#!/usr/bin/env python3
"""Binary-cache tool for the R2 cache: closure walking over narinfos, push and
garbage collection. Stdlib only; all IO is injectable so tests pass fakes."""

import argparse
import concurrent.futures
import dataclasses
import datetime
import glob
import http.client
import json
import os
import re
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

LEGACY_CACHE = "https://noamsto-nix-config.cachix.org"
USER_AGENT = "nix-config-nix-cache/1"
MAX_CONCURRENCY = 8
STORE_DIR = "/nix/store"
RETRY_DELAYS = (1, 2, 4)
HASH_RE = re.compile(r"[0-9a-df-np-sv-z]{32}")

EVAL_APPLY = (
    'v: if v ? outPath then { "" = v.outPath; } else '
    "builtins.mapAttrs (_: d: let r = builtins.tryEval d.outPath; "
    "in if r.success then r.value else null) v"
)


class FetchError(Exception):
    pass


class EvalError(Exception):
    pass


@dataclasses.dataclass
class Narinfo:
    store_path: str
    url: str
    file_size: int
    references: list
    text: str


@dataclasses.dataclass
class Caches:
    r2_url: str
    public_key: str
    upstreams: list


@dataclasses.dataclass
class Node:
    name: str
    kind: str
    narinfo: Narinfo | None
    parents: set


def fetch_text(url, opener=urllib.request.urlopen, sleep=time.sleep):
    # Only 404 means absent. Cachix answers 403 to Python's default
    # User-Agent, and a transient error must never read as a missing path.
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for delay in (*RETRY_DELAYS, None):
        try:
            with opener(request, timeout=30) as response:
                return response.read().decode()
        except urllib.error.HTTPError as err:
            if err.code == 404:
                return None
            failure = err
        except (OSError, http.client.HTTPException) as err:
            # URLError is an OSError; this also covers read timeouts and
            # connections dropped mid-body.
            failure = err
        if delay is None:
            raise FetchError(f"{url}: {failure}") from failure
        sleep(delay)


def parse_narinfo(text):
    fields = {}
    for line in text.splitlines():
        key, sep, value = line.partition(": ")
        if sep:
            fields[key] = value.strip()
    references = fields.get("References", "").split()
    return Narinfo(
        store_path=fields["StorePath"],
        url=fields.get("URL", ""),
        file_size=int(fields.get("FileSize", 0)),
        references=references,
        text=text,
    )


def hash_of(path_or_name):
    name = os.path.basename(path_or_name.rstrip("/"))
    found = HASH_RE.match(name)
    if not found:
        raise ValueError(f"no store hash in {path_or_name!r}")
    return found.group(0)


def run_json(cmd, error=RuntimeError):
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise error(f"{' '.join(cmd[:3])} failed: {proc.stderr.strip()}")
    return json.loads(proc.stdout)


def load_caches(repo_root):
    apply = (
        "c: { r2 = c.r2; substituters = c.substituters; "
        "extraSubstituters = c.extraSubstituters; }"
    )
    data = run_json(
        [
            "nix",
            "eval",
            "--json",
            "--file",
            os.path.join(repo_root, "lib/caches.nix"),
            "--apply",
            apply,
        ]
    )
    r2_url = data["r2"]["url"]
    skip = (r2_url, LEGACY_CACHE)
    upstreams = [
        s for s in data["substituters"] + data["extraSubstituters"] if s not in skip
    ]
    return Caches(r2_url, data["r2"]["publicKey"], upstreams)


def eval_selector(selector):
    cmd = ["nix", "eval", "--json", f".#{selector}", "--apply", EVAL_APPLY]
    return run_json(cmd, EvalError)


def local_path_info(hash_):
    """Narinfo for a path in the local store, or None. Absence is `null` in
    the JSON with exit 0, so the exit code says nothing about it."""
    matches = glob.glob(f"{STORE_DIR}/{hash_}-*")
    if not matches:
        return None
    info = run_json(
        ["nix", "path-info", "--json", "--json-format", "1", matches[0]]
    )
    entry = info.get(matches[0])
    if not entry:
        return None
    return Narinfo(
        store_path=matches[0],
        url="",
        file_size=0,
        references=[os.path.basename(r) for r in entry.get("references", [])],
        text="",
    )


def lookup(hash_, caches, fetch=fetch_text, local=local_path_info):
    sources = [("r2", caches.r2_url)]
    sources += [("upstream", u) for u in caches.upstreams]
    for kind, base in sources:
        text = fetch(f"{base.rstrip('/')}/{hash_}.narinfo")
        if text is not None:
            return kind, parse_narinfo(text)
    info = local(hash_)
    if info is not None:
        return "local", info
    text = fetch(f"{LEGACY_CACHE}/{hash_}.narinfo")
    if text is not None:
        return "legacy", parse_narinfo(text)
    return "absent", None


def walk(root_paths, lookup_fn, max_workers=MAX_CONCURRENCY):
    nodes = {}
    # hash -> (base name, parent hashes) for the level about to be looked up
    frontier = {
        hash_of(p): (os.path.basename(p.rstrip("/")), set()) for p in root_paths
    }
    with concurrent.futures.ThreadPoolExecutor(max_workers) as pool:
        while frontier:
            hashes = list(frontier)
            results = list(pool.map(lookup_fn, hashes))
            discovered = {}
            for hash_, (kind, info) in zip(hashes, results):
                name, parents = frontier[hash_]
                nodes[hash_] = Node(name, kind, info, parents)
                for ref in info.references if info else []:
                    ref_hash = hash_of(ref)
                    if ref_hash == hash_:
                        continue
                    if ref_hash in nodes:
                        nodes[ref_hash].parents.add(hash_)
                    elif ref_hash in frontier:
                        frontier[ref_hash][1].add(hash_)
                    else:
                        entry = discovered.setdefault(
                            ref_hash, (os.path.basename(ref), set())
                        )
                        entry[1].add(hash_)
            frontier = discovered
    return nodes


def pop_secrets(names):
    return {n: os.environ.pop(n) for n in names if n in os.environ}


REPO_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)


def extend_nix_config(existing, url, public_key):
    """NIX_CONFIG value with the R2 cache appended after any existing value."""
    lines = [existing.rstrip("\n")] if existing.strip() else []
    lines.append(f"extra-substituters = {url}")
    lines.append(f"extra-trusted-public-keys = {public_key}")
    return "\n".join(lines) + "\n"


def render_github_env(name, value, delimiter=None):
    """`$GITHUB_ENV` heredoc entry. The delimiter is random so the value
    cannot terminate it early."""
    delimiter = delimiter or f"EOF_{secrets.token_hex(16)}"
    return f"{name}<<{delimiter}\n{value.rstrip(chr(10))}\n{delimiter}\n"


def sentinel_expr(run_id, attempt):
    # A fresh derivation name exists in no cache. Nix stops at the first
    # substituter that has a path, so only such a path forces R2 to be asked.
    return (
        f'derivation {{ name = "r2-probe-{run_id}-{attempt}"; '
        'system = builtins.currentSystem; builder = "/bin/sh"; }'
    )


def matching_lines(output, url):
    """Lines of the sentinel's output that mention the cache URL, and whether
    one of them is a query for a path on it."""
    lines = [line for line in output.splitlines() if url in line]
    query = re.compile(r"querying info about .* on '" + re.escape(url) + "'")
    return lines, any(query.search(line) for line in lines)


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    return 1


def cmd_substituter(args):
    caches = load_caches(REPO_ROOT)
    url = caches.r2_url
    child_env = dict(os.environ)
    child_env["NIX_CONFIG"] = extend_nix_config(
        child_env.get("NIX_CONFIG", ""), url, caches.public_key
    )
    env_file = child_env.get("GITHUB_ENV")
    if env_file:
        with open(env_file, "a") as handle:
            handle.write(render_github_env("NIX_CONFIG", child_env["NIX_CONFIG"]))

    proc = subprocess.run(
        ["nix", "config", "show", "substituters"],
        capture_output=True,
        text=True,
        env=child_env,
        check=False,
    )
    if proc.returncode != 0:
        return fail(f"nix config show substituters failed: {proc.stderr.strip()}")
    if url not in proc.stdout.split():
        return fail(
            f"{url} is not in the effective substituters: {proc.stdout.strip()}"
        )

    try:
        info = fetch_text(url.rstrip("/") + "/nix-cache-info")
    except FetchError as err:
        return fail(str(err))
    if info is None or f"StoreDir: {STORE_DIR}" not in info:
        return fail(f"{url}/nix-cache-info is missing or lacks StoreDir: {STORE_DIR}")

    run_id = child_env.get("GITHUB_RUN_ID") or "local"
    attempt = child_env.get("GITHUB_RUN_ATTEMPT") or "0"
    proc = subprocess.run(
        [
            "nix",
            "build",
            "--dry-run",
            "--impure",
            "-vvv",
            "--option",
            "narinfo-cache-negative-ttl",
            "0",
            "--option",
            "narinfo-cache-positive-ttl",
            "0",
            "--expr",
            sentinel_expr(run_id, attempt),
        ],
        capture_output=True,
        text=True,
        env=child_env,
        check=False,
    )
    lines, queried = matching_lines(proc.stdout + proc.stderr, url)
    print("\n".join(lines))
    if not queried:
        return fail(f"nix never queried {url} for the sentinel path")
    return 0


@dataclasses.dataclass
class Need:
    paths: set
    unresolved: set


@dataclasses.dataclass
class Verdict:
    failures: list
    warnings: list


class RealiseError(Exception):
    pass


def compute_need(nodes, pin_hashes):
    """Hashes to upload, and hashes found on no source. A pin is needed unless
    R2 has it, even when an upstream serves it: the kernel outputs must exist
    in R2 itself. A pin found nowhere is built by `realise`, so it is needed."""
    paths, unresolved = set(), set()
    for hash_, node in nodes.items():
        if node.kind in ("local", "legacy"):
            paths.add(hash_)
        elif node.kind == "upstream":
            if hash_ in pin_hashes:
                paths.add(hash_)
        elif node.kind == "absent":
            (paths if hash_ in pin_hashes else unresolved).add(hash_)
    return Need(paths, unresolved)


def stub_text(node):
    """Narinfo text a stub may carry: only a path some cache really serves,
    so that no uploaded narinfo refers to a path R2 will not have."""
    if node is None or node.kind not in ("r2", "upstream") or node.narinfo is None:
        return None
    return node.narinfo.text or None


def prune_unuploadable(need_hashes, nodes):
    """Fixpoint: drop needed paths with a reference that is neither needed nor
    stub-able, and then their dependents. `nix copy` refuses a path whose
    reference is not valid in the destination. Returns (kept, dropped)."""
    kept = set(need_hashes)
    changed = True
    while changed:
        changed = False
        for hash_ in sorted(kept):
            info = nodes[hash_].narinfo
            for ref in info.references if info else []:
                ref_hash = hash_of(ref)
                if ref_hash == hash_ or ref_hash in kept:
                    continue
                if stub_text(nodes.get(ref_hash)) is None:
                    kept.discard(hash_)
                    changed = True
                    break
    return kept, set(need_hashes) - kept


def stub_refs(need_hashes, all_nodes):
    """hash -> narinfo text for each reference (not self) of a needed path
    that lies outside the need set."""
    stubs = {}
    for hash_ in need_hashes:
        info = all_nodes[hash_].narinfo
        for ref in info.references if info else []:
            ref_hash = hash_of(ref)
            if ref_hash == hash_ or ref_hash in need_hashes:
                continue
            text = stub_text(all_nodes.get(ref_hash))
            if text is not None:
                stubs[ref_hash] = text
    return stubs


def store_path(node):
    return f"{STORE_DIR}/{node.name}"


def chunked(items, size=500):
    items = list(items)
    for start in range(0, len(items), size):
        yield items[start : start + size]


def realise(pins, need_paths):
    """Build pins by selector, then substitute or build the need paths.
    Returns the full store paths that stayed invalid."""
    for selector in pins:
        proc = subprocess.run(
            ["nix", "build", "--no-link", f".#{selector}"], check=False
        )
        if proc.returncode != 0:
            raise RealiseError(f"building pin {selector} failed")
    for chunk in chunked(need_paths):
        subprocess.run(
            ["nix-store", "--realise", "--ignore-unknown", *chunk],
            stdout=subprocess.DEVNULL,
            check=False,
        )
    invalid = []
    for chunk in chunked(need_paths):
        proc = subprocess.run(
            ["nix-store", "--check-validity", "--print-invalid", *chunk],
            capture_output=True,
            text=True,
            check=False,
        )
        invalid += proc.stdout.split()
    return set(invalid)


def stage(paths, stubs, stage_dir, key_text):
    """Copy `paths` signed into a file:// binary cache at `stage_dir`.

    Staged locally instead of `nix copy --to s3://`: a binary cache store
    requires every reference to be valid in the destination, and references
    that live in R2 or upstream are not in the local store. Stub narinfos of
    those references stand in for them and are deleted again after the copy,
    so they are never uploaded."""
    os.makedirs(stage_dir, exist_ok=True)
    stub_files = []
    key_fd, key_file = tempfile.mkstemp(
        prefix="nix-cache-key-", dir=os.environ.get("RUNNER_TEMP") or None
    )
    try:
        with os.fdopen(key_fd, "w") as handle:
            os.fchmod(handle.fileno(), 0o600)
            handle.write(key_text)
        for hash_, text in stubs.items():
            stub_file = os.path.join(stage_dir, f"{hash_}.narinfo")
            with open(stub_file, "w") as handle:
                handle.write(text)
            stub_files.append(stub_file)
        store_url = f"file://{stage_dir}?secret-key={key_file}&compression=zstd"
        proc = subprocess.run(
            ["nix", "copy", "--no-recursive", "--to", store_url, "--stdin"],
            input="\n".join(paths) + "\n",
            text=True,
            check=False,
        )
        if proc.returncode != 0:
            raise RuntimeError("nix copy into the staging store failed")
    finally:
        os.unlink(key_file)
        for stub_file in stub_files:
            if os.path.exists(stub_file):
                os.unlink(stub_file)


def rclone_binary():
    """rclone from the store, resolved with no credentials in the environment
    so that evaluating a bumped input can never see them."""
    proc = subprocess.run(
        [
            "nix",
            "build",
            "--no-link",
            "--print-out-paths",
            "--inputs-from",
            ".",
            "nixpkgs#rclone.out",
        ],
        capture_output=True,
        text=True,
        cwd=REPO_ROOT,
        check=False,
    )
    lines = [line for line in proc.stdout.splitlines() if line.strip()]
    if proc.returncode != 0 or len(lines) != 1:
        raise RuntimeError(
            f"expected one rclone output, got {lines!r}: {proc.stderr.strip()}"
        )
    return os.path.join(lines[0].strip(), "bin", "rclone")


def r2_env(endpoint, creds):
    """Environment for an rclone child: the `r2` remote and its credentials."""
    env = dict(os.environ)
    if "://" not in endpoint:
        endpoint = f"https://{endpoint}"
    env.update(
        {
            "RCLONE_CONFIG_R2_TYPE": "s3",
            "RCLONE_CONFIG_R2_PROVIDER": "Cloudflare",
            "RCLONE_CONFIG_R2_ACCESS_KEY_ID": creds["R2_ACCESS_KEY_ID"],
            "RCLONE_CONFIG_R2_SECRET_ACCESS_KEY": creds["R2_SECRET_ACCESS_KEY"],
            "RCLONE_CONFIG_R2_ENDPOINT": endpoint,
            "RCLONE_CONFIG_R2_NO_CHECK_BUCKET": "true",
            "RCLONE_CONFIG_R2_REGION": "auto",
        }
    )
    return env


def upload(stage_dir, bucket, endpoint, creds):
    """Credentials reach only the rclone child, through its environment."""
    rclone = rclone_binary()
    env = r2_env(endpoint, creds)
    # nars first: a narinfo must never point at a nar that is not there yet.
    steps = []
    nar_dir = os.path.join(stage_dir, "nar")
    if os.path.isdir(nar_dir):
        steps.append(
            [rclone, "copy", nar_dir, f"r2:{bucket}/nar", "--transfers", "8"]
        )
    steps.append(
        [
            rclone, "copy", stage_dir, f"r2:{bucket}", "--max-depth", "1",
            "--include", "*.narinfo", "--transfers", "8",
        ]
    )
    for cmd in steps:
        if subprocess.run(cmd, env=env, check=False).returncode != 0:
            raise RuntimeError(f"rclone {cmd[1]} to R2 failed")


def verify_args(pin_paths, url, key):
    # `nix store verify` with no paths falls back to the flake's default
    # package and exits 1, so jobs without pins must skip it.
    if not pin_paths:
        return None
    return [
        "nix", "store", "verify", "--store", url,
        "--trusted-public-keys", key, *pin_paths,
    ]


def classify(uploaded, nodes, pin_hashes):
    """Verdict after the upload. Failure: a pin, or something this run
    uploaded, is not in R2. Warning only: any other reachable path on no
    cache, which this run could not produce and cannot repair."""
    failures, warnings = [], []
    for hash_, node in sorted(nodes.items()):
        if node.kind == "r2":
            continue
        if hash_ in pin_hashes:
            failures.append(f"pin {node.name} is not in R2")
        elif hash_ in uploaded:
            failures.append(f"{node.name} was uploaded but is not in R2")
        elif node.kind in ("absent", "local", "legacy"):
            warnings.append(node.name)
    return Verdict(failures, warnings)


def eval_roots(selectors):
    """Roots tolerate a selector or attribute that fails to evaluate."""
    paths = []
    for selector in selectors:
        try:
            result = eval_selector(selector)
        except EvalError as err:
            print(f"::warning::skipping root {selector}: {err}")
            continue
        for attr, path in result.items():
            if path is None:
                print(f"::warning::skipping root {selector}.{attr}: does not evaluate")
            else:
                paths.append(path)
    return paths


def eval_pins(selectors):
    """selector -> output path. No tolerance: a pin without a path could
    never be checked against R2."""
    pins = {}
    for selector in selectors:
        path = eval_selector(selector).get("")
        if path is None:
            raise EvalError(f"pin {selector} does not evaluate to one output path")
        pins[selector] = path
    return pins


def cmd_push(args):
    key = args.secrets.get("NIX_CACHE_SIGNING_KEY")
    if not key:
        return fail("NIX_CACHE_SIGNING_KEY is not set")
    stage_only = args.stage_only is not None
    if not stage_only:
        for name in ("R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"):
            if not args.secrets.get(name):
                return fail(f"{name} is not set")
        if not args.r2_bucket:
            return fail("R2_BUCKET is not set (or pass --r2-bucket)")
        if not args.r2_endpoint:
            return fail("R2_ENDPOINT is not set (or pass --r2-endpoint)")

    with open(os.path.join(REPO_ROOT, "scripts/nix-cache/roots.json")) as handle:
        jobs = json.load(handle)
    if args.job not in jobs:
        return fail(f"unknown job {args.job!r}; known: {', '.join(sorted(jobs))}")
    job = jobs[args.job]

    caches = load_caches(REPO_ROOT)
    r2_prefix = caches.r2_url.rstrip("/") + "/"

    def fetch(url):
        # --stage-only treats R2 as empty without touching the network.
        if stage_only and url.startswith(r2_prefix):
            return None
        return fetch_text(url)

    def lookup_fn(hash_):
        return lookup(hash_, caches, fetch=fetch)

    try:
        pins = eval_pins(job["pins"])
        root_paths = eval_roots(job["roots"]) + list(pins.values())
        pin_hashes = {hash_of(p) for p in pins.values()}
        nodes = walk(root_paths, lookup_fn)
        need = compute_need(nodes, pin_hashes)
        uploaded = set()

        if need.paths:
            missing_pins = [
                s for s, p in pins.items() if nodes[hash_of(p)].kind != "r2"
            ]
            invalid = realise(
                missing_pins, [store_path(nodes[h]) for h in sorted(need.paths)]
            )
            # Realising makes paths local and reveals the references of a pin
            # that was found nowhere, so look again.
            nodes = walk(root_paths, lookup_fn)
            need = compute_need(nodes, pin_hashes)
            need.paths -= {hash_of(p) for p in invalid}
            kept, dropped = prune_unuploadable(need.paths, nodes)
            for hash_ in sorted(dropped | need.unresolved):
                print(f"not uploadable: {nodes[hash_].name}")
            if kept:
                stage_dir = args.stage_only or tempfile.mkdtemp(
                    prefix="nix-cache-stage-",
                    dir=os.environ.get("RUNNER_TEMP") or None,
                )
                stage(
                    [store_path(nodes[h]) for h in sorted(kept)],
                    stub_refs(kept, nodes),
                    stage_dir,
                    key,
                )
                if not stage_only:
                    upload(stage_dir, args.r2_bucket, args.r2_endpoint, args.secrets)
                uploaded = kept
            print(f"{len(uploaded)} paths staged")

        if stage_only:
            print(f"staged in {args.stage_only}; upload and verify skipped")
            return 0

        if uploaded:
            nodes = walk(root_paths, lookup_fn)
    except (FetchError, EvalError, RealiseError, RuntimeError) as err:
        return fail(str(err))

    verdict = classify(uploaded, nodes, pin_hashes)
    if verdict.warnings:
        print(
            "::warning::not on any cache and not produced by this run: "
            + ", ".join(verdict.warnings)
        )
    for failure in verdict.failures:
        print(f"error: {failure}", file=sys.stderr)
    code = 1 if verdict.failures else 0
    verify = verify_args(sorted(pins.values()), caches.r2_url, caches.public_key)
    if verify and subprocess.run(verify, check=False).returncode != 0:
        print("error: nix store verify of the pins failed", file=sys.stderr)
        code = 1
    return code


@dataclasses.dataclass
class Obj:
    key: str
    size: int
    mtime: datetime.datetime


@dataclasses.dataclass
class GcPlan:
    delete_narinfos: list
    delete_nars: list
    retained_bytes: int
    abort_reason: str | None = None


GC_HOUR = datetime.timedelta(hours=1)
GC_MAX_DELETE_FRACTION = 0.6
GC_WARN_BYTES = 8 * 10**9


def parse_modtime(text):
    """rclone ModTime: RFC 3339 with nanoseconds and a Z suffix. fromisoformat
    takes at most microseconds, so the fraction is truncated."""
    text = re.sub(r"\.(\d{1,6})\d*", lambda m: "." + m.group(1), text)
    parsed = datetime.datetime.fromisoformat(text)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=datetime.UTC)
    return parsed


def is_narinfo_key(key):
    return key.endswith(".narinfo") and "/" not in key


def narinfo_url(text):
    for line in text.splitlines():
        key, sep, value = line.partition(": ")
        if sep and key == "URL":
            return value.strip()
    return None


def plan_gc(
    objects, narinfo_text, live_hashes, pin_hashes, reference_holes, force, now,
    grace, budget,
):
    """Pure planner. Only `*.narinfo` at the root and `nar/*` are ever counted
    or deleted; `nix-cache-info` and anything else is ignored."""
    counted = [o for o in objects if is_narinfo_key(o.key) or o.key.startswith("nar/")]
    # A listed narinfo without text vanished before it was fetched.
    narinfos = {
        o.key: o for o in counted if is_narinfo_key(o.key) and o.key in narinfo_text
    }
    nars = {o.key: o for o in counted if o.key.startswith("nar/")}
    total_bytes = sum(o.size for o in counted)

    def abort(reason):
        return GcPlan([], [], total_bytes, reason)

    if not narinfos:
        return abort("the listing has no narinfos")
    present = {k[: -len(".narinfo")] for k in narinfos}
    missing = sorted(pin_hashes - present)
    if missing:
        return abort(f"pin not in R2: {', '.join(missing)}")
    if reference_holes:
        return abort(
            "reference found on no cache: " + ", ".join(sorted(reference_holes))
        )

    live = live_hashes | pin_hashes
    url_of = {k: narinfo_url(narinfo_text[k]) for k in narinfos}

    def age(obj):
        return now - obj.mtime

    kept = {
        k
        for k, o in narinfos.items()
        if k[: -len(".narinfo")] in live or age(o) <= grace
    }
    refcount = {}
    for k in kept:
        refcount[url_of[k]] = refcount.get(url_of[k], 0) + 1
    kept_nars = {k for k, o in nars.items() if k in refcount or age(o) <= grace}
    retained = sum(narinfos[k].size for k in kept) + sum(
        nars[k].size for k in kept_nars
    )

    if retained > budget:
        evictable = sorted(
            (
                k
                for k in kept
                if k[: -len(".narinfo")] not in live and age(narinfos[k]) >= GC_HOUR
            ),
            key=lambda k: narinfos[k].mtime,
        )
        for k in evictable:
            if retained <= budget:
                break
            kept.discard(k)
            retained -= narinfos[k].size
            url = url_of[k]
            refcount[url] -= 1
            if refcount[url] == 0 and url in kept_nars and age(nars[url]) >= GC_HOUR:
                kept_nars.discard(url)
                retained -= nars[url].size
    if retained > budget:
        orphans = sorted(
            (
                k
                for k in kept_nars
                if refcount.get(k, 0) == 0 and age(nars[k]) >= GC_HOUR
            ),
            key=lambda k: nars[k].mtime,
        )
        for k in orphans:
            if retained <= budget:
                break
            kept_nars.discard(k)
            retained -= nars[k].size

    delete_narinfos = sorted(set(narinfos) - kept)
    delete_nars = sorted(set(nars) - kept_nars)
    deleted = len(delete_narinfos) + len(delete_nars)
    if not force and deleted / len(counted) > GC_MAX_DELETE_FRACTION:
        return abort(
            f"would delete {deleted} of {len(counted)} objects "
            f"(over {GC_MAX_DELETE_FRACTION:.0%}); pass --force to override"
        )
    return GcPlan(delete_narinfos, delete_nars, retained)


def rclone_delete(keys, remote, rclone, env):
    """Delete exactly `keys`, listed in a temp file; never a filter or prefix."""
    if not keys:
        return
    fd, path = tempfile.mkstemp(prefix="nix-cache-gc-")
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write("\n".join(keys) + "\n")
        proc = subprocess.run(
            [rclone, "delete", "--files-from", path, remote], env=env, check=False
        )
        if proc.returncode != 0:
            raise RuntimeError("rclone delete failed")
    finally:
        os.unlink(path)


def apply_gc(plan, remote, rclone, env, relist):
    # Narinfos go first so a narinfo never outlives its nar. `relist` returns
    # the nars referenced by narinfos present now: an upload that landed since
    # the plan was made may reference a nar the plan marked for deletion, and
    # that nar must survive.
    rclone_delete(plan.delete_narinfos, remote, rclone, env)
    if not plan.delete_nars:
        return
    referenced = relist()
    rclone_delete(
        [k for k in plan.delete_nars if k not in referenced], remote, rclone, env
    )


def list_objects(remote, rclone, env):
    proc = subprocess.run(
        [rclone, "lsjson", "-R", "--files-only", "--use-server-modtime", remote],
        capture_output=True,
        text=True,
        env=env,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"rclone lsjson failed: {proc.stderr.strip()}")
    return [
        Obj(e["Path"], e["Size"], parse_modtime(e["ModTime"]))
        for e in json.loads(proc.stdout)
    ]


def fetch_narinfos(keys, base_url, fetch=fetch_text):
    """key -> text for each narinfo that exists; a 404 means it just vanished."""
    keys = list(keys)
    base = base_url.rstrip("/")
    with concurrent.futures.ThreadPoolExecutor(MAX_CONCURRENCY) as pool:
        texts = pool.map(lambda k: fetch(f"{base}/{k}"), keys)
        return {k: t for k, t in zip(keys, texts) if t is not None}


def mark(jobs, lookup_fn):
    """(live hashes, pin hashes, reference holes) over every job. Roots are
    strict: an evaluation error or a null attribute raises EvalError."""
    live, pin_hashes, holes = set(), set(), set()
    for job in jobs.values():
        pins = eval_pins(job["pins"])
        roots = list(pins.values())
        for selector in job["roots"]:
            for attr, path in eval_selector(selector).items():
                if path is None:
                    raise EvalError(f"root {selector}.{attr} does not evaluate")
                roots.append(path)
        nodes = walk(roots, lookup_fn)
        pin_hashes |= {hash_of(p) for p in pins.values()}
        for hash_, node in nodes.items():
            if node.kind == "r2":
                live.add(hash_)
            elif node.kind == "absent" and node.parents:
                holes.add(hash_)
    return live | pin_hashes, pin_hashes, holes


def cmd_gc(args):
    for name in ("R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"):
        if not args.secrets.get(name):
            return fail(f"{name} is not set")
    if not args.r2_bucket:
        return fail("R2_BUCKET is not set (or pass --r2-bucket)")
    if not args.r2_endpoint:
        return fail("R2_ENDPOINT is not set (or pass --r2-endpoint)")

    with open(os.path.join(REPO_ROOT, "scripts/nix-cache/roots.json")) as handle:
        jobs = json.load(handle)
    caches = load_caches(REPO_ROOT)

    try:
        live, pin_hashes, holes = mark(
            jobs, lambda hash_: lookup(hash_, caches, fetch=fetch_text)
        )
        rclone = rclone_binary()
        env = r2_env(args.r2_endpoint, args.secrets)
        remote = f"r2:{args.r2_bucket}"

        objects = list_objects(remote, rclone, env)
        texts = fetch_narinfos(
            (o.key for o in objects if is_narinfo_key(o.key)), caches.r2_url
        )
    except (FetchError, EvalError, RuntimeError) as err:
        print(f"::warning::gc aborted: {err}")
        return fail(str(err))

    plan = plan_gc(
        objects, texts, live, pin_hashes, holes, args.force,
        datetime.datetime.now(datetime.UTC),
        datetime.timedelta(days=args.grace_days), args.budget_bytes,
    )
    if plan.abort_reason:
        print(f"::warning::gc aborted: {plan.abort_reason}")
        return 0

    sizes = {o.key: o.size for o in objects}
    print(
        f"delete {len(plan.delete_narinfos)} narinfos "
        f"({sum(sizes[k] for k in plan.delete_narinfos)} bytes), "
        f"{len(plan.delete_nars)} nars "
        f"({sum(sizes[k] for k in plan.delete_nars)} bytes); "
        f"retain {plan.retained_bytes} bytes"
    )
    if plan.retained_bytes > GC_WARN_BYTES:
        print(f"::warning::gc retains {plan.retained_bytes} bytes, over 8 GB")
    if not args.delete:
        print("dry run: nothing deleted (pass --delete)")
        return 0

    def relist():
        current = [
            o.key for o in list_objects(remote, rclone, env) if is_narinfo_key(o.key)
        ]
        for key in current:
            if key not in texts:
                texts.update(fetch_narinfos([key], caches.r2_url))
        return {
            u for u in (narinfo_url(texts[k]) for k in current if k in texts) if u
        }

    try:
        apply_gc(plan, remote, rclone, env, relist)
    except (FetchError, RuntimeError) as err:
        return fail(str(err))
    return 0


def build_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("substituter", help="add the R2 cache as an extra substituter and prove Nix queries it")
    p.set_defaults(func=cmd_substituter)
    p = sub.add_parser("push", help="upload missing closure paths to R2")
    p.add_argument("--job", required=True)
    p.add_argument("--stage-only", metavar="DIR", help="stage and sign into DIR; R2 treated as empty, no upload or verify")
    p.add_argument("--r2-bucket", default=os.environ.get("R2_BUCKET"))
    p.add_argument("--r2-endpoint", default=os.environ.get("R2_ENDPOINT"))
    p.set_defaults(func=cmd_push)
    p = sub.add_parser("gc", help="delete unreachable objects from R2")
    p.add_argument("--delete", action="store_true", help="delete; default is a dry run")
    p.add_argument("--force", action="store_true", help="allow deleting over 60%% of objects")
    p.add_argument("--grace-days", type=float, default=3)
    p.add_argument("--budget-bytes", type=int, default=7 * 10**9)
    p.add_argument("--r2-bucket", default=os.environ.get("R2_BUCKET"))
    p.add_argument("--r2-endpoint", default=os.environ.get("R2_ENDPOINT"))
    p.set_defaults(func=cmd_gc)
    return parser


def main(argv=None):
    secrets = pop_secrets(
        ["NIX_CACHE_SIGNING_KEY", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY"]
    )
    args = build_parser().parse_args(argv)
    args.secrets = secrets
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

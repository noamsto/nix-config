"""Pure decision logic of the flake-update bot: input sets, log parsing,
leaf classification, pin decisions and PR/issue rendering. No IO."""

import copy
import datetime
import fnmatch
import json
import re

ALWAYS_EXCLUDED = ("nixpkgs-fallback", "nixpkgs-bambu")

# Library, toolkit, kernel and toolchain families: pinning one of these to an
# older nixpkgs would mix ABIs, so they are never treated as leaves.
DENYLIST = (
    "lib*",
    "linux*",
    "kernel*",
    "firmware*",
    "python*",
    "perl*",
    "ruby*",
    "lua*",
    "php*",
    "nodejs*",
    "ghc*",
    "go",
    "go_*",
    "rustc*",
    "cargo*",
    "jdk*",
    "openjdk*",
    "qt*",
    "kde*",
    "gst*",
    "gstreamer*",
    "glib*",
    "gtk*",
    "openssl*",
    "glibc*",
    "gcc*",
    "clang*",
    "llvm*",
    "stdenv*",
    "mesa*",
    "systemd*",
    "cuda*",
    "rocm*",
    "ffmpeg*",
    "pipewire*",
    "wayland*",
    "xorg*",
    "nss*",
    "nspr*",
    "icu*",
    "boost*",
    "zlib*",
    "electron*",
    "dbus*",
    "polkit*",
)

STALE_DAYS = 14
STALE_FLAG = "⚠ missing security fixes"
EXCERPT_LINES = 30

_ANSI = re.compile(r"\x1b\[[0-9;]*m")
# nix-fast-build prefixes every nix line with "<attr>> ".
_ATTR_PREFIX = re.compile(r"^[^\s>]+> ")
_DRV = r"'(/nix/store/[^']+\.drv)'"
_CANNOT_BUILD = re.compile(r"^error: Cannot build " + _DRV)
_HASH_MISMATCH = re.compile(r"^error: hash mismatch in fixed-output derivation " + _DRV)
_LEGACY_BUILDER = re.compile(r"^error: builder for " + _DRV + r" failed")
_LEGACY_DEPS = re.compile(r"^error: \d+ dependencies of derivation " + _DRV + r" failed")
_STORE_HASH = re.compile(r"^[0-9a-z]{32}-")
_BACKTICKS = re.compile(r"`+")

PINNED_STILL_FAILING = (
    "pinned-still-failing (the pin did not take effect — e.g. a later overlay in"
    " lib/overlays.nix defines this attr — or the fallback build fails too)"
)


def _root_inputs(lock: dict) -> dict:
    return lock["nodes"]["root"].get("inputs", {})


def _root_node(lock: dict, name: str) -> dict | None:
    ref = _root_inputs(lock).get(name)
    # A list is a `follows` path, not an independently locked node.
    if not isinstance(ref, str):
        return None
    return lock["nodes"].get(ref)


def input_sets(lock: dict, frozen: list[str]) -> tuple[list[str], list[str]]:
    skip = set(ALWAYS_EXCLUDED) | set(frozen)
    nixpkgs_side, inputs_side = [], []
    for name in sorted(_root_inputs(lock)):
        node = _root_node(lock, name)
        if name in skip or node is None:
            continue
        orig = node.get("original", {})
        is_nixpkgs = (
            orig.get("type") == "github"
            and orig.get("owner", "").lower() == "nixos"
            and orig.get("repo") == "nixpkgs"
            and "ref" in orig
            and "rev" not in orig
        )
        (nixpkgs_side if is_nixpkgs else inputs_side).append(name)
    return nixpkgs_side, inputs_side


def locked_rev(lock: dict, name: str) -> str | None:
    node = _root_node(lock, name)
    return node.get("locked", {}).get("rev") if node else None


def drop_auto_pins(pins_doc: dict) -> dict:
    doc = copy.deepcopy(pins_doc)
    doc["pins"] = [p for p in doc.get("pins", []) if p.get("mode") != "auto"]
    return doc


def dump_pins(pins_doc: dict) -> str:
    return json.dumps(pins_doc, indent=2) + "\n"


def failed_steps(steps: dict, expected: list[str]) -> list[str]:
    """Fail closed: an expected step that is missing or did not succeed
    (failure, skipped after a setup failure, cancelled on timeout) failed."""
    if not isinstance(steps, dict):
        steps = {}
    return [
        s
        for s in expected
        if not isinstance(steps.get(s), dict) or steps[s].get("outcome") != "success"
    ]


def step_failure_why(step: str, outcome) -> str:
    if outcome is None:
        return f"step {step} has no recorded outcome (it never ran)"
    verb = {
        "failure": "failed",
        "skipped": "was skipped",
        "cancelled": "was cancelled",
    }.get(outcome, f"ended {outcome}")
    return f"step {step} {verb} without a failed derivation (eval, setup or structural error)"


def _clean(line: str) -> str:
    return _ATTR_PREFIX.sub("", _ANSI.sub("", line), count=1).rstrip()


def parse_log(text: str) -> dict:
    # Only "\n" ends a line: splitlines() also breaks on \x0b, \x0c, \x1c-\x1e,
    # \x85 and U+2028/9, which builder output can contain to forge an
    # unindented error line.
    lines = [_clean(line.removesuffix("\r")) for line in text.split("\n")]
    roots, dep_failed, seen = [], [], set()

    def block(i: int) -> list[str]:
        # The error's detail lines are indented; the next unindented line ends it.
        out = []
        for line in lines[i + 1 :]:
            if line and not line[0].isspace():
                break
            out.append(line)
        return out

    def add_root(drv: str, kind: str, i: int) -> None:
        if drv not in seen:
            seen.add(drv)
            excerpt = [lines[i], *block(i)][:EXCERPT_LINES]
            roots.append({"drv": drv, "kind": kind, "excerpt": "\n".join(excerpt)})

    def add_dep(drv: str) -> None:
        if drv not in dep_failed:
            dep_failed.append(drv)

    for i, line in enumerate(lines):
        if m := _CANNOT_BUILD.match(line):
            reason = next(
                (b.strip() for b in block(i) if b.strip().startswith("Reason:")), ""
            )
            if "builder failed" in reason:
                add_root(m[1], "builder", i)
            elif "dependencies failed" in reason:
                add_dep(m[1])
        elif m := _HASH_MISMATCH.match(line):
            add_root(m[1], "hash", i)
        elif m := _LEGACY_BUILDER.match(line):
            add_root(m[1], "builder", i)
        elif m := _LEGACY_DEPS.match(line):
            add_dep(m[1])
    return {"roots": roots, "depFailed": dep_failed}


def _basename(path: str) -> str:
    return path.rsplit("/", 1)[-1]


def drv_candidate(drv: str) -> str:
    name = _STORE_HASH.sub("", _basename(drv)).removesuffix(".drv")
    # Nix parseDrvName: the name ends at the first "-" not followed by a letter.
    for i, ch in enumerate(name[:-1]):
        if ch == "-" and not name[i + 1].isalpha():
            return name[:i]
    return name


def _path_list(value) -> list[str]:
    if isinstance(value, str):
        value = value.split()
    return [_basename(p) for p in value or [] if p]


def normalize_drvs(doc: dict) -> dict[str, dict]:
    # v4 wraps the drvs in "derivations"; legacy is the bare path-keyed map.
    drvs = doc.get("derivations", doc)
    out = {}
    for key, d in drvs.items():
        env = d.get("env", {})
        attrs = d.get("structuredAttrs")
        if attrs is None and "__json" in env:
            attrs = json.loads(env["__json"])
        src = attrs if attrs is not None else env
        input_drvs = d["inputs"]["drvs"] if "inputs" in d else d.get("inputDrvs", {})
        out[_basename(key)] = {
            "name": d["name"],
            "outputs": {
                o: _basename(v["path"])
                for o, v in d.get("outputs", {}).items()
                if v.get("path")
            },
            "inputDrvs": [_basename(k) for k in input_drvs],
            "buildInputs": _path_list(src.get("buildInputs")),
            "propagatedBuildInputs": _path_list(src.get("propagatedBuildInputs")),
        }
    return out


def classify_leaf(attr: str, drv: dict, referrers: list[dict]) -> tuple[bool, str]:
    if "." in attr:
        return False, "nested attr"
    for pattern in DENYLIST:
        if fnmatch.fnmatchcase(attr, pattern):
            return False, f"denylisted: {pattern}"
    for output in ("dev", "lib", "static"):
        if output in drv["outputs"]:
            return False, f"has {output} output"
    outs = set(drv["outputs"].values())
    for ref in referrers:
        if outs & set(ref["buildInputs"] + ref["propagatedBuildInputs"]):
            return False, f"linked into {ref['name']}"
    return True, "leaf"


def _block_reason(f: dict, pinned: set[str]) -> str:
    if f["attr"] is None:
        return "unmapped"
    if f["attr"] in pinned:
        return "pinned-still-failing"
    if f["notCausedByUpdate"] is None:
        return "base comparison unavailable"
    if f["notCausedByUpdate"]:
        return "not caused by the update"
    if f["missingInFallback"]:
        return "missing from nixpkgs-fallback"
    if not f["leaf"]:
        return f"not a leaf ({f['why']})"
    return ""


def decide(
    *,
    attempt: str,
    round_: int,
    max_rounds: int,
    reports: list[dict],
    expected_jobs: list[str],
    base_pins: dict,
    cur_pins: dict,
    nixpkgs_rev: str,
    nixpkgs_moved: bool,
    today: str,
    run_url: str,
) -> dict:
    pinned = {p["attr"] for p in cur_pins.get("pins", [])}
    failures = []
    for r in reports:
        for f in r["failures"]:
            f = {**f, "system": r["system"], "job": r["job"]}
            f["block"] = _block_reason(f, pinned)
            if f["block"] == "pinned-still-failing":
                f["why"] = PINNED_STILL_FAILING
            failures.append(f)

    def result(action: str, why: str, pins: dict = cur_pins) -> dict:
        return {"action": action, "pins": pins, "failures": failures, "why": why}

    jobs = {r["job"] for r in reports}
    missing = [j for j in expected_jobs if j not in jobs]
    if missing:
        return result("block", f"missing report: {', '.join(missing)}")
    if all(r["ok"] for r in reports):
        return result("land", "all builds passed")
    if attempt not in ("combined", "nixpkgs"):
        return result("block", f"the {attempt} attempt never repins")
    if failures and not nixpkgs_moved:
        return result(
            "block", "nixpkgs unchanged; the failure comes from a non-nixpkgs input"
        )
    if round_ >= max_rounds:
        return result("block", f"round cap reached ({round_}/{max_rounds})")
    if not failures:
        return result("block", "a build failed without a reported failure")
    blocking = [f for f in failures if f["block"]]
    if blocking:
        why = "; ".join(f"{f['attr'] or f['drv']}: {f['block']}" for f in blocking)
        return result("block", why)

    base_since = {p["attr"]: p.get("since") for p in base_pins.get("pins", [])}
    pins = copy.deepcopy(cur_pins)
    added = []
    for f in failures:
        if f["attr"] in added:
            continue
        added.append(f["attr"])
        pins.setdefault("pins", []).append(
            {
                "attr": f["attr"],
                "mode": "auto",
                "reason": f"failed on {f['system']} ({attempt} round {round_})"
                + (f": {run_url}" if run_url else ""),
                "since": base_since.get(f["attr"]) or today,
                "failedAt": nixpkgs_rev,
            }
        )
    return result("repin", f"pin {', '.join(added)}", pins)


def finalize(results: dict[str, str]) -> dict:
    order = ("combined", "nixpkgs", "inputs")
    land = next((a for a in order if results.get(a) == "land"), "")
    return {
        "land": land,
        "blocked": results.get("combined") != "land",
        "sides": [a for a in order if results.get(a) == "block"],
        "interaction": results.get("combined") == "block"
        and results.get("nixpkgs") == "land"
        and results.get("inputs") == "land",
    }


def fallback_advance(pins_doc: dict, base_lock: dict, new_lock: dict) -> str | None:
    new = locked_rev(new_lock, "nixpkgs")
    if (
        new
        and new != locked_rev(base_lock, "nixpkgs")
        and not pins_doc.get("pins")
        and locked_rev(new_lock, "nixpkgs-fallback") != new
    ):
        return new
    return None


def _short(node: dict | None) -> str:
    locked = (node or {}).get("locked", {})
    if "rev" in locked:
        return locked["rev"][:7]
    return locked.get("narHash", "").split("-", 1)[-1][:7]


def input_bumps(base_lock: dict, new_lock: dict) -> list[tuple[str, str, str]]:
    bumps = []
    for name in sorted(_root_inputs(new_lock)):
        node = _root_node(new_lock, name)
        if node is None:
            continue
        old, new = _short(_root_node(base_lock, name)), _short(node)
        if old != new:
            bumps.append((name, old, new))
    return bumps


def _age_days(since: str, today: str) -> int:
    return (datetime.date.fromisoformat(today) - datetime.date.fromisoformat(since)).days


def _pin_line(p: dict, today: str, flag: bool) -> str:
    line = f"- `{p['attr']}` ({p['mode']})"
    if p.get("since"):
        age = _age_days(p["since"], today)
        line += f", since {p['since']} ({age} days)"
        if flag and age > STALE_DAYS:
            line += f" {STALE_FLAG}"
    if p.get("reason"):
        line += f": {p['reason']}"
    return line


def render_pr_body(
    *,
    attempt: str,
    base_lock: dict,
    new_lock: dict,
    base_pins: dict,
    new_pins: dict,
    fallback_rev: str,
    fallback_age_days: int,
    advanced: bool,
    today: str,
    run_url: str,
) -> str:
    out = ["## Nightly flake update", "", f"Landed attempt: **{attempt}**"]
    if run_url:
        out.append(f"Run: {run_url}")

    out += ["", "### Input bumps", ""]
    bumps = input_bumps(base_lock, new_lock)
    if bumps:
        out += ["| Input | Old | New |", "| --- | --- | --- |"]
        out += [f"| `{n}` | `{o or '-'}` | `{w}` |" for n, o, w in bumps]
    else:
        out.append("No root input changed.")

    base = {p["attr"]: p for p in base_pins.get("pins", [])}
    new = {p["attr"]: p for p in new_pins.get("pins", [])}
    sections = (
        ("Added", [new[a] for a in new if a not in base], True),
        ("Removed", [base[a] for a in base if a not in new], False),
        ("Kept", [new[a] for a in new if a in base], True),
    )
    out += ["", "### Pins"]
    if not base and not new:
        out += ["", "No pins."]
    for title, pins, flag in sections:
        if pins:
            out += ["", f"{title}:", *(_pin_line(p, today, flag) for p in pins)]

    held = bool(new_pins.get("pins"))
    fallback = f"`nixpkgs-fallback`: `{fallback_rev[:7]}`, {fallback_age_days} days old"
    if not advanced and fallback_age_days > STALE_DAYS:
        fallback += f" {STALE_FLAG}" + (" (held back by live pins)" if held else "")
    out += [
        "",
        "### nixpkgs-fallback",
        "",
        fallback,
        f"Advanced: {'yes' if advanced else 'no'}",
        "",
        (
            "The fallback advances to the landed `nixpkgs` rev only when this update"
            " moved `nixpkgs` and no pin of any mode is live (a hold also points at"
            " the fallback)."
        ),
    ]
    return "\n".join(out).rstrip() + "\n"


def _fenced(text: str) -> list[str]:
    longest = max((len(m) for m in _BACKTICKS.findall(text)), default=0)
    fence = "`" * max(3, longest + 1)
    return [fence, text, fence]


def render_issue_body(
    *,
    final: dict,
    reports_by_attempt: dict[str, list[dict]],
    run_url: str,
    today: str | None = None,
) -> str:
    today = today or datetime.datetime.now(datetime.UTC).date().isoformat()
    out = ["## Nightly flake update blocked", ""]
    if run_url:
        out.append(f"Run: {run_url}")
    if final.get("interaction"):
        out.append(
            "Failed: a×b interaction (each half built alone, the combined tree did"
            " not; only the nixpkgs half landed)."
        )
    else:
        out.append(f"Failed: {', '.join(final.get('sides', [])) or 'none'}")
    if final.get("land"):
        out.append(f"Landed instead: **{final['land']}**")

    for attempt in ("combined", "nixpkgs", "inputs"):
        failures = [
            {**f, "system": r["system"], "job": r["job"]}
            for r in reports_by_attempt.get(attempt, [])
            for f in r["failures"]
        ]
        if not failures:
            continue
        out += ["", f"### {attempt}"]
        holds = []
        for f in failures:
            attr = f["attr"]
            out += [
                "",
                f"#### `{attr or f['drv']}` on {f['system']} (job {f['job']})",
                "",
                f"- drv: `{f['drv']}`",
                f"- mapped: {'yes' if attr else 'no'}",
                f"- leaf: {'yes' if f['leaf'] else 'no'}",
                f"- why: {f['why']}",
            ]
            if f.get("logExcerpt"):
                out += ["", *_fenced(f["logExcerpt"])]
            if attr and attempt != "inputs":
                hold = {"attr": attr, "mode": "hold", "reason": f["why"], "since": today}
                if (line := json.dumps(hold, ensure_ascii=False)) not in holds:
                    holds.append(line)
        out.append("")
        if attempt == "inputs":
            out.append(
                'To freeze the offending input, add it to `pins.json`: `"frozenInputs": [..., "<input>"]`'
            )
        elif holds:
            out += ["To hold these packages, add to `pins.json` `pins`:", ""]
            out += [f"`{line}`" for line in holds]
    return "\n".join(out).rstrip() + "\n"

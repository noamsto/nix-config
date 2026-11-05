#!/usr/bin/env python3
"""CLI + IO of the flake-update bot. All decisions live in botcore."""

import argparse
import datetime
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import botcore

TREES = ("combined", "nixpkgs", "inputs")
NIX = ["nix", "--extra-experimental-features", "nix-command flakes"]
CAND_RE = re.compile(r"^[A-Za-z0-9_+-][A-Za-z0-9._+-]*$")
FALLBACK_LINE = re.compile(
    r'(nixpkgs-fallback\.url = "github:nixos/nixpkgs/)[0-9a-f]{40}(";)'
)
REPORT_DIR = re.compile(r"^report-(combined|nixpkgs|inputs)-(\d+)-")


def set_output(key: str, value: str) -> None:
    line = f"{key}={value}"
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a") as fh:
            fh.write(line + "\n")
    else:
        print(line)


def today() -> str:
    return datetime.datetime.now(datetime.UTC).date().isoformat()


def run_url() -> str:
    env = os.environ
    if all(k in env for k in ("GITHUB_SERVER_URL", "GITHUB_REPOSITORY", "GITHUB_RUN_ID")):
        return f"{env['GITHUB_SERVER_URL']}/{env['GITHUB_REPOSITORY']}/actions/runs/{env['GITHUB_RUN_ID']}"
    return ""


def read_json(path, default=None):
    p = pathlib.Path(path)
    if not p.exists() and default is not None:
        return default
    return json.loads(p.read_text())


def write(path, text: str) -> None:
    p = pathlib.Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)


def sh(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


# --- prepare ---------------------------------------------------------------


def cmd_prepare(args) -> None:
    out = pathlib.Path(args.out)
    lock_path = pathlib.Path("flake.lock")
    base_bytes = lock_path.read_bytes()
    base_lock = json.loads(base_bytes)
    base_pins = read_json("pins.json", {"frozenInputs": [], "pins": []})
    nixpkgs_side, inputs_side = botcore.input_sets(
        base_lock, base_pins.get("frozenInputs", [])
    )
    names = {
        "combined": nixpkgs_side + inputs_side,
        "nixpkgs": nixpkgs_side,
        "inputs": inputs_side,
    }
    try:
        for tree in TREES:
            lock_path.write_bytes(base_bytes)
            if names[tree]:
                subprocess.run([*NIX, "flake", "update", *names[tree]], check=True)
            new_lock = json.loads(lock_path.read_text())
            if botcore.locked_rev(new_lock, "nixpkgs") != botcore.locked_rev(
                base_lock, "nixpkgs"
            ):
                pins = botcore.drop_auto_pins(base_pins)
            else:
                pins = base_pins
            pins_text = botcore.dump_pins(pins)
            write(out / tree / "flake.lock", lock_path.read_text())
            write(out / tree / "pins.json", pins_text)
            changed = new_lock != base_lock or pins_text != botcore.dump_pins(base_pins)
            set_output(f"{tree}-changed", "true" if changed else "false")
    finally:
        lock_path.write_bytes(base_bytes)


# --- analyze ---------------------------------------------------------------


def nix_str(value: str) -> str:
    return json.dumps(value).replace("${", "\\${")


class EvalFailed(Exception):
    pass


REV_RE = re.compile(r"^[0-9a-f]{40}$")

# Per candidate: its drvPath in `set`, or null when absent, not a derivation
# (nixos, lib, config) or failing with a catchable error.
DRV_APPLY = """set: let
  cands = builtins.fromJSON @CANDS@;
  drvOf = c: let
    r = builtins.tryEval (
      if set ? ${c}
      then let v = set.${c}; in
        if builtins.isAttrs v && v ? drvPath
        then builtins.unsafeDiscardStringContext v.drvPath
        else null
      else null);
  in if r.success then r.value else null;
in builtins.listToAttrs (map (c: { name = c; value = drvOf c; }) cands)"""

HAS_APPLY = """set: let
  cands = builtins.fromJSON @CANDS@;
  has = c: let r = builtins.tryEval (set ? ${c}); in r.success && r.value;
in builtins.listToAttrs (map (c: { name = c; value = has c; }) cands)"""


def nix_apply(installable: str, template: str, cands: list[str]) -> dict:
    """Pure `nix eval --apply` of template over installable; raises EvalFailed."""
    fn = template.replace("@CANDS@", nix_str(json.dumps(cands)))
    proc = sh([*NIX, "eval", "--json", installable, "--apply", fn], check=False)
    if proc.returncode != 0:
        print(f"nix eval failed for {installable}:\n{proc.stderr[-2000:]}", file=sys.stderr)
        lines = [line for line in proc.stderr.splitlines() if line.strip()]
        raise EvalFailed(lines[-1].strip() if lines else f"exit {proc.returncode}")
    return json.loads(proc.stdout)


def drv_table(flake_dir: str, system: str, cands: list[str]) -> dict[str, set[str]]:
    """cand -> drvPaths it evaluates to in the hosts' pkgs of flake_dir."""
    if not cands:
        return {}
    flake = "git+file://" + flake_dir
    installables = [f"{flake}#legacyPackages.{system}"]
    if system == "x86_64-linux":
        installables.append(f"{flake}#nixosConfigurations.example.pkgs")
    table: dict[str, set[str]] = {c: set() for c in cands}
    for installable in installables:
        for cand, drv in nix_apply(installable, DRV_APPLY, cands).items():
            if isinstance(drv, str):
                table.setdefault(cand, set()).add(drv)
    return table


def fallback_table(system: str, cands: list[str]) -> dict[str, bool]:
    """cand -> whether the locked nixpkgs-fallback has it."""
    rev = botcore.locked_rev(read_json("flake.lock"), "nixpkgs-fallback") or ""
    if not REV_RE.match(rev):
        raise EvalFailed(f"no 40-hex nixpkgs-fallback rev in flake.lock: {rev!r}")
    installable = f"github:nixos/nixpkgs/{rev}#legacyPackages.{system}"
    return nix_apply(installable, HAS_APPLY, cands)


def referrers(drv: str) -> list[str] | None:
    proc = sh(["nix-store", "--query", "--referrers", drv], check=False)
    if proc.returncode != 0:
        print(f"nix-store --query --referrers {drv} failed:\n{proc.stderr[-2000:]}", file=sys.stderr)
        return None
    return [
        line.strip()
        for line in proc.stdout.splitlines()
        if line.strip().endswith(".drv") and line.strip() != drv
    ]


def blank_failure(drv: str, why: str, excerpt: str = "") -> dict:
    return {
        "drv": drv,
        "attr": None,
        "leaf": False,
        "notCausedByUpdate": False,
        "missingInFallback": False,
        "why": why,
        "logExcerpt": excerpt,
    }


def cmd_analyze(args) -> None:
    try:
        steps = json.loads(args.steps_json or "{}")
    except json.JSONDecodeError:
        steps = {}
    if not isinstance(steps, dict):
        steps = {}
    expected = args.expected_steps.split()
    if not expected:
        sys.exit("analyze: --expected-steps is empty")
    failed = botcore.failed_steps(steps, expected)
    logs = pathlib.Path(args.logs)

    def outcome(step: str):
        entry = steps.get(step)
        return entry.get("outcome") if isinstance(entry, dict) else None

    roots, dep_failed, no_root_steps, seen = [], set(), [], set()
    for step in failed:
        # A skipped or missing step never ran, so any log for it is stale.
        log = logs / f"{step}.log"
        ran = outcome(step) in ("failure", "cancelled") and log.exists()
        parsed = botcore.parse_log(log.read_text(errors="replace") if ran else "")
        dep_failed.update(parsed["depFailed"])
        if not parsed["roots"]:
            no_root_steps.append(step)
        for r in parsed["roots"]:
            if r["drv"] not in seen:
                seen.add(r["drv"])
                roots.append(r)

    # FOD hop: an unmapped fixed-output hash failure is attributed to the
    # failed dependents that consume it.
    dependents: dict[str, list[str]] = {}
    for r in roots:
        if r["kind"] == "hash":
            dependents[r["drv"]] = [d for d in referrers(r["drv"]) or [] if d in dep_failed]

    cand_of: dict[str, str] = {}
    for drv in [r["drv"] for r in roots] + [d for ds in dependents.values() for d in ds]:
        cand = botcore.drv_candidate(drv)
        if CAND_RE.match(cand):
            cand_of[drv] = cand
    cands = sorted(set(cand_of.values()))

    def attempt(fn, *a):
        try:
            return fn(*a), None
        except EvalFailed as e:
            return {}, str(e)

    cur, cur_err = attempt(drv_table, str(pathlib.Path.cwd()), args.system, cands)
    base, base_err = attempt(drv_table, str(pathlib.Path(args.base_dir).resolve()), args.system, cands)
    fallback, fallback_err = attempt(fallback_table, args.system, cands) if cands else ({}, None)

    def maps(table: dict, drv: str) -> bool:
        cand = cand_of.get(drv)
        return cand is not None and drv in table.get(cand, set())

    failures = []
    for r in roots:
        drv = r["drv"]
        if cur_err is not None:
            failures.append(blank_failure(drv, f"nix eval of candidates failed: {cur_err}", r["excerpt"]))
            continue
        if maps(cur, drv):
            target = drv
        else:
            target = next((d for d in dependents.get(drv, []) if maps(cur, d)), None)
        failure = blank_failure(drv, "unmapped: no top-level package attr builds this derivation", r["excerpt"])
        if target:
            attr = cand_of[target]
            failure["attr"] = attr
            failure["leaf"], failure["why"] = leaf_of(attr, target)
            if base_err is None:
                failure["notCausedByUpdate"] = maps(base, target)
            else:
                failure["notCausedByUpdate"] = None
                failure["why"] += f"; base eval failed: {base_err}"
            if fallback_err is None:
                failure["missingInFallback"] = not fallback.get(attr, False)
            else:
                failure["missingInFallback"] = True
                failure["why"] += f"; nixpkgs-fallback eval failed: {fallback_err}"
        failures.append(failure)

    for step in no_root_steps:
        failures.append(blank_failure("", botcore.step_failure_why(step, outcome(step))))

    report = {
        "system": args.system,
        "job": args.job,
        "ok": not failed and not roots,
        "failures": failures,
    }
    write(args.out, json.dumps(report, indent=2) + "\n")


def leaf_of(attr: str, drv: str) -> tuple[bool, str]:
    refs = referrers(drv)
    if refs is None:
        return False, "could not query referrers: nix-store --query --referrers failed (see the job log)"
    proc = sh([*NIX, "derivation", "show", drv, *refs], check=False)
    if proc.returncode != 0:
        return False, f"could not inspect derivation graph: {proc.stderr.strip()[-200:]}"
    drvs = botcore.normalize_drvs(json.loads(proc.stdout))
    own = drvs.get(drv.rsplit("/", 1)[-1])
    if own is None:
        return False, "could not inspect derivation graph: drv missing from output"
    others = [v for k, v in drvs.items() if k != drv.rsplit("/", 1)[-1]]
    return botcore.classify_leaf(attr, own, others)


# --- decide / finalize -----------------------------------------------------


def cmd_decide(args) -> None:
    tree, out = pathlib.Path(args.tree), pathlib.Path(args.out)
    reports = [
        json.loads(p.read_text())
        for p in sorted(pathlib.Path(args.reports).rglob("report.json"))
    ]
    tree_lock = read_json(tree / "flake.lock")
    cur_pins = read_json(tree / "pins.json", {"frozenInputs": [], "pins": []})
    nixpkgs_rev = botcore.locked_rev(tree_lock, "nixpkgs") or ""
    base_rev = botcore.locked_rev(read_json("flake.lock"), "nixpkgs") or ""
    decision = botcore.decide(
        attempt=args.attempt,
        round_=args.round,
        max_rounds=args.max_rounds,
        reports=reports,
        expected_jobs=args.expected_jobs.split(),
        base_pins=read_json("pins.json", {"frozenInputs": [], "pins": []}),
        cur_pins=cur_pins,
        nixpkgs_rev=nixpkgs_rev,
        nixpkgs_moved=bool(nixpkgs_rev) and nixpkgs_rev != base_rev,
        today=today(),
        run_url=run_url(),
    )
    out.mkdir(parents=True, exist_ok=True)
    if decision["action"] == "repin":
        shutil.copyfile(tree / "flake.lock", out / "flake.lock")
        write(out / "pins.json", botcore.dump_pins(decision["pins"]))
    write(out / "decision.json", json.dumps(decision, indent=2) + "\n")
    print(f"decision: {decision['action']}: {decision['why']}")
    set_output("action", decision["action"])


def cmd_finalize(args) -> None:
    final = botcore.finalize(
        {"combined": args.combined, "nixpkgs": args.nixpkgs, "inputs": args.inputs}
    )
    write("final.json", json.dumps(final, indent=2) + "\n")
    set_output("land", final["land"])
    set_output("blocked", "true" if final["blocked"] else "false")


# --- advance-fallback / bodies ---------------------------------------------


def cmd_advance_fallback(args) -> None:
    base_lock = read_json(args.base_lock)
    new_lock = read_json("flake.lock")
    pins = read_json("pins.json", {"frozenInputs": [], "pins": []})
    rev = botcore.fallback_advance(pins, base_lock, new_lock)
    if rev is None:
        set_output("advanced", "false")
        set_output("fallback-rev", botcore.locked_rev(new_lock, "nixpkgs-fallback") or "")
        return
    flake = pathlib.Path("flake.nix")
    text = flake.read_text()
    if len(FALLBACK_LINE.findall(text)) != 1:
        sys.exit("flake.nix: expected exactly one nixpkgs-fallback.url line")
    flake.write_text(FALLBACK_LINE.sub(lambda m: m[1] + rev + m[2], text))
    subprocess.run([*NIX, "flake", "lock"], check=True)
    set_output("advanced", "true")
    set_output("fallback-rev", rev)


def fallback_node(lock: dict) -> dict:
    ref = lock["nodes"]["root"]["inputs"]["nixpkgs-fallback"]
    return lock["nodes"][ref]["locked"]


def cmd_pr_body(args) -> None:
    new_lock = read_json("flake.lock")
    locked = fallback_node(new_lock)
    now = today()
    updated = datetime.datetime.fromtimestamp(
        locked["lastModified"], datetime.UTC
    ).date()
    age = (datetime.date.fromisoformat(now) - updated).days
    body = botcore.render_pr_body(
        attempt=args.attempt,
        base_lock=read_json(args.base_lock),
        new_lock=new_lock,
        base_pins=read_json(args.base_pins, {"frozenInputs": [], "pins": []}),
        new_pins=read_json("pins.json", {"frozenInputs": [], "pins": []}),
        fallback_rev=locked["rev"],
        fallback_age_days=age,
        advanced=args.advanced == "true",
        today=now,
        run_url=run_url(),
    )
    write(args.out, body)


def cmd_issue_body(args) -> None:
    root = pathlib.Path(args.reports)
    best: dict[str, tuple[int, list[dict]]] = {}
    for path in sorted(root.rglob("report.json")):
        rel = path.relative_to(root)
        m = REPORT_DIR.match(rel.parts[0]) if len(rel.parts) > 1 else None
        if not m:
            continue
        attempt, rnd = m[1], int(m[2])
        report = json.loads(path.read_text())
        if attempt not in best or rnd > best[attempt][0]:
            best[attempt] = (rnd, [report])
        elif rnd == best[attempt][0]:
            best[attempt][1].append(report)
    body = botcore.render_issue_body(
        final=read_json(args.final),
        reports_by_attempt={a: reports for a, (_, reports) in best.items()},
        run_url=run_url(),
        today=today(),
    )
    write(args.out, body)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)

    def add(name, fn, **flags):
        p = sub.add_parser(name)
        for flag, kw in flags.items():
            p.add_argument("--" + flag.replace("_", "-"), required=True, **kw)
        p.set_defaults(fn=fn)

    add("prepare", cmd_prepare, out={})
    add(
        "analyze",
        cmd_analyze,
        system={},
        job={},
        logs={},
        steps_json={},
        expected_steps={},
        base_dir={},
        out={},
    )
    add(
        "decide",
        cmd_decide,
        attempt={},
        round={"type": int},
        max_rounds={"type": int},
        reports={},
        expected_jobs={},
        tree={},
        out={},
    )
    add("finalize", cmd_finalize, combined={}, nixpkgs={}, inputs={})
    add("advance-fallback", cmd_advance_fallback, base_lock={})
    add(
        "pr-body",
        cmd_pr_body,
        attempt={},
        base_lock={},
        base_pins={},
        advanced={"choices": ["true", "false"]},
        out={},
    )
    add("issue-body", cmd_issue_body, final={}, reports={}, out={})

    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()

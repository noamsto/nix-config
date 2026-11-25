import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from argparse import Namespace
from unittest import mock

import botcore
import update_bot

FIXTURES = pathlib.Path(__file__).parent / "fixtures"
STORE = "/nix/store/"
GENUINE = STORE + "l5kwfpvbrfhm3h25wkghrwqfxjyshzva-genuine-1.0.drv"
THING_SRC = STORE + "2w363vsifryj0m759inbsmcqk38lv88v-thing-src.drv"
PARENT = STORE + "bmls4mj1s0nn0sg46k2yxaqkwi7r7f4a-parent-2.0.drv"
SIBLING = STORE + "50rd1r4qpglmr9bd47ksa45wph2zr44l-sibling-1.0.drv"
VICTIM = STORE + "0123456789abcdfghijklmnpqrsvwxyz-victim-1.0.drv"
YDRV = STORE + "abcdfghijklmnpqrsvwxyz0123456789-ywhy-1.0.drv"
FOO = STORE + "1111111111111111111111111111111a-foo-1.0.drv"
FOO_WRAPPED = STORE + "2222222222222222222222222222222b-foo-wrapped-1.0.drv"


class FlakeUrlTest(unittest.TestCase):
    def test_shallow_suffix_on_git_file_url(self):
        self.assertEqual(update_bot.flake_url("/x/y"), "git+file:///x/y?shallow=1")


class CheckMainTest(unittest.TestCase):
    OLD = "a" * 40
    NEW = "b" * 40

    def run_check(self, ls_remote: str, rerun: str):
        proc = subprocess.CompletedProcess([], 0, stdout=ls_remote, stderr="")
        with (
            mock.patch.object(update_bot, "sh", return_value=proc),
            mock.patch.object(update_bot, "set_output") as out,
            mock.patch("builtins.print") as printed,
        ):
            update_bot.cmd_check_main(Namespace(run_sha=self.OLD, rerun=rerun))
        notices = [c.args[0] for c in printed.call_args_list]
        return dict(c.args for c in out.call_args_list), notices

    def test_not_moved_publishes(self):
        outputs, notices = self.run_check(f"{self.OLD}\trefs/heads/main\n", "false")
        self.assertEqual(outputs, {"moved": "false", "dispatch": "false"})
        self.assertEqual(notices, [])

    def test_moved_skips_and_dispatches(self):
        outputs, notices = self.run_check(f"{self.NEW}\trefs/heads/main\n", "false")
        self.assertEqual(outputs, {"moved": "true", "dispatch": "true"})
        self.assertEqual(
            notices,
            [
                (
                    f"::notice::main moved from {self.OLD} to {self.NEW} during this run; "
                    "not publishing, starting a fresh run"
                )
            ],
        )

    def test_moved_during_a_rerun_skips_without_dispatching(self):
        outputs, notices = self.run_check(f"{self.NEW}\trefs/heads/main\n", "true")
        self.assertEqual(outputs, {"moved": "true", "dispatch": "false"})
        self.assertIn("not starting another", notices[0])

    def test_unreadable_ls_remote_fails_closed(self):
        with self.assertRaises(SystemExit):
            self.run_check("", "false")


class AnalyzeTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = pathlib.Path(tmp.name)
        self.logs = self.tmp / "logs"
        self.logs.mkdir()

    def stage(self, log: bool = True, capture: bool = True) -> None:
        if log:
            shutil.copy(FIXTURES / "nix-fast-build-forged.log", self.logs / "example.log")
        if capture:
            dest = self.logs / "example.nix-json"
            dest.mkdir()
            shutil.copy(FIXTURES / "nix-fast-build-forged.jsonl", dest / "nix.AAAAAA")

    def analyze(self, outcome: str = "failure", valid: dict | None = None) -> list[dict]:
        attrs = {GENUINE: "genuine", PARENT: "parent"}
        if valid is None:
            valid = {GENUINE: False, THING_SRC: False, PARENT: False, SIBLING: True}

        def drv_table(flake_dir, system, cands):
            return {c: {d for d, a in attrs.items() if a == c} for c in cands}

        out = self.tmp / "report.json"
        args = Namespace(
            system="x86_64-linux",
            job="check",
            logs=str(self.logs),
            steps_json=json.dumps({"example": {"outcome": outcome}}),
            expected_steps="example",
            base_dir=str(self.tmp),
            out=str(out),
        )
        with (
            mock.patch.object(update_bot, "drv_table", drv_table),
            mock.patch.object(update_bot, "fallback_table", lambda s, c: dict.fromkeys(c, True)),
            mock.patch.object(update_bot, "referrers", lambda d: [PARENT] if d == THING_SRC else []),
            mock.patch.object(update_bot, "leaf_of", lambda a, d: (True, "leaf")),
            mock.patch.object(update_bot, "outputs_valid", lambda d: valid.get(d), create=True),
        ):
            update_bot.cmd_analyze(args)
        return json.loads(out.read_text())["failures"]

    def test_builder_forgeries_are_not_roots(self):
        self.stage()
        failures = self.analyze()
        self.assertEqual(
            sorted(f["drv"] for f in failures if f["drv"]), sorted([GENUINE, THING_SRC])
        )
        self.assertEqual(
            {f["drv"]: f["attr"] for f in failures}, {GENUINE: "genuine", THING_SRC: "parent"}
        )

    def test_cancelled_step_is_not_read(self):
        self.stage()
        failures = self.analyze("cancelled")
        self.assertEqual([f["drv"] for f in failures], [""])
        self.assertIn("was cancelled", failures[0]["why"])

    def test_text_log_without_capture_is_a_blank_failure(self):
        self.stage(capture=False)
        failures = self.analyze()
        self.assertEqual([f["drv"] for f in failures], [""])
        self.assertIn("without a failed derivation", failures[0]["why"])

    def test_unverifiable_root_fails_closed(self):
        self.stage()
        failures = {
            f["drv"]: f
            for f in self.analyze(
                valid={GENUINE: False, THING_SRC: None, PARENT: False, SIBLING: True}
            )
        }
        # SIBLING built fine and is dropped; THING_SRC could not be checked.
        self.assertEqual(sorted(failures), sorted([GENUINE, THING_SRC]))
        self.assertEqual(failures[GENUINE]["attr"], "genuine")
        blank = failures[THING_SRC]
        self.assertIsNone(blank["attr"])
        self.assertIn("store check inconclusive", blank["why"])
        self.assertTrue(blank["logExcerpt"].startswith("error: hash mismatch"))

    def test_all_roots_unverifiable_are_blank_failures(self):
        self.stage()
        failures = self.analyze(valid={})
        self.assertEqual(
            sorted(f["drv"] for f in failures), sorted([GENUINE, THING_SRC, SIBLING])
        )
        for f in failures:
            self.assertIsNone(f["attr"])
            self.assertIn("store check inconclusive", f["why"])

    def test_capture_files_are_parsed_independently(self):
        forged = f"error: hash mismatch in fixed-output derivation '{YDRV}':\n         got: x"
        genuine = f"error: Cannot build '{YDRV}'.\n       Reason: builder failed with exit code 1."
        start = {"action": "start", "type": 105, "level": 3, "id": 1, "fields": [YDRV, "", 1, 1]}
        forged_file = ["@nix " + json.dumps({"action": "msg", "level": 0, "msg": forged})]
        genuine_file = [
            "@nix " + json.dumps(start),
            "@nix " + json.dumps({"action": "msg", "level": 0, "msg": genuine}),
        ]
        for forged_name, genuine_name in (("nix.ZZZZZZ", "nix.AAAAAA"), ("nix.AAAAAA", "nix.ZZZZZZ")):
            with self.subTest(forged=forged_name):
                shutil.rmtree(self.logs / "example.nix-json", ignore_errors=True)
                dest = self.logs / "example.nix-json"
                dest.mkdir()
                for name, lines in ((forged_name, forged_file), (genuine_name, genuine_file)):
                    (dest / name).write_text("".join(f"{line}\n" for line in lines))
                failures = self.analyze(valid={YDRV: False})
                self.assertEqual([f["drv"] for f in failures], [YDRV])
                self.assertTrue(failures[0]["logExcerpt"].startswith("error: Cannot build"))


class WrapperHopTest(unittest.TestCase):
    """A failed inner drv whose top-level attr is a wrapper that depends on it."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = pathlib.Path(tmp.name)
        capture = self.tmp / "logs" / "example.nix-json"
        capture.mkdir(parents=True)
        start = {"action": "start", "type": 105, "level": 3, "id": 1, "fields": [FOO, "", 1, 1]}
        built = f"error: Cannot build '{FOO}'.\n       Reason: builder failed with exit code 1."
        dep = f"error: Cannot build '{FOO_WRAPPED}'.\n       Reason: 1 dependency failed."
        records = [start, *({"action": "msg", "level": 0, "msg": m} for m in (built, dep))]
        (capture / "nix.AAAAAA").write_text("".join(f"@nix {json.dumps(r)}\n" for r in records))

    def analyze(self, referrers, attrs, base_attrs=None, wrapper_built=False) -> list[dict]:
        # By default the base lacks the wrapper's attr, so the update caused the failure.
        base_attrs = base_attrs or {}
        base_dir = str(self.tmp / "base")

        def drv_table(flake_dir, system, cands):
            owned = base_attrs if flake_dir == base_dir else attrs
            return {c: {d for d, a in owned.items() if a == c} for c in cands}

        out = self.tmp / "report.json"
        args = Namespace(
            system="x86_64-linux",
            job="check",
            logs=str(self.tmp / "logs"),
            steps_json=json.dumps({"example": {"outcome": "failure"}}),
            expected_steps="example",
            base_dir=base_dir,
            out=str(out),
        )
        with (
            mock.patch.object(update_bot, "drv_table", drv_table),
            mock.patch.object(update_bot, "fallback_table", lambda s, c: dict.fromkeys(c, True)),
            mock.patch.object(update_bot, "referrers", referrers),
            mock.patch.object(update_bot, "leaf_of", lambda a, d: (True, "leaf")),
            mock.patch.object(
                update_bot, "outputs_valid", lambda d: wrapper_built and d == FOO_WRAPPED, create=True
            ),
        ):
            update_bot.cmd_analyze(args)
        return json.loads(out.read_text())["failures"]

    @staticmethod
    def wrapper_referrers(d):
        return [FOO_WRAPPED] if d == FOO else []

    def test_failed_inner_drv_maps_to_the_wrapping_attr(self):
        (f,) = self.analyze(self.wrapper_referrers, {FOO_WRAPPED: "foo"})
        self.assertEqual((f["drv"], f["attr"]), (FOO, "foo"))
        self.assertTrue(f["leaf"])
        self.assertFalse(f["notCausedByUpdate"])
        self.assertFalse(f["missingInFallback"])
        self.assertNotIn("unmapped", f["why"])

    def test_wrapper_already_building_on_base_is_not_caused_by_the_update(self):
        (f,) = self.analyze(self.wrapper_referrers, {FOO_WRAPPED: "foo"}, base_attrs={FOO_WRAPPED: "foo"})
        self.assertTrue(f["notCausedByUpdate"])

    def test_decide_repins_the_wrapping_attr(self):
        failures = self.analyze(self.wrapper_referrers, {FOO_WRAPPED: "foo"})
        reps = [{"system": "x86_64-linux", "job": "check", "ok": False, "failures": failures}]
        empty = {"frozenInputs": [], "pins": []}
        got = botcore.decide(
            attempt="combined",
            round_=1,
            max_rounds=3,
            reports=reps,
            expected_jobs=["check"],
            base_pins=empty,
            cur_pins=empty,
            nixpkgs_rev="b" * 40,
            nixpkgs_moved=True,
            today="2026-11-05",
            run_url="https://example.invalid/run",
        )
        self.assertEqual(got["action"], "repin")
        self.assertEqual([p["attr"] for p in got["pins"]["pins"]], ["foo"])

    def test_root_without_a_matching_dependent_stays_unmapped(self):
        (f,) = self.analyze(self.wrapper_referrers, {})
        self.assertIsNone(f["attr"])
        self.assertIn("unmapped", f["why"])

    def test_candidate_attr_building_an_unrelated_drv_stays_unmapped(self):
        other = STORE + "3333333333333333333333333333333c-foo-1.0.drv"
        (f,) = self.analyze(self.wrapper_referrers, {other: "foo"})
        self.assertIsNone(f["attr"])
        self.assertIn("unmapped", f["why"])

    def test_no_referrer_does_not_map(self):
        (f,) = self.analyze(lambda d: [], {FOO_WRAPPED: "foo"})
        self.assertIsNone(f["attr"])
        self.assertIn("unmapped", f["why"])

    def test_dependent_whose_outputs_are_valid_does_not_map(self):
        # Reported as dependency-failed, but the store has its outputs.
        (f,) = self.analyze(self.wrapper_referrers, {FOO_WRAPPED: "foo"}, wrapper_built=True)
        self.assertIsNone(f["attr"])
        self.assertIn("unmapped", f["why"])

    def test_dependent_not_reported_dependency_failed_does_not_map(self):
        capture = self.tmp / "logs" / "example.nix-json" / "nix.AAAAAA"
        kept = [line for line in capture.read_text().splitlines() if FOO_WRAPPED not in line]
        capture.write_text("".join(f"{line}\n" for line in kept))
        (f,) = self.analyze(self.wrapper_referrers, {FOO_WRAPPED: "foo"})
        self.assertIsNone(f["attr"])
        self.assertIn("unmapped", f["why"])


class OutputsValidTest(unittest.TestCase):
    def probe(self, *procs: tuple[int, str, str]) -> bool | None:
        calls = []

        def sh(cmd, check=True):
            calls.append(cmd)
            rc, out, err = procs[len(calls) - 1]
            return subprocess.CompletedProcess(cmd, rc, out, err)

        with mock.patch.object(update_bot, "sh", sh), mock.patch("sys.stderr"):
            got = update_bot.outputs_valid(GENUINE)
        self.assertEqual(len(calls), len(procs))
        return got

    def test_valid_outputs(self):
        self.assertIs(self.probe((0, "/nix/store/a-x\n/nix/store/b-x-dev\n", ""), (0, "", "")), True)

    def test_invalid_output(self):
        err = "error: path '/nix/store/a-x' is not valid\n"
        self.assertIs(self.probe((0, "/nix/store/a-x\n", ""), (1, "", err)), False)

    def test_other_path_info_error_is_unknown(self):
        self.assertIsNone(self.probe((0, "/nix/store/a-x\n", ""), (1, "", "error: boom\n")))

    def test_unqueryable_drv_is_unknown(self):
        self.assertIsNone(self.probe((1, "", "error: no such drv\n")))

    def test_drv_without_outputs_is_unknown(self):
        self.assertIsNone(self.probe((0, "", "")))


class NixJsonTeeTest(unittest.TestCase):
    WRAPPER = pathlib.Path(update_bot.__file__).resolve().parent / "nix-json-tee"
    STDERR = '@nix {"action":"msg","level":0,"msg":"a"}\n@nix {"action":"msg","level":0,"msg":"b"}\n'

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = pathlib.Path(tmp.name)
        fake = self.tmp / "bin" / "nix"
        fake.parent.mkdir()
        fake.write_text(
            "#!/bin/sh\n"
            'echo "nix $*"\n'
            f"printf '%s' '{self.STDERR}' >&2\n"
            "exit 7\n"
        )
        fake.chmod(0o755)
        self.capture_dir = self.tmp / "capture"

    def run_wrapper(self, *args: str, capture_dir: bool = True):
        bash = shutil.which("bash")
        if bash is None:
            self.fail("bash is required to run nix-json-tee")
        env = {"PATH": f"{self.tmp / 'bin'}:{os.environ.get('PATH', os.defpath)}"}
        if capture_dir:
            env["NFB_JSON_DIR"] = str(self.capture_dir)
        proc = subprocess.run(
            [bash, str(self.WRAPPER), *args],
            check=False,
            env=env,
            capture_output=True,
            text=True,
        )
        files = sorted(self.capture_dir.glob("*")) if self.capture_dir.exists() else []
        return proc, files

    def assert_transparent(self, proc, args: tuple[str, ...]):
        self.assertEqual(proc.returncode, 7)
        self.assertEqual(proc.stdout, f"nix {' '.join(args)}\n")
        self.assertEqual(proc.stderr, self.STDERR)

    def test_tees_internal_json_builds(self):
        args = ("--foo", "--log-format", "internal-json", "bar")
        proc, files = self.run_wrapper(*args)
        self.assert_transparent(proc, args)
        self.assertEqual([f.name[:4] for f in files], ["nix."])
        self.assertEqual(files[0].read_text(), self.STDERR)

    def test_tees_equals_form(self):
        args = ("build", "--log-format=internal-json")
        proc, files = self.run_wrapper(*args)
        self.assert_transparent(proc, args)
        self.assertEqual([f.read_text() for f in files], [self.STDERR])

    def test_each_build_gets_its_own_file(self):
        self.run_wrapper("--log-format", "internal-json")
        _, files = self.run_wrapper("--log-format", "internal-json")
        self.assertEqual(len(files), 2)

    def test_other_log_formats_are_not_tee_d(self):
        for args in (("build", "bar"), ("--log-format", "bar-json"), ("--log-format",)):
            proc, files = self.run_wrapper(*args)
            self.assert_transparent(proc, args)
            self.assertEqual(files, [])

    def test_without_capture_dir_is_a_plain_exec(self):
        args = ("--log-format", "internal-json")
        proc, files = self.run_wrapper(*args, capture_dir=False)
        self.assert_transparent(proc, args)
        self.assertEqual(files, [])


def cli_lock(tmux_rev: str = "c" * 40) -> dict:
    return {
        "nodes": {
            "root": {
                "inputs": {
                    "nixpkgs": "nixpkgs",
                    "nixpkgs-fallback": "nixpkgs-fallback",
                    "tmux-og": "tmux-og",
                }
            },
            "nixpkgs": {
                "locked": {"rev": "d" * 40},
                "original": {
                    "type": "github",
                    "owner": "NixOS",
                    "repo": "nixpkgs",
                    "ref": "nixos-unstable",
                },
            },
            "nixpkgs-fallback": {"locked": {"rev": "d" * 40}},
            "tmux-og": {"locked": {"rev": tmux_rev}},
        }
    }


class SelectCliTest(unittest.TestCase):
    REV = "a" * 40

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = pathlib.Path(tmp.name)
        old_cwd = os.getcwd()
        os.chdir(self.tmp)
        self.addCleanup(os.chdir, old_cwd)
        self.write(".github/upstreams.json", '{"noamsto/tmux-og": "tmux-og"}\n')
        self.write("flake.lock", json.dumps(cli_lock()) + "\n")
        self.write("pins.json", '{"frozenInputs": [], "pins": []}\n')

    def write(self, rel: str, text: str) -> None:
        path = self.tmp / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def run_select(self, *argv: str):
        outputs: list[tuple[str, str]] = []
        printed: list[str] = []
        with (
            mock.patch.object(sys, "argv", ["update_bot.py", "select", *argv]),
            mock.patch.object(
                update_bot, "set_output", side_effect=lambda k, v: outputs.append((k, v))
            ),
            mock.patch("builtins.print", side_effect=lambda *a: printed.append(a[0])),
        ):
            update_bot.main()
        return dict(outputs), printed

    def test_narrow_selection(self):
        outputs, printed = self.run_select(
            "--event=repository_dispatch",
            "--source=noamsto/tmux-og",
            f"--rev={self.REV}",
        )
        self.assertEqual(
            outputs,
            {
                "mode": "narrow",
                "input": "tmux-og",
                "source": "noamsto/tmux-og",
                "rev": self.REV,
            },
        )
        self.assertIn(
            f"::notice::on-demand: noamsto/tmux-og announced {self.REV}; moving tmux-og",
            printed,
        )

    def test_unknown_source_skips(self):
        outputs, printed = self.run_select(
            "--event=repository_dispatch",
            "--source=noamsto/unknown",
            f"--rev={self.REV}",
        )
        self.assertEqual(outputs["mode"], "skip")
        self.assertEqual(outputs["input"], "")
        self.assertTrue(any(p.startswith("::notice::") for p in printed))

    def test_source_starting_with_dash_parses(self):
        outputs, _ = self.run_select(
            "--event=repository_dispatch",
            "--source=-x",
            f"--rev={self.REV}",
        )
        self.assertEqual(outputs["mode"], "skip")

    def test_missing_upstreams_skips_dispatch_and_runs_schedule(self):
        (self.tmp / ".github/upstreams.json").unlink()
        outputs, _ = self.run_select(
            "--event=repository_dispatch",
            "--source=noamsto/tmux-og",
            f"--rev={self.REV}",
        )
        self.assertEqual(outputs["mode"], "skip")
        outputs, _ = self.run_select("--event=schedule", "--source=", "--rev=")
        self.assertEqual(outputs["mode"], "full")
        self.assertEqual(outputs["source"], "")

class RecipientsCliTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = pathlib.Path(tmp.name)
        old_cwd = os.getcwd()
        os.chdir(self.tmp)
        self.addCleanup(os.chdir, old_cwd)

    def write(self, rel: str, text: str) -> None:
        path = self.tmp / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def run_recipients(self, extra: str):
        outputs: list[tuple[str, str]] = []
        printed: list[str] = []
        code = 0
        with (
            mock.patch.object(
                sys, "argv", ["update_bot.py", "recipients", f"--extra={extra}"]
            ),
            mock.patch.object(
                update_bot, "set_output", side_effect=lambda k, v: outputs.append((k, v))
            ),
            mock.patch("builtins.print", side_effect=lambda *a: printed.append(a[0])),
        ):
            try:
                update_bot.main()
            except SystemExit as e:
                code = e.code if isinstance(e.code, int) else 1
        return dict(outputs), printed, code

    def test_file_and_extra_merged_deduped_and_compact(self):
        self.write(
            ".github/consumers.json", '["noamsto/consumer-a", "noamsto/tmux-og"]\n'
        )
        outputs, _, code = self.run_recipients(
            '["noamsto/tmux-og", "noamsto/consumer-b"]'
        )
        merged = '["noamsto/consumer-a","noamsto/tmux-og","noamsto/consumer-b"]'
        self.assertEqual(code, 0)
        self.assertEqual(outputs, {"consumers": merged})

    def test_missing_file_uses_extra_only(self):
        outputs, _, code = self.run_recipients('["noamsto/consumer-b"]')
        self.assertEqual(code, 0)
        self.assertEqual(outputs, {"consumers": '["noamsto/consumer-b"]'})

    def test_empty_extra_uses_file_only(self):
        self.write(".github/consumers.json", '["noamsto/consumer-a"]\n')
        outputs, _, code = self.run_recipients("")
        self.assertEqual(code, 0)
        self.assertEqual(outputs, {"consumers": '["noamsto/consumer-a"]'})

    def test_malformed_extra_fails_loudly(self):
        self.write(".github/consumers.json", "[]\n")
        outputs, printed, code = self.run_recipients("[")
        self.assertNotEqual(code, 0)
        self.assertEqual(outputs, {})
        self.assertTrue(any("::error::recipients" in line for line in printed))

    def test_extra_starting_with_dash_parses_and_fails_validation(self):
        self.write(".github/consumers.json", "[]\n")
        outputs, printed, code = self.run_recipients("-x")
        self.assertNotEqual(code, 0)
        self.assertEqual(outputs, {})
        self.assertTrue(any("::error::recipients" in line for line in printed))


class PrepareNarrowTest(unittest.TestCase):
    BASE_REV = "a" * 40
    NEW_REV = "b" * 40

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = pathlib.Path(tmp.name)
        old_cwd = os.getcwd()
        os.chdir(self.tmp)
        self.addCleanup(os.chdir, old_cwd)
        self.pins = {"frozenInputs": [], "pins": []}
        self.lock_path = self.tmp / "flake.lock"
        self.lock_path.write_text(json.dumps(cli_lock(self.BASE_REV)) + "\n")
        (self.tmp / "pins.json").write_text(json.dumps(self.pins) + "\n")
        self.out = self.tmp / "out"

    def prepare(self, only: str, changed: bool):
        base_bytes = self.lock_path.read_bytes()
        calls: list[list[str]] = []

        def fake_run(cmd, **kwargs):
            calls.append(list(cmd))
            if changed and cmd[-3:] == ["flake", "update", "tmux-og"]:
                self.lock_path.write_text(json.dumps(cli_lock(self.NEW_REV)) + "\n")
            return subprocess.CompletedProcess(cmd, 0)

        outputs: list[tuple[str, str]] = []
        with (
            mock.patch.object(update_bot.subprocess, "run", fake_run),
            mock.patch.object(
                update_bot, "set_output", side_effect=lambda k, v: outputs.append((k, v))
            ),
            mock.patch("builtins.print"),
        ):
            update_bot.cmd_prepare(Namespace(out=str(self.out), only=only))
        return calls, dict(outputs), base_bytes

    def test_only_writes_narrow_tree_and_restores_lock(self):
        calls, outputs, base_bytes = self.prepare("tmux-og", changed=True)
        self.assertEqual(outputs, {"narrow-changed": "true"})
        self.assertEqual(sorted(p.name for p in self.out.iterdir()), ["narrow"])
        narrow = self.out / "narrow"
        self.assertEqual(
            json.loads((narrow / "flake.lock").read_text())["nodes"]["tmux-og"]["locked"][
                "rev"
            ],
            self.NEW_REV,
        )
        self.assertEqual((narrow / "pins.json").read_text(), botcore.dump_pins(self.pins))
        self.assertEqual(self.lock_path.read_bytes(), base_bytes)
        self.assertEqual([c[-3:] for c in calls], [["flake", "update", "tmux-og"]])

    def test_unchanged_lock_reports_false(self):
        calls, outputs, base_bytes = self.prepare("tmux-og", changed=False)
        self.assertEqual(outputs, {"narrow-changed": "false"})
        self.assertEqual(self.lock_path.read_bytes(), base_bytes)
        self.assertEqual([c[-3:] for c in calls], [["flake", "update", "tmux-og"]])

    def test_only_must_be_an_input_side_root_input(self):
        with self.assertRaises(SystemExit):
            self.prepare("nixpkgs", changed=False)


class FinalizeCliTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = pathlib.Path(tmp.name)
        old_cwd = os.getcwd()
        os.chdir(self.tmp)
        self.addCleanup(os.chdir, old_cwd)
        self.summary = self.tmp / "summary.md"
        env = mock.patch.dict(os.environ, {"GITHUB_STEP_SUMMARY": str(self.summary)})
        env.start()
        self.addCleanup(env.stop)

    def finalize(self, mode="full", narrow="", input=""):
        args = Namespace(
            combined="", nixpkgs="", inputs="", mode=mode, narrow=narrow, input=input
        )
        outputs: list[tuple[str, str]] = []
        printed: list[str] = []
        code = 0
        with (
            mock.patch.object(
                update_bot, "set_output", side_effect=lambda k, v: outputs.append((k, v))
            ),
            mock.patch("builtins.print", side_effect=lambda *a: printed.append(a[0])),
        ):
            try:
                update_bot.cmd_finalize(args)
            except SystemExit as exc:
                code = exc.code
        return dict(outputs), printed, code

    def test_narrow_block_errors_and_summarizes(self):
        outputs, printed, code = self.finalize(
            mode="narrow", narrow="block", input="tmux-og"
        )
        self.assertNotEqual(code, 0)
        self.assertEqual(outputs, {"land": "", "blocked": "false"})
        sentence = (
            "on-demand update of tmux-og did not land (block); "
            "the next nightly retries it"
        )
        self.assertIn(f"::error::{sentence}", printed)
        self.assertIn(sentence, self.summary.read_text())
        self.assertEqual(
            json.loads((self.tmp / "final.json").read_text()),
            {"land": "", "blocked": False, "sides": ["narrow"], "interaction": False},
        )

    def test_narrow_not_run_errors_and_says_not_run(self):
        outputs, printed, code = self.finalize(mode="narrow", narrow="", input="tmux-og")
        self.assertNotEqual(code, 0)
        self.assertEqual(outputs, {"land": "", "blocked": "false"})
        self.assertTrue(any("(not run)" in p for p in printed))
        self.assertTrue(any(p.startswith("::error::") for p in printed))
        self.assertIn("(not run)", self.summary.read_text())
        self.assertTrue((self.tmp / "final.json").is_file())

    def test_narrow_land(self):
        outputs, _, code = self.finalize(mode="narrow", narrow="land", input="tmux-og")
        self.assertEqual(code, 0)
        self.assertEqual(outputs, {"land": "narrow", "blocked": "false"})
        self.assertFalse(self.summary.exists())

    def test_full_mode_matches_botcore(self):
        outputs, _, code = self.finalize(mode="full")
        self.assertEqual(code, 0)
        expected = botcore.finalize({"combined": "", "nixpkgs": "", "inputs": ""})
        self.assertEqual(outputs["land"], expected["land"])
        self.assertEqual(outputs["blocked"], "true" if expected["blocked"] else "false")


if __name__ == "__main__":
    unittest.main()

import json
import os
import pathlib
import shutil
import subprocess
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

    def analyze(self, referrers, attrs, base_attrs=None) -> list[dict]:
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
            mock.patch.object(update_bot, "outputs_valid", lambda d: False, create=True),
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

    def test_dependent_that_did_not_fail_does_not_map(self):
        (f,) = self.analyze(lambda d: [], {FOO_WRAPPED: "foo"})
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


if __name__ == "__main__":
    unittest.main()

import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest
from argparse import Namespace
from unittest import mock

import update_bot

FIXTURES = pathlib.Path(__file__).parent / "fixtures"
STORE = "/nix/store/"
GENUINE = STORE + "l5kwfpvbrfhm3h25wkghrwqfxjyshzva-genuine-1.0.drv"
THING_SRC = STORE + "2w363vsifryj0m759inbsmcqk38lv88v-thing-src.drv"
PARENT = STORE + "bmls4mj1s0nn0sg46k2yxaqkwi7r7f4a-parent-2.0.drv"
SIBLING = STORE + "50rd1r4qpglmr9bd47ksa45wph2zr44l-sibling-1.0.drv"
VICTIM = STORE + "0123456789abcdfghijklmnpqrsvwxyz-victim-1.0.drv"


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

    def test_unverifiable_roots_are_dropped(self):
        self.stage()
        failures = self.analyze(valid={})
        self.assertEqual([f["drv"] for f in failures], [""])


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

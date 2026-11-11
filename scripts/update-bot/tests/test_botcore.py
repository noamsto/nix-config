import copy
import json
import unittest
from pathlib import Path

import botcore

FIXTURES = Path(__file__).parent / "fixtures"
NP_BASE = "31ecbaca1bdefa45dffc409f0250bd8039ea0010"
NP_NEW = "0bb2eed9d6b7b1c9e3d4f5a6b7c8d9e0f1a2b3c4"
TODAY = "2026-11-05"
RUN = "https://github.com/noamsto/nix-config/actions/runs/1"
JOBS = ["check", "darwin", "aarch64-linux"]
SYSTEMS = {"check": "x86_64-linux", "darwin": "aarch64-darwin", "aarch64-linux": "aarch64-linux"}


def text(name: str) -> str:
    return (FIXTURES / name).read_text()


def load(name: str) -> dict:
    return json.loads(text(name))


def drv_names(paths: list[str]) -> list[str]:
    return [p.rsplit("/", 1)[-1][33:] for p in paths]


class ParseLogTest(unittest.TestCase):
    def test_nix235(self):
        got = botcore.parse_log(text("nix235.log"))
        roots = [(r["kind"], n) for r, n in zip(got["roots"], drv_names([r["drv"] for r in got["roots"]]))]
        self.assertEqual(roots, [("builder", "brokenleaf-1.0.drv"), ("hash", "thing-src.drv")])
        self.assertEqual(drv_names(got["depFailed"]), ["parent-2.0.drv"])
        excerpt = got["roots"][0]["excerpt"]
        self.assertTrue(excerpt.startswith("error: Cannot build '/nix/store/"))
        self.assertIn("Reason: builder failed with exit code 2.", excerpt)
        self.assertIn("> boom", excerpt)
        self.assertNotIn("hash mismatch", excerpt)
        # The unindented garbage line after the hash block ends that block.
        self.assertIn("got:    sha256-c8s4", got["roots"][1]["excerpt"])
        self.assertNotIn("Cannot build", got["roots"][1]["excerpt"])

    def test_nix_fast_build_strips_ansi_and_attr_prefix(self):
        got = botcore.parse_log(text("nix-fast-build.log"))
        self.assertEqual(
            [(r["kind"], botcore.drv_candidate(r["drv"])) for r in got["roots"]],
            [("builder", "brokenleaf"), ("hash", "thing2-src")],
        )
        self.assertEqual(drv_names([r["drv"] for r in got["roots"]]), ["brokenleaf-1.1.drv", "thing2-src.drv"])
        self.assertEqual(drv_names(got["depFailed"]), ["parent-2.1.drv"])
        for root in got["roots"]:
            self.assertNotIn("\x1b", root["excerpt"])
            self.assertNotIn("parent>", root["excerpt"])
            self.assertTrue(root["drv"].startswith("/nix/store/"))
        self.assertIn("Reason: builder failed with exit code 3.", got["roots"][0]["excerpt"])
        self.assertNotIn("end of log", got["roots"][0]["excerpt"])

    def test_single_target_bare_prefix_and_singular_dependency_reason(self):
        got = botcore.parse_log(text("nix-fast-build-single.log"))
        self.assertEqual(
            [(r["kind"], botcore.drv_candidate(r["drv"])) for r in got["roots"]],
            [("builder", "tectonic"), ("builder", "hyprlock")],
        )
        self.assertEqual(
            drv_names(got["depFailed"]), ["neovim-0.12.6.drv", "vicinae-0.20.1.drv"]
        )
        for root in got["roots"]:
            self.assertNotIn("\x1b", root["excerpt"])
            self.assertTrue(root["excerpt"].startswith("error: Cannot build '/nix/store/"))
        self.assertIn("Reason: builder failed with exit code 101.", got["roots"][0]["excerpt"])
        self.assertIn(">   thread 'main' panicked", got["roots"][0]["excerpt"])

    def test_bare_prefix_forged_builder_line_is_not_a_root(self):
        victim = "/nix/store/" + "b" * 32 + "-victim-1.0.drv"
        for forged in (f"> > error: Cannot build '{victim}'.", f"> pkg> error: Cannot build '{victim}'."):
            with self.subTest(line=forged):
                log = (
                    forged + "\n"
                    "       Reason: builder failed with exit code 1.\n"
                    "> done\n"
                )
                self.assertEqual(botcore.parse_log(log), {"roots": [], "depFailed": []})

    def test_singular_dependency_reason_in_plain_output(self):
        drv = "/nix/store/" + "c" * 32 + "-parent-2.0.drv"
        log = f"error: Cannot build '{drv}'.\n       Reason: 1 dependency failed.\n"
        self.assertEqual(botcore.parse_log(log), {"roots": [], "depFailed": [drv]})

    def test_legacy_forms_and_dedupe(self):
        got = botcore.parse_log(text("legacy.log"))
        self.assertEqual(
            [(r["kind"], botcore.drv_candidate(r["drv"])) for r in got["roots"]],
            [("builder", "oldleaf"), ("hash", "oldthing-src")],
        )
        self.assertEqual(drv_names(got["depFailed"]), ["oldparent-1.0.drv"])
        self.assertIn("make: *** [Makefile:12: all] Error 1", got["roots"][0]["excerpt"])

    def test_eval_error_has_no_roots(self):
        self.assertEqual(botcore.parse_log(text("eval-error.log")), {"roots": [], "depFailed": []})

    def test_excerpt_bounded(self):
        drv = "/nix/store/" + "a" * 32 + "-big-1.0.drv"
        log = "\n".join(
            [f"error: Cannot build '{drv}'.", "       Reason: builder failed with exit code 1."]
            + [f"       > line {i}" for i in range(100)]
        )
        (root,) = botcore.parse_log(log)["roots"]
        self.assertEqual(len(root["excerpt"].splitlines()), botcore.EXCERPT_LINES)

    def test_other_cannot_build_reason_is_ignored(self):
        drv = "/nix/store/" + "a" * 32 + "-slow-1.0.drv"
        log = f"error: Cannot build '{drv}'.\n       Reason: timed out after 3600 seconds.\n"
        self.assertEqual(botcore.parse_log(log), {"roots": [], "depFailed": []})

    def test_forged_error_after_odd_line_break_is_not_a_root(self):
        real = "/nix/store/" + "a" * 32 + "-real-1.0.drv"
        fake = "/nix/store/" + "b" * 32 + "-victim-1.0.drv"
        for sep in ("\x0b", "\x0c", "\x1c", "\x85", " ", " "):
            with self.subTest(sep=repr(sep)):
                log = (
                    f"error: Cannot build '{real}'.\n"
                    "       Reason: builder failed with exit code 1.\n"
                    f"       > output{sep}error: builder for '{fake}' failed with exit code 1\r\n"
                    "       > done\n"
                )
                got = botcore.parse_log(log)
                self.assertEqual([r["drv"] for r in got["roots"]], [real])
                self.assertIn("> done", got["roots"][0]["excerpt"])


def drv_path(char: str, name: str) -> str:
    return f"/nix/store/{char * 32}-{name}.drv"


def record(**rec) -> str:
    return "@nix " + json.dumps(rec)


def started(drv: str) -> str:
    return record(action="start", id=1, level=3, type=105, fields=[drv, "", 1, 1], text="")


def msg(text: str, level: int = 0) -> str:
    return record(action="msg", level=level, msg=text)


def cannot_build(drv: str, reason: str = "builder failed with exit code 1", extra=()) -> str:
    return "\n".join([f"error: Cannot build '{drv}'.", f"       Reason: {reason}.", *extra])


class ParseInternalJsonTest(unittest.TestCase):
    GENUINE = drv_path("a", "genuine-1.0")
    VICTIM = drv_path("b", "victim-1.0")

    def roots(self, lines: list[str]) -> list[tuple[str, str]]:
        return [(r["drv"], r["kind"]) for r in botcore.parse_internal_json(lines)["roots"]]

    def test_forged_fixture(self):
        lines = text("nix-fast-build-forged.jsonl").splitlines()
        # The forgeries must stay in the fixture, or the rejections below prove nothing.
        records = [json.loads(line[5:]) for line in lines if line.startswith("@nix ")]
        self.assertTrue(
            any(
                r["action"] == "msg" and r["level"] == 0 and "victim-1.0.drv" in r["msg"]
                for r in records
            )
        )
        self.assertTrue(
            any(
                r["action"] == "result"
                and r["type"] == 101
                and any("victim-1.0.drv" in f for f in r["fields"])
                for r in records
            )
        )
        self.assertTrue(
            any(
                r["action"] == "msg"
                and r["level"] == 0
                and "Cannot build" in r["msg"]
                and "sibling-1.0.drv" in r["msg"]
                for r in records
            )
        )
        got = botcore.parse_internal_json(lines)
        self.assertEqual(
            [(n, r["kind"]) for n, r in zip(drv_names([r["drv"] for r in got["roots"]]), got["roots"])],
            [("thing-src.drv", "hash"), ("sibling-1.0.drv", "builder"), ("genuine-1.0.drv", "builder")],
        )
        thing, sibling, genuine = got["roots"]
        self.assertTrue(thing["excerpt"].startswith("error: hash mismatch in fixed-output derivation"))
        self.assertTrue(genuine["excerpt"].startswith("error: Cannot build"))
        self.assertIn("Last 5 log lines:", genuine["excerpt"])
        self.assertNotIn("victim", "".join(r["drv"] for r in got["roots"]))
        self.assertEqual(drv_names(got["depFailed"]), ["parent-2.0.drv"])
        # The sibling really started and built; only cmd_analyze's store probe drops it.
        self.assertTrue(sibling["excerpt"].startswith("error: Cannot build"))

    def test_empty(self):
        self.assertEqual(botcore.parse_internal_json([]), {"roots": [], "depFailed": []})

    def test_builder_output_records_are_ignored(self):
        text_ = cannot_build(self.VICTIM)
        for variant in (text_, "\x1b[31;1merror:\x1b[0m" + text_[len("error:") :]):
            for line in variant.split("\n"):
                with self.subTest(line=line):
                    lines = [started(self.VICTIM), record(action="result", type=101, id=1, fields=[line])]
                    self.assertEqual(botcore.parse_internal_json(lines)["roots"], [])

    def test_echoed_builder_text_is_not_a_root(self):
        echo = [f"       > {line}" for line in cannot_build(self.VICTIM).split("\n")]
        genuine = cannot_build(self.GENUINE, extra=["       Last 3 log lines:", *echo])
        lines = [started(self.GENUINE), started(self.VICTIM), msg(genuine)]
        self.assertEqual(self.roots(lines), [(self.GENUINE, "builder")])

    def test_odd_line_breaks_in_an_echo_stay_in_the_block(self):
        for sep in ("\x0b", "\x0c", "\x1c", "\x85", " ", " "):
            with self.subTest(sep=repr(sep)):
                echo = f"       > out{sep}{cannot_build(self.VICTIM).splitlines()[0]}"
                genuine = cannot_build(self.GENUINE, extra=[echo, "       > done"])
                lines = [started(self.GENUINE), started(self.VICTIM), msg(genuine)]
                (root,) = botcore.parse_internal_json(lines)["roots"]
                self.assertEqual(root["drv"], self.GENUINE)
                self.assertIn("> done", root["excerpt"])

    def test_malformed_records_are_ignored(self):
        junk = [
            "",
            "garbage",
            "@nix",
            "@nix not json",
            "@nix []",
            "@nix 5",
            "@nix null",
            'warning: {"action":"msg","level":0}',
            msg(cannot_build(self.GENUINE), level=1),
            msg(cannot_build(self.GENUINE), level=3),
            record(action="msg", level=0),
            record(action="msg", level=0, msg=5),
            record(action="msg", msg=cannot_build(self.GENUINE)),
            record(action="start", type=105),
            record(action="start", type=105, fields=[]),
            record(action="start", type=105, fields=[5]),
            record(action="start", type=104, fields=[self.GENUINE]),
            record(action="result", type=105, fields=[self.GENUINE]),
        ]
        lines = [started(self.GENUINE), *junk, msg(cannot_build(self.GENUINE), level=1)]
        self.assertEqual(botcore.parse_internal_json(lines), {"roots": [], "depFailed": []})
        lines = [*junk, msg(cannot_build(self.GENUINE))]
        self.assertEqual(botcore.parse_internal_json(lines), {"roots": [], "depFailed": []})
        lines = [*junk, started(self.GENUINE), msg(cannot_build(self.GENUINE))]
        self.assertEqual(self.roots(lines), [(self.GENUINE, "builder")])

    def test_root_without_a_nix_start_record_is_dropped(self):
        lines = [started(self.GENUINE), msg(cannot_build(self.GENUINE)), msg(cannot_build(self.VICTIM))]
        self.assertEqual(self.roots(lines), [(self.GENUINE, "builder")])

    def test_dependency_failures_need_no_start_record(self):
        parent = drv_path("c", "parent-2.0")
        lines = [msg(cannot_build(parent, "2 dependencies failed"))]
        self.assertEqual(botcore.parse_internal_json(lines), {"roots": [], "depFailed": [parent]})

    def test_last_record_per_drv_wins(self):
        forged = f"error: hash mismatch in fixed-output derivation '{self.GENUINE}':\n         got: x"
        real = cannot_build(self.GENUINE, extra=["       Last 1 log lines:", "       > boom"])
        lines = [started(self.GENUINE), msg(forged), msg(real)]
        (root,) = botcore.parse_internal_json(lines)["roots"]
        self.assertEqual(root["kind"], "builder")
        self.assertIn("> boom", root["excerpt"])

    def test_root_order_is_stream_order(self):
        drvs = [drv_path(c, f"p{c}-1.0") for c in "xyz"]
        lines = [*(started(d) for d in drvs), *(msg(cannot_build(d)) for d in drvs)]
        self.assertEqual([d for d, _ in self.roots(lines)], drvs)

    def test_each_message_is_parsed_alone(self):
        other = drv_path("c", "other-1.0")
        crafted = "       > padding\n       > more"
        lines = [
            started(self.GENUINE),
            msg(cannot_build(self.GENUINE)),
            msg(crafted),
            started(other),
            msg(cannot_build(other)),
        ]
        got = botcore.parse_internal_json(lines)["roots"]
        self.assertEqual([r["drv"] for r in got], [self.GENUINE, other])
        self.assertNotIn("padding", got[0]["excerpt"])


class FailedStepsTest(unittest.TestCase):
    EXPECTED = ("checks", "packages", "example")

    def test_all_success(self):
        steps = {s: {"outcome": "success", "conclusion": "success"} for s in self.EXPECTED}
        self.assertEqual(botcore.failed_steps(steps, self.EXPECTED), [])

    def test_failure_skipped_cancelled(self):
        steps = {
            "checks": {"outcome": "failure"},
            "packages": {"outcome": "skipped"},
            "example": {"outcome": "cancelled"},
        }
        self.assertEqual(botcore.failed_steps(steps, self.EXPECTED), list(self.EXPECTED))

    def test_missing_step(self):
        steps = {"checks": {"outcome": "success"}, "packages": {"outcome": "success"}}
        self.assertEqual(botcore.failed_steps(steps, self.EXPECTED), ["example"])

    def test_empty_or_malformed_steps(self):
        for steps in ({}, None, [], {"checks": "success", "packages": {}, "example": None}):
            with self.subTest(steps=steps):
                self.assertEqual(botcore.failed_steps(steps, self.EXPECTED), list(self.EXPECTED))

    def test_why_names_the_outcome(self):
        self.assertTrue(botcore.step_failure_why("checks", "skipped").startswith("step checks was skipped without"))
        self.assertTrue(botcore.step_failure_why("checks", "cancelled").startswith("step checks was cancelled without"))
        self.assertTrue(botcore.step_failure_why("checks", "failure").startswith("step checks failed without"))
        self.assertIn("no recorded outcome", botcore.step_failure_why("checks", None))


class DrvCandidateTest(unittest.TestCase):
    def test_cases(self):
        h = "/nix/store/" + "0" * 32 + "-"
        cases = {
            h + "ripgrep-15.2.0.drv": "ripgrep",
            h + "nixos-system-example-none-26.11.20261101.0bb2eed.drv": "nixos-system-example-none",
            h + "thing-src.drv": "thing-src",
            h + "python3.13-requests-2.32.3.drv": "python3.13-requests",
            h + "hello.drv": "hello",
            "0" * 32 + "-btop-1.4.0.drv": "btop",
        }
        for drv, want in cases.items():
            with self.subTest(drv=drv):
                self.assertEqual(botcore.drv_candidate(drv), want)


def v4_drv(name, outputs, inputs=(), env=None, structured=None):
    return {
        "name": name,
        "outputs": {o: {"path": p} for o, p in outputs.items()},
        "inputs": {"drvs": {d: {"outputs": ["out"]} for d in inputs}, "srcs": []},
        "env": env or {},
        "structuredAttrs": structured,
    }


H = {k: c * 32 for k, c in zip(("rg", "rgd", "fish", "sp", "lnk", "tool", "env", "gl"), "abcdfghi")}
RG_OUT = f"{H['rg']}-ripgrep-15.2.0"
V4 = {
    "version": 4,
    "derivations": {
        f"{H['rgd']}-ripgrep-15.2.0.drv": v4_drv("ripgrep-15.2.0", {"out": RG_OUT}),
        # buildEnv aggregation with structured attrs: a runtime reference only.
        f"{H['sp']}-system-path.drv": v4_drv(
            "system-path",
            {"out": f"{H['sp']}-system-path"},
            [f"{H['rgd']}-ripgrep-15.2.0.drv"],
            structured={"paths": [f"/nix/store/{RG_OUT}"], "buildInputs": [], "propagatedBuildInputs": []},
        ),
        f"{H['fish']}-ripgrep-fish-completions.drv": v4_drv(
            "ripgrep-fish-completions",
            {"out": f"{H['fish']}-ripgrep-fish-completions"},
            [f"{H['rgd']}-ripgrep-15.2.0.drv"],
            env={"buildInputs": "", "propagatedBuildInputs": "", "src": f"/nix/store/{RG_OUT}"},
        ),
        f"{H['tool']}-uses-rg-at-build.drv": v4_drv(
            "uses-rg-at-build",
            {"out": f"{H['tool']}-uses-rg-at-build"},
            [f"{H['rgd']}-ripgrep-15.2.0.drv"],
            env={"nativeBuildInputs": f"/nix/store/{RG_OUT}", "buildInputs": "", "propagatedBuildInputs": ""},
        ),
        f"{H['lnk']}-links-rg.drv": v4_drv(
            "links-rg-1.0",
            {"out": f"{H['lnk']}-links-rg-1.0"},
            [f"{H['rgd']}-ripgrep-15.2.0.drv"],
            structured={"buildInputs": [f"/nix/store/{RG_OUT}"], "propagatedBuildInputs": []},
        ),
        f"{H['env']}-propagates-rg.drv": v4_drv(
            "propagates-rg-1.0",
            {"out": f"{H['env']}-propagates-rg-1.0"},
            [f"{H['rgd']}-ripgrep-15.2.0.drv"],
            env={"buildInputs": "", "propagatedBuildInputs": f"/nix/store/{H['gl']}-other /nix/store/{RG_OUT}"},
        ),
    },
}


class NormalizeDrvsTest(unittest.TestCase):
    def test_v4(self):
        got = botcore.normalize_drvs(V4)
        self.assertEqual(
            got[f"{H['rgd']}-ripgrep-15.2.0.drv"],
            {
                "name": "ripgrep-15.2.0",
                "outputs": {"out": RG_OUT},
                "inputDrvs": [],
                "buildInputs": [],
                "propagatedBuildInputs": [],
            },
        )
        self.assertEqual(got[f"{H['lnk']}-links-rg.drv"]["buildInputs"], [RG_OUT])
        self.assertEqual(got[f"{H['lnk']}-links-rg.drv"]["inputDrvs"], [f"{H['rgd']}-ripgrep-15.2.0.drv"])
        self.assertEqual(got[f"{H['env']}-propagates-rg.drv"]["propagatedBuildInputs"], [f"{H['gl']}-other", RG_OUT])

    def test_legacy(self):
        doc = {
            f"/nix/store/{H['lnk']}-links-rg.drv": {
                "name": "links-rg-1.0",
                "outputs": {"out": {"path": f"/nix/store/{H['lnk']}-links-rg-1.0"}},
                "inputDrvs": {f"/nix/store/{H['rgd']}-ripgrep-15.2.0.drv": {"outputs": ["out"]}},
                "env": {"buildInputs": f"/nix/store/{RG_OUT}  /nix/store/{H['gl']}-glib-2.84-dev"},
            },
            f"/nix/store/{H['sp']}-system-path.drv": {
                "name": "system-path",
                "outputs": {"out": {"path": f"/nix/store/{H['sp']}-system-path"}},
                "inputDrvs": {},
                "env": {"__json": json.dumps({"propagatedBuildInputs": [f"/nix/store/{RG_OUT}"]})},
            },
        }
        got = botcore.normalize_drvs(doc)
        self.assertEqual(
            got[f"{H['lnk']}-links-rg.drv"],
            {
                "name": "links-rg-1.0",
                "outputs": {"out": f"{H['lnk']}-links-rg-1.0"},
                "inputDrvs": [f"{H['rgd']}-ripgrep-15.2.0.drv"],
                "buildInputs": [RG_OUT, f"{H['gl']}-glib-2.84-dev"],
                "propagatedBuildInputs": [],
            },
        )
        self.assertEqual(got[f"{H['sp']}-system-path.drv"]["propagatedBuildInputs"], [RG_OUT])

    def test_v4_null_build_inputs(self):
        x, bash = "a" * 32, "b" * 32
        doc = {
            "version": 4,
            "derivations": {
                f"{x}-x-1.0.drv": v4_drv(
                    "x-1.0",
                    {"out": f"{x}-x-1.0"},
                    structured={"buildInputs": [f"/nix/store/{bash}-bash-5.3-dev", None]},
                ),
            },
        }
        got = botcore.normalize_drvs(doc)
        self.assertEqual(got[f"{x}-x-1.0.drv"]["buildInputs"], [f"{bash}-bash-5.3-dev"])


class ClassifyLeafTest(unittest.TestCase):
    def setUp(self):
        self.drvs = botcore.normalize_drvs(V4)
        self.rg = self.drvs[f"{H['rgd']}-ripgrep-15.2.0.drv"]

    def refs(self, *keys):
        return [self.drvs[k] for k in keys]

    def test_runtime_and_native_referrers_stay_leaf(self):
        refs = self.refs(
            f"{H['sp']}-system-path.drv",
            f"{H['fish']}-ripgrep-fish-completions.drv",
            f"{H['tool']}-uses-rg-at-build.drv",
        )
        self.assertEqual(botcore.classify_leaf("ripgrep", self.rg, refs), (True, "leaf"))

    def test_nested(self):
        self.assertEqual(botcore.classify_leaf("python3Packages.requests", self.rg, []), (False, "nested attr"))

    def test_denylisted(self):
        self.assertEqual(botcore.classify_leaf("openssl_3", self.rg, []), (False, "denylisted: openssl*"))
        self.assertEqual(botcore.classify_leaf("go", self.rg, []), (False, "denylisted: go"))
        self.assertEqual(botcore.classify_leaf("gopass", self.rg, []), (True, "leaf"))

    def test_dev_lib_static_outputs(self):
        for out in ("dev", "lib", "static"):
            with self.subTest(out=out):
                drv = {**self.rg, "outputs": {"out": RG_OUT, out: f"{RG_OUT}-{out}"}}
                self.assertEqual(botcore.classify_leaf("ripgrep", drv, []), (False, f"has {out} output"))

    def test_linked_via_structured_build_inputs(self):
        refs = self.refs(f"{H['sp']}-system-path.drv", f"{H['lnk']}-links-rg.drv")
        self.assertEqual(botcore.classify_leaf("ripgrep", self.rg, refs), (False, "linked into links-rg-1.0"))

    def test_linked_via_propagated_env_string(self):
        refs = self.refs(f"{H['env']}-propagates-rg.drv")
        self.assertEqual(botcore.classify_leaf("ripgrep", self.rg, refs), (False, "linked into propagates-rg-1.0"))


class InputSetsTest(unittest.TestCase):
    def test_sides_with_frozen_and_excluded(self):
        lock = load("lock-base.json")
        self.assertEqual(
            botcore.input_sets(lock, ["llm-agents"]),
            (["nixpkgs", "nixpkgs-stable"], ["argonaut", "home-manager", "tmux-fingers", "wallpapers"]),
        )

    def test_without_frozen(self):
        _, inputs = botcore.input_sets(load("lock-base.json"), [])
        self.assertIn("llm-agents", inputs)
        # Rev-pinned non-nixpkgs input is inputs-side; non-root nixpkgs_2 is ignored.
        self.assertIn("argonaut", inputs)
        self.assertNotIn("nixpkgs_2", inputs)
        for excluded in botcore.ALWAYS_EXCLUDED:
            self.assertNotIn(excluded, inputs)

    def test_follows_root_input_is_skipped(self):
        lock = load("lock-base.json")
        lock["nodes"]["root"]["inputs"]["nixpkgs-alias"] = ["home-manager", "nixpkgs"]
        nixpkgs, inputs = botcore.input_sets(lock, [])
        self.assertNotIn("nixpkgs-alias", nixpkgs + inputs)
        self.assertIsNone(botcore.locked_rev(lock, "nixpkgs-alias"))

    def test_locked_rev(self):
        self.assertEqual(botcore.locked_rev(load("lock-base.json"), "nixpkgs"), NP_BASE)
        self.assertEqual(botcore.locked_rev(load("lock-new.json"), "nixpkgs"), NP_NEW)
        self.assertIsNone(botcore.locked_rev(load("lock-new.json"), "wallpapers"))
        self.assertIsNone(botcore.locked_rev(load("lock-new.json"), "absent"))


class PinsDocTest(unittest.TestCase):
    def test_drop_auto_pins(self):
        base = load("pins-base.json")
        snapshot = copy.deepcopy(base)
        got = botcore.drop_auto_pins(base)
        self.assertEqual(got["frozenInputs"], ["llm-agents"])
        self.assertEqual([p["attr"] for p in got["pins"]], ["slack"])
        self.assertEqual(base, snapshot)

    def test_dump_pins_canonical(self):
        self.assertEqual(
            botcore.dump_pins({"frozenInputs": [], "pins": []}), '{\n  "frozenInputs": [],\n  "pins": []\n}\n'
        )
        doc = load("pins-base.json")
        self.assertEqual(json.loads(botcore.dump_pins(doc)), doc)


def failure(attr="hello", **kw):
    return {
        "drv": f"/nix/store/{'0' * 32}-{attr or 'unknown'}-1.0.drv",
        "attr": attr,
        "leaf": True,
        "notCausedByUpdate": False,
        "missingInFallback": False,
        "why": "leaf",
        "logExcerpt": "error: Cannot build ...",
        **kw,
    }


def reports(fails_by_job=None, jobs=JOBS):
    fails_by_job = fails_by_job or {}
    return [
        {
            "system": SYSTEMS[j],
            "job": j,
            "ok": not fails_by_job.get(j),
            "failures": fails_by_job.get(j, []),
        }
        for j in jobs
    ]


class DecideTest(unittest.TestCase):
    def decide(self, reps, attempt="combined", round_=1, cur_pins=None, base_pins=None, nixpkgs_moved=True):
        base_pins = base_pins if base_pins is not None else load("pins-base.json")
        return botcore.decide(
            attempt=attempt,
            round_=round_,
            max_rounds=3,
            reports=reps,
            expected_jobs=JOBS,
            base_pins=base_pins,
            cur_pins=cur_pins if cur_pins is not None else botcore.drop_auto_pins(base_pins),
            nixpkgs_rev=NP_NEW,
            nixpkgs_moved=nixpkgs_moved,
            today=TODAY,
            run_url=RUN,
        )

    def assertBlocked(self, got, why_part):
        self.assertEqual(got["action"], "block")
        self.assertIn(why_part, got["why"])

    def test_all_ok_lands(self):
        cur = botcore.drop_auto_pins(load("pins-base.json"))
        got = self.decide(reports(), cur_pins=cur)
        self.assertEqual(got["action"], "land")
        self.assertEqual(got["pins"], cur)

    def test_new_leaf_repins_with_today(self):
        got = self.decide(reports({"check": [failure("btop")]}))
        self.assertEqual(got["action"], "repin")
        self.assertEqual(
            got["pins"]["pins"],
            [
                {"attr": "slack", "mode": "hold", "reason": "screen sharing regression", "since": "2026-11-01"},
                {
                    "attr": "btop",
                    "mode": "auto",
                    "reason": f"failed on x86_64-linux (combined round 1): {RUN}",
                    "since": TODAY,
                    "failedAt": NP_NEW,
                },
            ],
        )
        self.assertEqual(got["pins"]["frozenInputs"], ["llm-agents"])

    def test_pinned_in_base_still_failing_repins_with_base_since(self):
        # nixpkgs moved, so the tree dropped hello's auto pin; it failed again on latest.
        got = self.decide(reports({"check": [failure("hello")]}))
        self.assertEqual(got["action"], "repin")
        (hello,) = [p for p in got["pins"]["pins"] if p["attr"] == "hello"]
        self.assertEqual(hello["since"], "2026-10-01")
        self.assertEqual(hello["failedAt"], NP_NEW)

    def test_same_attr_on_two_systems_pinned_once(self):
        got = self.decide(reports({"check": [failure("btop")], "darwin": [failure("btop")]}))
        self.assertEqual([p["attr"] for p in got["pins"]["pins"]].count("btop"), 1)

    def test_nixpkgs_attempt_repins(self):
        self.assertEqual(self.decide(reports({"check": [failure("btop")]}), attempt="nixpkgs")["action"], "repin")

    def test_inputs_attempt_never_repins(self):
        self.assertBlocked(self.decide(reports({"check": [failure("btop")]}), attempt="inputs"), "never repins")

    def test_unmapped_blocks(self):
        got = self.decide(reports({"check": [failure("btop"), failure(None, why="step packages failed")]}))
        self.assertBlocked(got, "unmapped")
        self.assertEqual(len(got["failures"]), 2)

    def test_not_caused_by_update_blocks(self):
        self.assertBlocked(
            self.decide(reports({"check": [failure("btop", notCausedByUpdate=True)]})), "not caused by the update"
        )

    def test_missing_in_fallback_blocks(self):
        self.assertBlocked(
            self.decide(reports({"check": [failure("btop", missingInFallback=True)]})), "missing from nixpkgs-fallback"
        )

    def test_non_leaf_blocks(self):
        got = self.decide(reports({"check": [failure("openssl", leaf=False, why="denylisted: openssl*")]}))
        self.assertBlocked(got, "not a leaf (denylisted: openssl*)")

    def test_pinned_still_failing_blocks(self):
        got = self.decide(reports({"check": [failure("slack")]}))
        self.assertBlocked(got, "slack: pinned-still-failing")
        self.assertTrue(got["failures"][0]["why"].startswith("pinned-still-failing (the pin did not take effect"))
        self.assertEqual(got["failures"][0]["system"], "x86_64-linux")

    def test_base_comparison_unavailable_blocks(self):
        got = self.decide(reports({"check": [failure("btop", notCausedByUpdate=None)]}))
        self.assertBlocked(got, "btop: base comparison unavailable")

    def test_nixpkgs_unchanged_blocks(self):
        got = self.decide(reports({"check": [failure("btop")]}), nixpkgs_moved=False)
        self.assertBlocked(got, "nixpkgs unchanged; the failure comes from a non-nixpkgs input")

    def test_nixpkgs_unchanged_still_lands_when_green(self):
        self.assertEqual(self.decide(reports(), nixpkgs_moved=False)["action"], "land")

    def test_missing_report_blocks(self):
        got = self.decide(reports(jobs=["check", "darwin"]))
        self.assertEqual(got["action"], "block")
        self.assertEqual(got["why"], "missing report: aarch64-linux")

    def test_round_cap_blocks(self):
        self.assertBlocked(self.decide(reports({"check": [failure("btop")]}), round_=3), "round cap")

    def test_failed_report_without_failures_blocks(self):
        reps = reports()
        reps[0]["ok"] = False
        self.assertEqual(self.decide(reps)["action"], "block")


class FinalizeTest(unittest.TestCase):
    def test_precedence(self):
        table = [
            (("land", "", ""), "combined", False, [], False),
            (("block", "land", "land"), "nixpkgs", True, ["combined"], True),
            (("block", "land", "block"), "nixpkgs", True, ["combined", "inputs"], False),
            (("block", "block", "land"), "inputs", True, ["combined", "nixpkgs"], False),
            (("block", "", "land"), "inputs", True, ["combined"], False),
            (("block", "block", "block"), "", True, ["combined", "nixpkgs", "inputs"], False),
            (("block", "", ""), "", True, ["combined"], False),
        ]
        for (c, n, i), land, blocked, sides, interaction in table:
            with self.subTest(combined=c, nixpkgs=n, inputs=i):
                self.assertEqual(
                    botcore.finalize({"combined": c, "nixpkgs": n, "inputs": i}),
                    {"land": land, "blocked": blocked, "sides": sides, "interaction": interaction},
                )


class FallbackAdvanceTest(unittest.TestCase):
    def setUp(self):
        self.base, self.new = load("lock-base.json"), load("lock-new.json")

    def test_zero_pins_and_moved_advances(self):
        self.assertEqual(botcore.fallback_advance(load("pins-empty.json"), self.base, self.new), NP_NEW)

    def test_auto_pin_holds_back(self):
        pins = {"frozenInputs": [], "pins": [{"attr": "btop", "mode": "auto", "since": TODAY}]}
        self.assertIsNone(botcore.fallback_advance(pins, self.base, self.new))

    def test_hold_pin_holds_back(self):
        pins = botcore.drop_auto_pins(load("pins-base.json"))
        self.assertIsNone(botcore.fallback_advance(pins, self.base, self.new))

    def test_nixpkgs_unmoved(self):
        self.assertIsNone(botcore.fallback_advance(load("pins-empty.json"), self.base, self.base))

    def test_fallback_already_at_new_rev(self):
        self.new["nodes"]["nixpkgs-fallback"]["locked"]["rev"] = NP_NEW
        self.assertIsNone(botcore.fallback_advance(load("pins-empty.json"), self.base, self.new))


class InputBumpsTest(unittest.TestCase):
    def test_bumps(self):
        self.assertEqual(
            botcore.input_bumps(load("lock-base.json"), load("lock-new.json")),
            [
                ("home-manager", "2222222", "5555555"),
                ("nixpkgs", "31ecbac", "0bb2eed"),
                ("nixpkgs-stable", "1111111", "4444444"),
                ("wallpapers", "Wa11AAA", "Wa11BBB"),
            ],
        )


class RenderPrBodyTest(unittest.TestCase):
    def render(self, new_pins, age, advanced):
        return botcore.render_pr_body(
            attempt="combined",
            base_lock=load("lock-base.json"),
            new_lock=load("lock-new.json"),
            base_pins=load("pins-base.json"),
            new_pins=new_pins,
            fallback_rev=NP_BASE,
            fallback_age_days=age,
            advanced=advanced,
            today=TODAY,
            run_url=RUN,
        )

    def test_pins_and_stale_flags(self):
        new = load("pins-base.json")
        new["pins"][0]["failedAt"] = NP_NEW
        new["pins"].append({"attr": "btop", "mode": "auto", "reason": "r", "since": TODAY, "failedAt": NP_NEW})
        body = self.render(new, 20, False)
        self.assertIn("Landed attempt: **combined**", body)
        self.assertIn("| `nixpkgs` | `31ecbac` | `0bb2eed` |", body)
        self.assertIn(f"Added:\n- `btop` (auto), since {TODAY} (0 days): r\n", body)
        self.assertIn(
            "- `hello` (auto), since 2026-10-01 (35 days) ⚠ missing security fixes: failed on x86_64-linux", body
        )
        self.assertIn("- `slack` (hold), since 2026-11-01 (4 days): screen sharing regression", body)
        self.assertIn(
            "`nixpkgs-fallback`: `31ecbac`, 20 days old ⚠ missing security fixes (held back by live pins)", body
        )
        self.assertIn("Advanced: no", body)

    def test_removed_pins_and_advanced_fallback(self):
        body = self.render(load("pins-empty.json"), 0, True)
        self.assertIn("Removed:\n- `hello` (auto)", body)
        self.assertNotIn("⚠", body)
        self.assertIn("Advanced: yes", body)

    def test_young_fallback_not_flagged(self):
        body = self.render(load("pins-base.json"), 14, False)
        self.assertIn("`nixpkgs-fallback`: `31ecbac`, 14 days old\n", body)


class RenderIssueBodyTest(unittest.TestCase):
    def test_hold_line_and_excerpt(self):
        reps = {
            "combined": reports({"check": [failure("btop", logExcerpt="error: Cannot build 'x'.")]}),
            "nixpkgs": reports({"darwin": [failure(None, leaf=False, why="step packages failed")]}),
        }
        body = botcore.render_issue_body(
            final=botcore.finalize({"combined": "block", "nixpkgs": "block", "inputs": ""}),
            reports_by_attempt=reps,
            run_url=RUN,
            today=TODAY,
        )
        self.assertIn(f"Run: {RUN}", body)
        self.assertIn("Failed: combined, nixpkgs", body)
        self.assertIn("#### `btop` on x86_64-linux (job check)", body)
        self.assertIn("- mapped: yes\n- leaf: yes\n- why: leaf", body)
        self.assertIn("```\nerror: Cannot build 'x'.\n```", body)
        self.assertIn(f'`{{"attr": "btop", "mode": "hold", "reason": "leaf", "since": "{TODAY}"}}`', body)
        self.assertIn("- mapped: no", body)
        self.assertEqual(body.count('"mode": "hold"'), 1)

    def test_fence_outgrows_backtick_runs(self):
        cases = {"plain": "```", "a ``` b": "````", "x ````` y `` z": "``````", "`": "```"}
        for text_, fence in cases.items():
            with self.subTest(text=text_):
                self.assertEqual(botcore._fenced(text_), [fence, text_, fence])

    def test_interaction_and_inputs_hint(self):
        reps = {"inputs": reports({"aarch64-linux": [failure(None, leaf=False, why="eval error")]})}
        body = botcore.render_issue_body(
            final=botcore.finalize({"combined": "block", "nixpkgs": "land", "inputs": "land"}),
            reports_by_attempt=reps,
            run_url=RUN,
            today=TODAY,
        )
        self.assertIn("a×b interaction", body)
        self.assertIn("Landed instead: **nixpkgs**", body)
        self.assertIn('"frozenInputs": [..., "<input>"]', body)
        self.assertNotIn('"mode": "hold"', body)


if __name__ == "__main__":
    unittest.main()

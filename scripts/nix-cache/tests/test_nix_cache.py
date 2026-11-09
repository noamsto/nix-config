import datetime
import http.client
import json
import os
import re
import unittest
import urllib.error
from pathlib import Path
from unittest import mock

import nix_cache as nc

UTC = datetime.UTC
NOW = datetime.datetime(2026, 11, 9, 12, 0, tzinfo=UTC)
GRACE = datetime.timedelta(days=3)
BIG = 10**12
DAY = datetime.timedelta(days=1)

H = {c: c * 32 for c in "abcdfghijk"}


def base(char, name="pkg"):
    return f"{H[char]}-{name}"


def narinfo_text(char, refs=(), url=None, name="pkg"):
    hash_ = H.get(char, char)
    url = url or f"nar/{hash_}.nar.zst"
    return (
        f"StorePath: /nix/store/{hash_}-{name}\n"
        f"URL: {url}\n"
        "FileSize: 10\n"
        f"References: {' '.join(refs)}\n"
    )


def node(char, kind, refs=(), parents=(), name="pkg"):
    info = None
    if kind in ("r2", "upstream", "local", "legacy"):
        info = nc.parse_narinfo(narinfo_text(char, refs, name=name))
        info.references = list(refs)
    return nc.Node(base(char, name), kind, info, set(parents))


class FakeResponse:
    def __init__(self, body):
        self.body = body

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def read(self):
        return self.body


def http_error(code):
    return urllib.error.HTTPError("http://x", code, "err", {}, None)


class FetchTextTest(unittest.TestCase):
    def run_fetch(self, outcomes):
        calls, sleeps = [], []
        queue = list(outcomes)

        def opener(request, timeout=None):
            calls.append(request)
            outcome = queue.pop(0)
            if isinstance(outcome, Exception):
                raise outcome
            return FakeResponse(outcome)

        try:
            result = nc.fetch_text("http://x/a.narinfo", opener, sleeps.append)
        except nc.FetchError as err:
            result = err
        return result, calls, sleeps

    def test_404_is_none_without_retry(self):
        result, calls, sleeps = self.run_fetch([http_error(404)])
        self.assertIsNone(result)
        self.assertEqual(len(calls), 1)
        self.assertEqual(sleeps, [])

    def test_403_retries_then_raises(self):
        result, calls, sleeps = self.run_fetch([http_error(403)] * 4)
        self.assertIsInstance(result, nc.FetchError)
        self.assertEqual(len(calls), 4)
        self.assertEqual(sleeps, [1, 2, 4])

    def test_incomplete_read_retries_then_raises(self):
        err = http.client.IncompleteRead(b"par", 10)
        result, calls, sleeps = self.run_fetch([err] * 4)
        self.assertIsInstance(result, nc.FetchError)
        self.assertEqual(len(calls), 4)
        self.assertEqual(sleeps, [1, 2, 4])

    def test_transient_error_then_success(self):
        result, calls, _ = self.run_fetch([urllib.error.URLError("boom"), b"ok"])
        self.assertEqual(result, "ok")
        self.assertEqual(len(calls), 2)

    def test_sends_user_agent(self):
        _, calls, _ = self.run_fetch([b"ok"])
        self.assertEqual(calls[0].get_header("User-agent"), nc.USER_AGENT)


class ComputeNeedTest(unittest.TestCase):
    def test_upstream_served_path_not_needed(self):
        nodes = {H["a"]: node("a", "upstream"), H["b"]: node("b", "local")}
        need = nc.compute_need(nodes, set())
        self.assertEqual(need.paths, {H["b"]})

    def test_pin_served_only_upstream_is_needed(self):
        nodes = {H["a"]: node("a", "upstream")}
        self.assertEqual(nc.compute_need(nodes, {H["a"]}).paths, {H["a"]})

    def test_pin_in_r2_not_needed(self):
        nodes = {H["a"]: node("a", "r2")}
        need = nc.compute_need(nodes, {H["a"]})
        self.assertEqual(need.paths, set())
        self.assertEqual(need.unresolved, set())

    def test_pin_absent_everywhere_is_needed(self):
        nodes = {H["a"]: node("a", "absent")}
        need = nc.compute_need(nodes, {H["a"]})
        self.assertEqual(need.paths, {H["a"]})
        self.assertEqual(need.unresolved, set())

    def test_non_pin_hole_is_unresolved(self):
        nodes = {H["a"]: node("a", "absent")}
        need = nc.compute_need(nodes, set())
        self.assertEqual(need.paths, set())
        self.assertEqual(need.unresolved, {H["a"]})

    def test_local_and_legacy_are_needed(self):
        nodes = {H["a"]: node("a", "local"), H["b"]: node("b", "legacy")}
        self.assertEqual(nc.compute_need(nodes, set()).paths, {H["a"], H["b"]})


class StubRefsTest(unittest.TestCase):
    def test_only_references_outside_need(self):
        nodes = {
            H["a"]: node("a", "local", refs=[base("b"), base("c")]),
            H["b"]: node("b", "local"),
            H["c"]: node("c", "upstream"),
        }
        stubs = nc.stub_refs({H["a"], H["b"]}, nodes)
        self.assertEqual(set(stubs), {H["c"]})
        self.assertEqual(stubs[H["c"]], nodes[H["c"]].narinfo.text)

    def test_self_reference_is_not_a_stub(self):
        nodes = {H["a"]: node("a", "local", refs=[base("a")])}
        self.assertEqual(nc.stub_refs({H["a"]}, nodes), {})

    def test_unservable_reference_gets_no_stub(self):
        nodes = {
            H["a"]: node("a", "local", refs=[base("b")]),
            H["b"]: node("b", "local"),
        }
        self.assertEqual(nc.stub_refs({H["a"]}, nodes), {})


class PruneUnuploadableTest(unittest.TestCase):
    def test_reference_neither_needed_nor_stubable_drops_path_and_dependents(self):
        nodes = {
            H["a"]: node("a", "local", refs=[base("b")]),
            H["b"]: node("b", "local", refs=[base("c")]),
            H["c"]: node("c", "absent"),
            H["d"]: node("d", "local"),
            H["f"]: node("f", "local", refs=[base("d")]),
        }
        # c is not needed and absent, so b is dropped, and a depends on b.
        need = {H["a"], H["b"], H["d"], H["f"]}
        kept, dropped = nc.prune_unuploadable(need, nodes)
        self.assertEqual(dropped, {H["a"], H["b"]})
        self.assertEqual(kept, {H["d"], H["f"]})

    def test_reference_with_stub_text_keeps_path(self):
        nodes = {
            H["a"]: node("a", "local", refs=[base("c")]),
            H["c"]: node("c", "upstream"),
        }
        kept, dropped = nc.prune_unuploadable({H["a"]}, nodes)
        self.assertEqual(kept, {H["a"]})
        self.assertEqual(dropped, set())

    def test_needed_reference_keeps_path(self):
        nodes = {
            H["a"]: node("a", "local", refs=[base("b")]),
            H["b"]: node("b", "local"),
        }
        kept, _ = nc.prune_unuploadable({H["a"], H["b"]}, nodes)
        self.assertEqual(kept, {H["a"], H["b"]})


class ClassifyTest(unittest.TestCase):
    def test_pin_not_in_r2_fails(self):
        nodes = {H["a"]: node("a", "upstream", name="kernel")}
        verdict = nc.classify(set(), nodes, {H["a"]})
        self.assertEqual(len(verdict.failures), 1)
        self.assertIn("kernel", verdict.failures[0])

    def test_uploaded_path_not_in_r2_fails(self):
        nodes = {H["a"]: node("a", "local")}
        verdict = nc.classify({H["a"]}, nodes, set())
        self.assertEqual(len(verdict.failures), 1)
        self.assertEqual(verdict.warnings, [])

    def test_non_pin_absent_is_warning_only(self):
        nodes = {H["a"]: node("a", "absent", name="hole")}
        verdict = nc.classify(set(), nodes, set())
        self.assertEqual(verdict.failures, [])
        self.assertEqual(verdict.warnings, [base("a", "hole")])

    def test_r2_paths_are_fine(self):
        nodes = {H["a"]: node("a", "r2")}
        verdict = nc.classify({H["a"]}, nodes, {H["a"]})
        self.assertEqual((verdict.failures, verdict.warnings), ([], []))


def obj(key, size=10, age=10 * DAY):
    return nc.Obj(key, size, NOW - age)


class PlanGcTest(unittest.TestCase):
    def plan(self, objects, texts=None, live=(), pins=(), holes=(), force=False,
             budget=BIG):
        if texts is None:
            texts = {
                o.key: narinfo_text(o.key[:32]) for o in objects
                if nc.is_narinfo_key(o.key) and len(o.key) == 40
            }
        return nc.plan_gc(
            objects, texts, set(live), set(pins), set(holes), force, NOW, GRACE,
            budget,
        )

    def pair(self, char, age=10 * DAY, size=10):
        return [
            obj(f"{H[char]}.narinfo", size, age),
            obj(f"nar/{H[char]}.nar.zst", size, age),
        ]

    def test_old_unreferenced_pair_deleted_narinfo_first(self):
        objs = self.pair("a") + self.pair("b")
        plan = self.plan(objs, live={H["b"]})
        self.assertIsNone(plan.abort_reason)
        self.assertEqual(plan.delete_narinfos, [f"{H['a']}.narinfo"])
        self.assertEqual(plan.delete_nars, [f"nar/{H['a']}.nar.zst"])

    def test_pin_older_than_grace_kept(self):
        objs = self.pair("a", age=100 * DAY) + self.pair("b")
        plan = self.plan(objs, pins={H["a"]}, force=True)
        self.assertNotIn(f"{H['a']}.narinfo", plan.delete_narinfos)
        self.assertNotIn(f"nar/{H['a']}.nar.zst", plan.delete_nars)
        self.assertIn(f"{H['b']}.narinfo", plan.delete_narinfos)

    def test_non_live_inside_grace_kept(self):
        objs = self.pair("a", age=DAY) + self.pair("b") + self.pair("c") + self.pair("d")
        plan = self.plan(objs, live={H["b"]})
        self.assertNotIn(f"{H['a']}.narinfo", plan.delete_narinfos)
        self.assertNotIn(f"nar/{H['a']}.nar.zst", plan.delete_nars)
        self.assertEqual(
            plan.delete_narinfos, [f"{H['c']}.narinfo", f"{H['d']}.narinfo"]
        )

    def test_budget_evicts_oldest_non_live_first(self):
        # All inside grace; 4 pairs of 20 bytes = 80. Budget 50 forces two out.
        objs = (
            self.pair("a", age=2 * DAY)
            + self.pair("b", age=DAY * 2 + datetime.timedelta(hours=5))
            + self.pair("c", age=datetime.timedelta(hours=5))
            + self.pair("d", age=datetime.timedelta(hours=2))
        )
        plan = self.plan(objs, budget=50)
        self.assertEqual(
            plan.delete_narinfos, [f"{H['a']}.narinfo", f"{H['b']}.narinfo"]
        )
        self.assertEqual(
            plan.delete_nars,
            [f"nar/{H['a']}.nar.zst", f"nar/{H['b']}.nar.zst"],
        )
        self.assertLessEqual(plan.retained_bytes, 50)

    def test_budget_never_evicts_live(self):
        objs = self.pair("a", age=2 * DAY) + self.pair("b", age=DAY)
        plan = self.plan(objs, live={H["a"]}, budget=0, force=True)
        self.assertNotIn(f"{H['a']}.narinfo", plan.delete_narinfos)
        self.assertIn(f"{H['b']}.narinfo", plan.delete_narinfos)

    def test_budget_never_touches_object_under_one_hour(self):
        objs = self.pair("a", age=datetime.timedelta(minutes=30)) + self.pair(
            "b", age=DAY
        )
        plan = self.plan(objs, budget=0, force=True)
        self.assertNotIn(f"{H['a']}.narinfo", plan.delete_narinfos)
        self.assertNotIn(f"nar/{H['a']}.nar.zst", plan.delete_nars)
        self.assertIn(f"{H['b']}.narinfo", plan.delete_narinfos)

    def test_nar_referenced_by_kept_narinfo_survives(self):
        shared = "nar/shared.nar.zst"
        objs = [
            obj(f"{H['a']}.narinfo"),
            obj(f"{H['b']}.narinfo"),
            obj(shared),
            obj(f"{H['c']}.narinfo"),
            obj("nar/c.nar.zst"),
        ]
        texts = {
            f"{H['a']}.narinfo": narinfo_text("a", url=shared),
            f"{H['b']}.narinfo": narinfo_text("b", url=shared),
            f"{H['c']}.narinfo": narinfo_text("c", url="nar/c.nar.zst"),
        }
        plan = self.plan(objs, texts=texts, live={H["b"]}, force=True)
        self.assertIn(f"{H['a']}.narinfo", plan.delete_narinfos)
        self.assertNotIn(shared, plan.delete_nars)
        self.assertIn("nar/c.nar.zst", plan.delete_nars)

    def test_nar_deleted_with_its_narinfo_when_unreferenced(self):
        objs = self.pair("a") + self.pair("b")
        plan = self.plan(objs, live={H["b"]})
        self.assertEqual(plan.delete_nars, [f"nar/{H['a']}.nar.zst"])

    def test_abort_pin_absent(self):
        plan = self.plan(self.pair("a"), pins={H["b"]})
        self.assertIn("pin", plan.abort_reason)
        self.assertEqual((plan.delete_narinfos, plan.delete_nars), ([], []))

    def test_abort_no_narinfos(self):
        plan = self.plan([obj("nar/x.nar.zst")], texts={})
        self.assertIsNotNone(plan.abort_reason)
        self.assertEqual((plan.delete_narinfos, plan.delete_nars), ([], []))

    def test_abort_reference_hole(self):
        plan = self.plan(self.pair("a") + self.pair("b"), live={H["b"]},
                         holes={H["c"]})
        self.assertIn("reference", plan.abort_reason)
        self.assertEqual((plan.delete_narinfos, plan.delete_nars), ([], []))

    def test_abort_over_sixty_percent_without_force(self):
        objs = self.pair("a") + self.pair("b")
        plan = self.plan(objs, live={H["b"]})
        self.assertIsNone(plan.abort_reason)  # exactly 50%
        objs = self.pair("a") + self.pair("b") + self.pair("c") + self.pair("d")
        plan = self.plan(objs, live={H["d"]})
        self.assertIn("--force", plan.abort_reason)
        self.assertEqual((plan.delete_narinfos, plan.delete_nars), ([], []))

    def test_force_overrides_sixty_percent_cap(self):
        objs = self.pair("a") + self.pair("b") + self.pair("c") + self.pair("d")
        plan = self.plan(objs, live={H["d"]}, force=True)
        self.assertIsNone(plan.abort_reason)
        self.assertEqual(len(plan.delete_narinfos), 3)

    def test_nix_cache_info_ignored(self):
        info = obj("nix-cache-info", 1000)
        plan = self.plan([info] + self.pair("a") + self.pair("b"), live={H["b"]})
        self.assertIsNone(plan.abort_reason)
        self.assertNotIn("nix-cache-info", plan.delete_narinfos + plan.delete_nars)
        # 4 counted objects, not 5: retained bytes exclude it.
        self.assertEqual(plan.retained_bytes, 20)

    def test_nix_cache_info_alone_is_not_a_narinfo(self):
        plan = self.plan([obj("nix-cache-info")], texts={})
        self.assertIn("no narinfos", plan.abort_reason)

    def test_unknown_keys_never_deleted(self):
        objs = [obj("README"), obj("sub/dir.narinfo")] + self.pair("a") + self.pair("b")
        plan = self.plan(objs, live={H["b"]})
        deleted = plan.delete_narinfos + plan.delete_nars
        self.assertNotIn("README", deleted)
        self.assertNotIn("sub/dir.narinfo", deleted)


class ApplyGcTest(unittest.TestCase):
    def test_narinfos_deleted_before_nars_and_relisted_nar_survives(self):
        events = []
        plan = nc.GcPlan(
            ["a.narinfo", "b.narinfo"], ["nar/a", "nar/b"], 0
        )

        def recorder(keys, remote, rclone, env):
            events.append(("delete", list(keys), remote, rclone))

        def relist():
            events.append(("relist",))
            return {"nar/b"}

        with mock.patch.object(nc, "rclone_delete", recorder):
            nc.apply_gc(plan, "r2:bucket", "/fake/rclone", {}, relist)
        self.assertEqual(
            events,
            [
                ("delete", ["a.narinfo", "b.narinfo"], "r2:bucket", "/fake/rclone"),
                ("relist",),
                ("delete", ["nar/a"], "r2:bucket", "/fake/rclone"),
            ],
        )

    def test_no_nars_skips_relist(self):
        plan = nc.GcPlan(["a.narinfo"], [], 0)
        relist = mock.Mock(side_effect=AssertionError("relist called"))
        with mock.patch.object(nc, "rclone_delete"):
            nc.apply_gc(plan, "r2:b", "/fake/rclone", {}, relist)
        relist.assert_not_called()


class PopSecretsTest(unittest.TestCase):
    def test_variable_removed_from_environ(self):
        with mock.patch.dict(os.environ, {"NC_TEST_SECRET": "s3", "NC_KEEP": "x"}):
            got = nc.pop_secrets(["NC_TEST_SECRET", "NC_MISSING"])
            self.assertEqual(got, {"NC_TEST_SECRET": "s3"})
            self.assertNotIn("NC_TEST_SECRET", os.environ)
            self.assertEqual(os.environ["NC_KEEP"], "x")


class VerifyArgsTest(unittest.TestCase):
    def test_empty_pins_is_none(self):
        self.assertIsNone(nc.verify_args([], "https://c", "key"))

    def test_pins_are_named(self):
        paths = ["/nix/store/a-k", "/nix/store/b-k"]
        args = nc.verify_args(paths, "https://c", "key:abc")
        self.assertEqual(args[:3], ["nix", "store", "verify"])
        self.assertIn("https://c", args)
        self.assertIn("key:abc", args)
        for path in paths:
            self.assertIn(path, args)


class LocalPathInfoTest(unittest.TestCase):
    def run_info(self, payload):
        path = f"/nix/store/{base('a')}"
        with mock.patch.object(nc.glob, "glob", return_value=[path]), mock.patch.object(
            nc, "run_json", return_value=payload(path)
        ):
            return nc.local_path_info(H["a"])

    def test_null_means_absent(self):
        self.assertIsNone(self.run_info(lambda p: {p: None}))

    def test_no_glob_match_is_absent(self):
        with mock.patch.object(nc.glob, "glob", return_value=[]):
            self.assertIsNone(nc.local_path_info(H["a"]))

    def test_full_path_references_become_base_names(self):
        info = self.run_info(
            lambda p: {p: {"references": [f"/nix/store/{base('b')}", p]}}
        )
        self.assertEqual(info.references, [base("b"), base("a")])


class NixConfigTest(unittest.TestCase):
    def test_existing_value_kept_and_two_lines_appended(self):
        out = nc.extend_nix_config("max-jobs = 4\n", "https://c", "k:1")
        self.assertEqual(
            out.splitlines(),
            [
                "max-jobs = 4",
                "extra-substituters = https://c",
                "extra-trusted-public-keys = k:1",
            ],
        )

    def test_empty_existing(self):
        out = nc.extend_nix_config("", "https://c", "k:1")
        self.assertEqual(
            out.splitlines(),
            ["extra-substituters = https://c", "extra-trusted-public-keys = k:1"],
        )

    def test_github_env_heredoc(self):
        out = nc.render_github_env("NIX_CONFIG", "a\nb\n", delimiter="EOF_X")
        self.assertEqual(out, "NIX_CONFIG<<EOF_X\na\nb\nEOF_X\n")


class MatchingLinesTest(unittest.TestCase):
    URL = "https://cache.example.com"

    def test_query_line_matches(self):
        out = f"querying info about '/nix/store/{base('a')}' on '{self.URL}' ...\n"
        lines, found = nc.matching_lines(out, self.URL)
        self.assertTrue(found)
        self.assertEqual(len(lines), 1)

    def test_bare_download_line_does_not_match(self):
        out = f"downloading '{self.URL}/{H['a']}.narinfo'...\nunrelated\n"
        lines, found = nc.matching_lines(out, self.URL)
        self.assertEqual(len(lines), 1)
        self.assertFalse(found)

    def test_query_on_other_cache_does_not_match(self):
        out = f"querying info about '/nix/store/x' on '{self.URL}.evil'\n"
        self.assertFalse(nc.matching_lines(out, self.URL)[1])


class ParseModtimeTest(unittest.TestCase):
    def test_nanoseconds_and_z(self):
        got = nc.parse_modtime("2026-11-09T12:00:00.123456789Z")
        self.assertEqual(got.tzinfo, UTC)
        self.assertEqual(got.microsecond, 123456)

    def test_offset_preserved_as_utc_instant(self):
        got = nc.parse_modtime("2026-11-09T14:00:00+02:00")
        self.assertEqual(got, NOW)


class RootsTest(unittest.TestCase):
    def build_yml(self):
        here = Path(nc.__file__).resolve().parent
        for candidate in (
            here / "build.yml",
            here / "../../.github/workflows/build.yml",
        ):
            if candidate.exists():
                return candidate.read_text()
        self.fail("build.yml not found beside nix_cache.py or in .github/workflows")

    def test_every_root_selector_is_built_by_workflow(self):
        roots = json.loads((Path(nc.__file__).parent / "roots.json").read_text())
        workflow = self.build_yml()
        self.assertTrue(roots)
        for job, spec in roots.items():
            for selector in spec["roots"]:
                pattern = r"-f \.#" + re.escape(selector) + r"(\s|$)"
                self.assertRegex(workflow, pattern, f"{job}: {selector}")


if __name__ == "__main__":
    unittest.main()

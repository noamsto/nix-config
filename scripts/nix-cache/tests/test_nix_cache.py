import argparse
import contextlib
import datetime
import http.client
import io
import json
import os
import re
import tempfile
import types
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

    def test_unparseable_narinfo_aborts_without_deleting(self):
        objs = self.pair("a") + self.pair("b")
        texts = {
            f"{H['a']}.narinfo": "URL: nar/x.nar.zst\n",
            f"{H['b']}.narinfo": narinfo_text("b"),
        }
        plan = self.plan(objs, texts=texts)
        self.assertTrue(plan.abort_reason.startswith("unparseable narinfo"))
        self.assertEqual(plan.delete_narinfos, [])
        self.assertEqual(plan.delete_nars, [])

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

    def texts_with_refs(self, refs_by_char, chars="abcdfg"):
        return {
            f"{H[c]}.narinfo": narinfo_text(
                c, [base(r) for r in refs_by_char.get(c, ())]
            )
            for c in chars
        }

    def test_reference_of_grace_kept_narinfo_is_kept(self):
        # a (2 days, inside grace) references b (10 days); neither is live.
        objs = self.pair("a", age=2 * DAY) + self.pair("b") + self.pair("c")
        texts = self.texts_with_refs({"a": "b"}, "abc")
        plan = self.plan(objs, texts=texts, force=True)
        self.assertEqual(plan.delete_narinfos, [f"{H['c']}.narinfo"])
        self.assertEqual(plan.delete_nars, [f"nar/{H['c']}.nar.zst"])

    def test_reference_closure_is_transitive(self):
        objs = (
            self.pair("a", age=DAY)
            + self.pair("b", age=5 * DAY)
            + self.pair("c", age=6 * DAY)
            + self.pair("d")
        )
        texts = self.texts_with_refs({"a": "b", "b": "c"}, "abcd")
        plan = self.plan(objs, texts=texts, force=True)
        self.assertEqual(plan.delete_narinfos, [f"{H['d']}.narinfo"])

    def test_self_and_unlisted_references_are_ignored(self):
        objs = self.pair("a") + self.pair("b", age=DAY)
        texts = self.texts_with_refs({"a": "ak", "b": "b"}, "ab")
        plan = self.plan(objs, texts=texts, force=True)
        self.assertEqual(plan.delete_narinfos, [f"{H['a']}.narinfo"])

    def test_budget_does_not_evict_referenced_narinfo(self):
        # a (newer) references b (older). 40 bytes retained, budget 30: only
        # a may go; the older b is referenced by a kept narinfo until then.
        objs = self.pair("a", age=2 * DAY) + self.pair(
            "b", age=2 * DAY + datetime.timedelta(hours=5)
        )
        texts = self.texts_with_refs({"a": "b"}, "ab")
        plan = self.plan(objs, texts=texts, budget=30, force=True)
        self.assertEqual(plan.delete_narinfos, [f"{H['a']}.narinfo"])
        self.assertEqual(plan.delete_nars, [f"nar/{H['a']}.nar.zst"])
        self.assertEqual(plan.retained_bytes, 20)

    def test_budget_eviction_frees_references_in_turn(self):
        objs = self.pair("a", age=2 * DAY) + self.pair(
            "b", age=2 * DAY + datetime.timedelta(hours=5)
        )
        texts = self.texts_with_refs({"a": "b"}, "ab")
        plan = self.plan(objs, texts=texts, budget=0, force=True)
        self.assertEqual(
            plan.delete_narinfos, [f"{H['a']}.narinfo", f"{H['b']}.narinfo"]
        )
        self.assertEqual(plan.retained_bytes, 0)

    def test_budget_never_evicts_reference_of_live_narinfo(self):
        objs = self.pair("a", age=DAY) + self.pair("b", age=2 * DAY)
        texts = self.texts_with_refs({"a": "b"}, "ab")
        plan = self.plan(objs, texts=texts, live={H["a"]}, budget=0, force=True)
        self.assertEqual((plan.delete_narinfos, plan.delete_nars), ([], []))

    def test_abort_listed_narinfo_without_text(self):
        objs = self.pair("a") + self.pair("b")
        texts = {f"{H['b']}.narinfo": narinfo_text("b")}
        plan = self.plan(objs, texts=texts, force=True)
        self.assertIn(f"{H['a']}.narinfo", plan.abort_reason)
        self.assertEqual((plan.delete_narinfos, plan.delete_nars), ([], []))

    def test_young_nar_of_budget_evicted_narinfo_is_kept(self):
        objs = [
            obj(f"{H['a']}.narinfo", age=2 * DAY),
            obj(f"nar/{H['a']}.nar.zst", age=datetime.timedelta(minutes=30)),
        ] + self.pair("b")
        plan = self.plan(objs, live={H["b"]}, budget=0, force=True)
        self.assertEqual(plan.delete_narinfos, [f"{H['a']}.narinfo"])
        self.assertNotIn(f"nar/{H['a']}.nar.zst", plan.delete_nars)

    def test_young_orphan_nar_kept_even_with_zero_budget(self):
        objs = self.pair("a") + [
            obj("nar/orphan.nar.zst", age=datetime.timedelta(minutes=30))
        ]
        plan = self.plan(objs, budget=0, force=True)
        self.assertEqual(plan.delete_narinfos, [f"{H['a']}.narinfo"])
        self.assertEqual(plan.delete_nars, [f"nar/{H['a']}.nar.zst"])


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


class RcloneBinaryTest(unittest.TestCase):
    def resolve(self, runner_temp, make_base=False):
        calls = []

        def fake_run(argv, **_kwargs):
            calls.append(argv)
            return types.SimpleNamespace(
                returncode=0, stdout="/nix/store/x-rclone\n", stderr=""
            )

        with tempfile.TemporaryDirectory() as tmp:
            env = {}
            if runner_temp:
                env["RUNNER_TEMP"] = tmp
                if make_base:
                    os.mkdir(os.path.join(tmp, "base"))
            with mock.patch.dict(os.environ, env):
                if not runner_temp:
                    os.environ.pop("RUNNER_TEMP", None)
                with mock.patch.object(nc.subprocess, "run", fake_run):
                    path = nc.rclone_binary()
            return path, calls[0], tmp

    def test_base_tree_lock_when_base_exists(self):
        path, argv, tmp = self.resolve(True, make_base=True)
        self.assertEqual(
            argv[argv.index("--inputs-from") + 1],
            f"git+file://{tmp}/base?shallow=1",
        )
        self.assertEqual(path, "/nix/store/x-rclone/bin/rclone")

    def test_checkout_lock_without_base(self):
        _, argv, _ = self.resolve(True)
        self.assertEqual(argv[argv.index("--inputs-from") + 1], ".")

    def test_checkout_lock_without_runner_temp(self):
        _, argv, _ = self.resolve(False)
        self.assertEqual(argv[argv.index("--inputs-from") + 1], ".")


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


CACHES = nc.Caches("https://r2.example", "r2-key:PUB", ["https://up.example"])


def proc(returncode=0, stdout=""):
    return types.SimpleNamespace(returncode=returncode, stdout=stdout, stderr="")


class LookupTest(unittest.TestCase):
    def kind(self, remote=(), local=False):
        def fetch(url):
            for base_url in remote:
                if url == f"{base_url}/{H['a']}.narinfo":
                    return narinfo_text("a")
            return None

        def local_fake(hash_):
            return nc.parse_narinfo(narinfo_text("a")) if local else None

        return nc.lookup(H["a"], CACHES, fetch=fetch, local=local_fake)[0]

    def test_r2_wins_over_upstream(self):
        self.assertEqual(
            self.kind(remote=["https://up.example", "https://r2.example"], local=True),
            "r2",
        )

    def test_upstream_before_local(self):
        self.assertEqual(self.kind(remote=["https://up.example"], local=True), "upstream")

    def test_local_before_legacy(self):
        self.assertEqual(self.kind(remote=[nc.LEGACY_CACHE], local=True), "local")

    def test_legacy_only(self):
        self.assertEqual(self.kind(remote=[nc.LEGACY_CACHE]), "legacy")

    def test_nowhere_is_absent(self):
        self.assertEqual(self.kind(), "absent")


class WalkTest(unittest.TestCase):
    def test_fetch_error_propagates_instead_of_reading_absent(self):
        def lookup_fn(hash_):
            raise nc.FetchError("boom")

        with self.assertRaises(nc.FetchError):
            nc.walk([f"/nix/store/{base('a')}"], lookup_fn)


class RealiseTest(unittest.TestCase):
    def run_realise(self, pins, build_pins=True, failing=()):
        calls = []

        def fake_run(cmd, **kwargs):
            calls.append(cmd)
            if cmd[:2] == ["nix", "build"] and cmd[-1] in {f".#{p}" for p in failing}:
                return proc(1)
            if cmd[0] == "nix-store" and "--check-validity" in cmd:
                return proc(0, "/nix/store/x-invalid\n")
            return proc(0)

        err = io.StringIO()
        with mock.patch.object(nc.subprocess, "run", fake_run), contextlib.redirect_stderr(err):
            invalid = nc.realise(pins, ["/nix/store/x-invalid"], build_pins=build_pins)
        return calls, invalid, err.getvalue()

    def builds(self, calls):
        return [c for c in calls if c[:2] == ["nix", "build"]]

    def test_default_builds_pins_normally(self):
        calls, _, _ = self.run_realise(["p1"])
        self.assertEqual(self.builds(calls), [["nix", "build", "--no-link", ".#p1"]])

    def test_no_build_pins_substitutes_only(self):
        calls, _, _ = self.run_realise(["p1", "p2"], build_pins=False)
        for cmd in self.builds(calls):
            self.assertEqual(cmd[3:5], ["--max-jobs", "0"])
        self.assertEqual(len(self.builds(calls)), 2)

    def test_failed_pin_is_reported_and_others_still_realised(self):
        for build_pins in (True, False):
            calls, invalid, err = self.run_realise(
                ["p1", "p2"], build_pins=build_pins, failing=["p1"]
            )
            self.assertIn("error: building pin p1 failed", err)
            self.assertEqual(len(self.builds(calls)), 2)
            self.assertTrue(any(c[0] == "nix-store" for c in calls))
            self.assertEqual(invalid, {"/nix/store/x-invalid"})


def enter_fake_repo(stack):
    """Point nc.REPO_ROOT at a temp repo holding a minimal roots.json, so the
    commands never depend on the real checkout (absent in the Nix sandbox)."""
    root = stack.enter_context(tempfile.TemporaryDirectory())
    os.makedirs(os.path.join(root, "scripts/nix-cache"))
    jobs = {"aarch64-linux": {"roots": [], "pins": ["sel"]}}
    with open(os.path.join(root, "scripts/nix-cache/roots.json"), "w") as handle:
        json.dump(jobs, handle)
    stack.enter_context(mock.patch.object(nc, "REPO_ROOT", root))


class CmdPushTest(unittest.TestCase):
    def args(self, **over):
        values = {
            "job": "aarch64-linux",
            "stage_only": None,
            "no_build_pins": False,
            "r2_bucket": "bucket",
            "r2_endpoint": "https://endpoint",
            "secrets": {
                "NIX_CACHE_SIGNING_KEY": "SECRET-KEY-MATERIAL",
                "R2_ACCESS_KEY_ID": "id",
                "R2_SECRET_ACCESS_KEY": "secret",
            },
        }
        values.update(over)
        return argparse.Namespace(**values)

    def run_push(self, args, **patches):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.ExitStack() as stack:
            enter_fake_repo(stack)
            for name, value in patches.items():
                stack.enter_context(mock.patch.object(nc, name, value))
            stack.enter_context(contextlib.redirect_stdout(out))
            stack.enter_context(contextlib.redirect_stderr(err))
            code = nc.cmd_push(args)
        return code, out.getvalue(), err.getvalue()

    def unreachable(self, name):
        return mock.Mock(side_effect=AssertionError(f"{name} reached"))

    def test_stage_only_without_signing_key_fails_before_any_io(self):
        code, _, err = self.run_push(
            self.args(stage_only="/stage", secrets={}),
            load_caches=self.unreachable("load_caches"),
            eval_pins=self.unreachable("eval_pins"),
        )
        self.assertEqual(code, 1)
        self.assertIn("NIX_CACHE_SIGNING_KEY", err)

    def test_signing_key_must_match_published_public_key(self):
        code, out, err = self.run_push(
            self.args(),
            load_caches=lambda root: CACHES,
            public_key_of=lambda key: "other-key:PUB",
            eval_pins=self.unreachable("eval_pins"),
        )
        self.assertEqual(code, 1)
        self.assertIn("does not match", err)
        self.assertIn(CACHES.public_key, err)
        self.assertNotIn("SECRET-KEY-MATERIAL", out + err)

    def test_underivable_public_key_has_its_own_message(self):
        code, out, err = self.run_push(
            self.args(),
            load_caches=lambda root: CACHES,
            public_key_of=lambda key: None,
            eval_pins=self.unreachable("eval_pins"),
        )
        self.assertEqual(code, 1)
        self.assertIn("could not derive a public key", err)
        self.assertNotIn("does not match", err)
        self.assertNotIn("SECRET-KEY-MATERIAL", out + err)

    def run_build_pins(self, no_build_pins):
        pin_path = f"/nix/store/{base('a', 'kernel')}"
        nodes = {H["a"]: node("a", "absent", name="kernel")}
        seen = []

        def realise(pins, paths, build_pins=True):
            seen.append(build_pins)
            return {pin_path}

        with mock.patch.object(nc.subprocess, "run", lambda cmd, **kw: proc(0)):
            self.run_push(
                self.args(no_build_pins=no_build_pins),
                load_caches=lambda root: CACHES,
                public_key_of=lambda key: CACHES.public_key,
                eval_pins=lambda selectors: {"sel": pin_path},
                eval_roots=lambda selectors: [],
                walk=lambda roots, fn: nodes,
                realise=realise,
            )
        return seen

    def test_no_build_pins_flag_disables_building_pins(self):
        self.assertEqual(self.run_build_pins(True), [False])

    def test_pins_are_built_by_default(self):
        self.assertEqual(self.run_build_pins(False), [True])

    def test_stage_only_skips_public_key_check(self):
        code, _, _ = self.run_push(
            self.args(stage_only="/stage"),
            load_caches=lambda root: CACHES,
            public_key_of=self.unreachable("public_key_of"),
            eval_pins=lambda selectors: {},
            eval_roots=lambda selectors: [],
            walk=lambda roots, fn: {},
        )
        self.assertEqual(code, 0)

    def test_pin_missing_from_r2_after_run_exits_one_and_is_reported(self):
        pin_path = f"/nix/store/{base('a', 'kernel')}"
        nodes = {H["a"]: node("a", "absent", name="kernel")}
        with mock.patch.object(nc.subprocess, "run", lambda cmd, **kw: proc(0)):
            code, _, err = self.run_push(
                self.args(no_build_pins=True),
                load_caches=lambda root: CACHES,
                public_key_of=lambda key: CACHES.public_key,
                eval_pins=lambda selectors: {"sel": pin_path},
                eval_roots=lambda selectors: [],
                walk=lambda roots, fn: nodes,
                realise=lambda pins, paths, build_pins=True: {pin_path},
            )
        self.assertEqual(code, 1)
        self.assertIn("pin", err)
        self.assertIn("kernel", err)


class GcCommandTest(unittest.TestCase):
    def args(self):
        return argparse.Namespace(
            secrets={"R2_ACCESS_KEY_ID": "id", "R2_SECRET_ACCESS_KEY": "secret"},
            r2_bucket="bucket",
            r2_endpoint="https://endpoint",
            force=False,
            grace_days=3,
            budget_bytes=BIG,
            delete=True,
        )

    def run_gc(self, listings, fetches, holes=(), live=()):
        deletes = []
        list_calls = iter(listings)
        fetch_calls = iter(fetches)
        out, err = io.StringIO(), io.StringIO()
        patches = {
            "load_caches": lambda root: CACHES,
            "mark": lambda jobs, fn: (set(live), set(), set(holes)),
            "rclone_binary": lambda: "/fake/rclone",
            "r2_env": lambda endpoint, creds: {},
            "list_objects": lambda remote, rclone, env: next(list_calls),
            "fetch_narinfos": lambda keys, base_url, fetch=None: next(fetch_calls),
            "rclone_delete": lambda keys, remote, rclone, env: deletes.append(
                list(keys)
            ),
        }
        with contextlib.ExitStack() as stack:
            enter_fake_repo(stack)
            for name, value in patches.items():
                stack.enter_context(mock.patch.object(nc, name, value))
            stack.enter_context(contextlib.redirect_stdout(out))
            stack.enter_context(contextlib.redirect_stderr(err))
            code = nc.cmd_gc(self.args())
        return code, out.getvalue(), deletes

    def old_pair_listing(self):
        return [
            obj(f"{H['a']}.narinfo"),
            obj(f"nar/{H['a']}.nar.zst"),
            obj(f"{H['b']}.narinfo"),
            obj(f"nar/{H['b']}.nar.zst"),
        ]

    def texts(self):
        return {f"{H[c]}.narinfo": narinfo_text(c) for c in "ab"}

    def test_every_abort_exits_one_with_error_and_listed_bytes(self):
        code, out, deletes = self.run_gc(
            [self.old_pair_listing()], [self.texts()], holes={H["c"]}, live={H["b"]}
        )
        self.assertEqual(code, 1)
        self.assertIn("::error::gc aborted: reference found on no cache", out)
        self.assertIn("40 bytes", out)
        self.assertEqual(deletes, [])

    def test_relist_with_unfetchable_listed_narinfo_stops_before_nars(self):
        new_listing = self.old_pair_listing() + [obj(f"{H['c']}.narinfo", age=0 * DAY)]
        code, out, deletes = self.run_gc(
            [self.old_pair_listing(), new_listing],
            [self.texts(), {}],
            live={H["b"]},
        )
        self.assertEqual(code, 1)
        self.assertIn("::error::gc aborted: listed narinfo", out)
        self.assertEqual(deletes, [[f"{H['a']}.narinfo"]])


class PublicKeyOfTest(unittest.TestCase):
    def test_returns_stripped_stdout_and_feeds_secret_on_stdin(self):
        seen = {}

        def run(cmd, **kwargs):
            seen["cmd"], seen["kwargs"] = cmd, kwargs
            return proc(0, "name:PUB\n")

        self.assertEqual(nc.public_key_of("name:SECRET", run=run), "name:PUB")
        self.assertEqual(seen["cmd"], ["nix", "key", "convert-secret-to-public"])
        self.assertEqual(seen["kwargs"]["input"], "name:SECRET")
        self.assertTrue(seen["kwargs"]["capture_output"])
        self.assertTrue(seen["kwargs"]["text"])
        self.assertNotIn("name:SECRET", " ".join(seen["cmd"]))

    def test_nonzero_exit_is_none(self):
        self.assertIsNone(nc.public_key_of("x", run=lambda cmd, **kw: proc(1, "junk")))


class UploadTest(unittest.TestCase):
    CREDS = types.MappingProxyType(
        {"R2_ACCESS_KEY_ID": "AKID-VALUE", "R2_SECRET_ACCESS_KEY": "SECRET-VALUE"}
    )

    def run_upload(self, results):
        calls = []
        queue = list(results)

        def fake_run(cmd, **kwargs):
            calls.append((cmd, kwargs))
            return proc(queue.pop(0))

        with tempfile.TemporaryDirectory() as stage_dir:
            os.mkdir(os.path.join(stage_dir, "nar"))
            with mock.patch.object(nc, "rclone_binary", lambda: "/fake/rclone"), \
                    mock.patch.object(nc.subprocess, "run", fake_run):
                try:
                    nc.upload(stage_dir, "bucket", "endpoint.example", self.CREDS)
                    error = None
                except RuntimeError as err:
                    error = err
        return calls, error, stage_dir

    def test_nars_then_narinfos_with_credentials_only_in_env(self):
        calls, error, stage_dir = self.run_upload([0, 0])
        self.assertIsNone(error)
        self.assertEqual(len(calls), 2)
        nar_cmd, narinfo_cmd = calls[0][0], calls[1][0]
        self.assertEqual(nar_cmd[:3], ["/fake/rclone", "copy", f"{stage_dir}/nar"])
        self.assertIn("r2:bucket/nar", nar_cmd)
        self.assertIn("*.narinfo", narinfo_cmd)
        self.assertIn("r2:bucket", narinfo_cmd)
        for cmd, kwargs in calls:
            joined = " ".join(cmd)
            self.assertNotIn("AKID-VALUE", joined)
            self.assertNotIn("SECRET-VALUE", joined)
            self.assertEqual(kwargs["env"]["RCLONE_CONFIG_R2_ACCESS_KEY_ID"], "AKID-VALUE")
            self.assertEqual(
                kwargs["env"]["RCLONE_CONFIG_R2_SECRET_ACCESS_KEY"], "SECRET-VALUE"
            )

    def test_failed_nar_copy_raises_before_narinfo_copy(self):
        calls, error, _ = self.run_upload([1, 0])
        self.assertIsInstance(error, RuntimeError)
        self.assertEqual(len(calls), 1)


class StageTest(unittest.TestCase):
    def run_stage(self, returncode):
        seen = {}

        def fake_run(cmd, **kwargs):
            url = next(a for a in cmd if a.startswith("file://"))
            key_file = re.search(r"secret-key=([^&]+)", url).group(1)
            seen["key_file"] = key_file
            seen["key_existed"] = os.path.exists(key_file)
            seen["stub_existed"] = os.path.exists(os.path.join(stage_dir, f"{H['c']}.narinfo"))
            return proc(returncode)

        with tempfile.TemporaryDirectory() as stage_dir:
            with mock.patch.object(nc.subprocess, "run", fake_run):
                try:
                    nc.stage(
                        ["/nix/store/x"], {H["c"]: narinfo_text("c")}, stage_dir, "KEY"
                    )
                    error = None
                except RuntimeError as err:
                    error = err
            leftovers = os.listdir(stage_dir)
        return seen, error, leftovers

    def test_stubs_and_key_file_removed_after_copy(self):
        seen, error, leftovers = self.run_stage(0)
        self.assertIsNone(error)
        self.assertTrue(seen["key_existed"] and seen["stub_existed"])
        self.assertFalse(os.path.exists(seen["key_file"]))
        self.assertEqual(leftovers, [])

    def test_stubs_and_key_file_removed_when_copy_fails(self):
        seen, error, leftovers = self.run_stage(1)
        self.assertIsInstance(error, RuntimeError)
        self.assertFalse(os.path.exists(seen["key_file"]))
        self.assertEqual(leftovers, [])


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

    def jobs_sections(self, workflow):
        """job name -> its section of build.yml (top-level keys under jobs:)."""
        _, _, jobs = workflow.partition("\njobs:\n")
        parts = re.split(r"^  ([A-Za-z0-9_-]+):\s*$", jobs, flags=re.MULTILINE)
        return dict(zip(parts[1::2], parts[2::2]))

    def test_every_root_selector_is_built_by_workflow_job(self):
        roots = json.loads((Path(nc.__file__).parent / "roots.json").read_text())
        sections = self.jobs_sections(self.build_yml())
        self.assertTrue(roots)
        for job, spec in roots.items():
            self.assertIn(job, sections)
            section = sections[job]
            built = set(re.findall(r"-f \.#(\S+)", section))
            self.assertEqual(built, set(spec["roots"]), job)
            self.assertIn(f"nix_cache.py push --job {job}", section)


if __name__ == "__main__":
    unittest.main()

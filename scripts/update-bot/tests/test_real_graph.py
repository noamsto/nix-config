"""classify_leaf against entries extracted from the real example-host closure.

real-graph.json holds botcore.normalize_drvs entries for a few targets and a
bounded subset of the closure drvs that list them in inputDrvs (referrers,
trimmed to name/outputs/buildInputs/propagatedBuildInputs).
"""

import json
import unittest
from pathlib import Path

import botcore

TARGETS = json.loads((Path(__file__).parent / "fixtures" / "real-graph.json").read_text())["targets"]


def target(attr: str) -> tuple[dict, list[dict]]:
    t = TARGETS[attr]
    return t["drv"], t["referrers"]


class RealGraphLeafTest(unittest.TestCase):
    def test_leaf_apps(self):
        for attr in ("ripgrep", "btop", "bat"):
            with self.subTest(attr=attr):
                drv, refs = target(attr)
                self.assertTrue(refs)
                self.assertEqual(botcore.classify_leaf(attr, drv, refs), (True, "leaf"))

    def test_openssl_denylisted(self):
        drv, refs = target("openssl")
        self.assertEqual(botcore.classify_leaf("openssl", drv, refs), (False, "denylisted: openssl*"))

    def test_openssl_has_dev_output(self):
        drv, refs = target("openssl")
        self.assertEqual(botcore.classify_leaf("ossl-test-alias", drv, refs), (False, "has dev output"))

    def test_openssl_linked_rule_on_real_referrers(self):
        # The real referrers link openssl's dev output only, and the dev key
        # trips rule 3 first. Rename that key (the store path stays real) so
        # rules 2 and 3 are bypassed and rule 4 runs on the raw referrers.
        drv, refs = target("openssl")
        outputs = {("devpath" if k == "dev" else k): v for k, v in drv["outputs"].items()}
        outputs = {k: v for k, v in outputs.items() if k in ("devpath", "out")}
        ok, why = botcore.classify_leaf("ossl-test-alias", {**drv, "outputs": outputs}, refs)
        self.assertFalse(ok)
        self.assertTrue(why.startswith("linked into "), why)

    def test_python_module_nested_attr(self):
        drv, refs = target("python3Packages.pyyaml")
        self.assertEqual(botcore.classify_leaf("python3Packages.pyyaml", drv, refs), (False, "nested attr"))

    def test_python_module_linked_under_plain_alias(self):
        # pyyaml has only dist/out outputs, so rule 4 fires directly.
        drv, refs = target("python3Packages.pyyaml")
        ok, why = botcore.classify_leaf("pyyaml-alias", drv, refs)
        self.assertFalse(ok)
        self.assertTrue(why.startswith("linked into "), why)


if __name__ == "__main__":
    unittest.main()

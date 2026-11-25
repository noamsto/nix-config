"""The cascade config files parse and name real root inputs.

.github/upstreams.json maps a source repo to the root input that pins it, and
.github/consumers.json lists the repos notified when it bumps. The nix check
copies both, plus flake.lock, into src/, so look there first and fall back to
the repo tree.
"""

import json
import unittest
from pathlib import Path

import botcore


def config_file(name: str) -> Path:
    for path in (
        Path(__file__).parents[1] / name,
        Path(__file__).parents[3] / ".github" / name,
    ):
        if path.exists():
            return path
    raise AssertionError(f"config file {name} not found next to the tests or in the repo")


def lock_file() -> Path:
    for path in (
        Path(__file__).parents[1] / "flake.lock",
        Path(__file__).parents[3] / "flake.lock",
    ):
        if path.exists():
            return path
    raise AssertionError("flake.lock not found next to the tests or in the repo")


class ConfigTest(unittest.TestCase):
    def test_upstreams(self):
        upstreams = botcore.parse_upstreams(json.loads(config_file("upstreams.json").read_text()))
        self.assertEqual(upstreams["noamsto/tmux-og"], "tmux-og")

    def test_consumers(self):
        botcore.parse_consumers(json.loads(config_file("consumers.json").read_text()))

    def test_upstreams_are_root_inputs(self):
        lock = json.loads(lock_file().read_text())
        upstreams = botcore.parse_upstreams(json.loads(config_file("upstreams.json").read_text()))
        for source, name in upstreams.items():
            with self.subTest(input=name):
                node = botcore._root_node(lock, name)
                self.assertIsNotNone(node)
                original = node["original"]
                self.assertEqual(f'{original["owner"]}/{original["repo"]}', source)


if __name__ == "__main__":
    unittest.main()

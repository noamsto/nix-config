import unittest

import update_bot


class FlakeUrlTest(unittest.TestCase):
    def test_shallow_suffix_on_git_file_url(self):
        self.assertEqual(update_bot.flake_url("/x/y"), "git+file:///x/y?shallow=1")


if __name__ == "__main__":
    unittest.main()

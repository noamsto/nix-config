import base64
import contextlib
import io
import json
import os
import re
import shutil
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest import mock

import silence
import stt_compare
import testclips

FAKE_KEY = "fake-key-do-not-leak-0123456789"


class FakeInteractions:
    """Loopback Gemini Interactions server: deterministic text per request, records what it got."""

    def __init__(self, text_for=lambda i: f"hello world zanzibar{i}", fail_on=()):
        self.fail_on = set(fail_on)
        self.requests = []  # (audio seconds, custom_vocabulary)
        self._text_for = text_for
        self._lock = threading.Lock()
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                audio = base64.b64decode(body["input"][0]["data"])
                config = body["generation_config"]["transcription_config"]
                with owner._lock:
                    i = len(owner.requests)
                    owner.requests.append((silence.read_wav(audio).seconds, config.get("custom_vocabulary", [])))
                if i in owner.fail_on:
                    self.send_error(500)
                    return
                payload = json.dumps(
                    {"steps": [{"type": "model_output", "content": [{"type": "text", "text": owner._text_for(i)}]}]}
                ).encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

        self._server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self._server.daemon_threads = True
        self.url = f"http://127.0.0.1:{self._server.server_address[1]}"
        threading.Thread(target=self._server.serve_forever, daemon=True).start()

    def close(self):
        self._server.shutdown()
        self._server.server_close()


class WordDiffTest(unittest.TestCase):
    def test_ignores_case_and_punctuation(self):
        self.assertEqual(stt_compare.word_diff("Hello, World.", "hello world"), 0)

    def test_counts_replaced_and_inserted_words(self):
        self.assertEqual(stt_compare.word_diff("a b c", "a x c"), 1)
        self.assertEqual(stt_compare.word_diff("a b", "a b c d"), 2)
        self.assertEqual(stt_compare.word_diff("a b c d", "a"), 3)


class CompareCliTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.model = os.environ["VOXTYPE_GEMINI_VAD_MODEL"]
        cls.tmp = tempfile.mkdtemp()
        a = testclips.to_16k(*testclips.speak(cls.tmp, "en-us", "please open a new account for me today", "a.wav"))
        b = testclips.to_16k(*testclips.speak(cls.tmp, "en-us", "and then close the old savings account", "b.wav"))
        signal = testclips.clip(16000, [("s", 2.0), ("a", a), ("s", 1.3), ("a", b), ("s", 2.0)])
        cls.clips = os.path.join(cls.tmp, "clips")
        os.mkdir(cls.clips)
        cls.clip_bytes = testclips.to_wav_bytes(signal, 16000)
        with open(os.path.join(cls.clips, "clip.wav"), "wb") as f:
            f.write(cls.clip_bytes)
        cls.duration = len(signal) / 16000
        cls.key_file = os.path.join(cls.tmp, "key")
        with open(cls.key_file, "w") as f:
            f.write(FAKE_KEY)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def setUp(self):
        self.server = FakeInteractions()
        self.addCleanup(self.server.close)

    def run_cli(self, *extra, directory=None, server=None):
        server = server or self.server
        argv = [
            "--key-file", self.key_file,
            "--base-url", server.url,
            "--vad-model", self.model,
            *extra,
            directory or self.clips,
        ]  # fmt: skip
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            stt_compare.main(argv)
        return out.getvalue()

    def test_variants_send_whole_trimmed_and_per_phrase_audio(self):
        out = self.run_cli("--segment")
        reqs = self.server.requests
        self.assertEqual(len(reqs), 6)  # whole, trimmed, 2 phrases, 2 phrases with context
        whole, trimmed = reqs[0][0], reqs[1][0]
        self.assertAlmostEqual(whole, self.duration, places=2)
        self.assertLess(trimmed, whole - 2.0)
        phrases_sent = reqs[2][0] + reqs[3][0]
        self.assertLessEqual(phrases_sent, trimmed + 0.2)
        self.assertAlmostEqual(reqs[4][0] + reqs[5][0], phrases_sent, places=2)

        self.assertIn(f"== clip.wav ({self.duration:.1f}s)", out)
        for label in ("whole", "trimmed", "phrases", "phrases+context"):
            self.assertRegex(out, rf"(?m)^  {re.escape(label)}\s+\d+\.\ds")
        self.assertIn(f"{whole:.1f}s", out)
        self.assertIn(f"{trimmed:.1f}s", out)
        self.assertRegex(out, r"(?m)^  phrases\s+\S+s\s+2 phrases\s+hello world zanzibar2 hello world zanzibar3$")
        self.assertEqual(re.findall(r"diff vs whole: (\d+) words", out), ["1", "4", "4"])
        self.assertRegex(out, r"(?m)^  trimmed\s.*\n\s+diff vs whole: 1 words$")
        self.assertIn("totals", out)
        self.assertRegex(out, r"(?m)^  whole\s+\d+\.\ds\s+100% of whole$")
        self.assertNotIn(FAKE_KEY, out)

    def test_context_variant_forwards_rare_words_of_previous_phrase_only(self):
        self.run_cli("--segment")
        reqs = self.server.requests
        self.assertNotIn("zanzibar2", reqs[3][1])  # plain phrases: no context
        self.assertIn("zanzibar4", reqs[5][1])  # phrases+context: first phrase's reply
        self.assertNotIn("zanzibar4", reqs[4][1])

    def test_vocabulary_env_reaches_every_request(self):
        with mock.patch.dict(os.environ, {"VOXTYPE_GEMINI_VOCABULARY": "Hyprland"}):
            self.run_cli("--segment")
        for _, vocabulary in self.server.requests:
            self.assertIn("Hyprland", vocabulary)

    def test_markdown_table_escapes_pipes_and_newlines(self):
        server = FakeInteractions(lambda i: "a|b\nc")
        self.addCleanup(server.close)
        out = self.run_cli("--segment", "--markdown", server=server)
        lines = out.splitlines()
        self.assertEqual(lines[0], "| clip | variant | sent (s) | vs whole (words) | transcript |")
        self.assertRegex(lines[1], r"^\|(?:\s*-+\s*\|){5}$")
        self.assertIn("a\\|b c", out)
        self.assertNotIn("a|b", out)
        rows = [line for line in lines if line.startswith("| clip.wav")]
        self.assertEqual(len(rows), 4)
        self.assertNotIn("== ", out)

    def test_unreadable_clip_prints_error_row_and_continues(self):
        with tempfile.TemporaryDirectory() as directory:
            with open(os.path.join(directory, "a-bad.wav"), "wb") as f:
                f.write(b"not a wav")
            with open(os.path.join(directory, "b-good.wav"), "wb") as f:
                f.write(self.clip_bytes)
            out = self.run_cli("--segment", directory=directory)
            md = self.run_cli("--segment", "--markdown", directory=directory)
        self.assertRegex(out, r"(?m)^== a-bad\.wav\n\s+<error: ")
        self.assertIn("== b-good.wav", out)
        self.assertRegex(out, r"(?m)^  phrases\+context\s")
        self.assertRegex(md, r"(?m)^\| a-bad\.wav \|.*<error: ")
        self.assertIn("| b-good.wav | whole |", md)

    def test_one_failing_variant_leaves_the_others_running(self):
        with mock.patch.object(stt_compare, "transcribe_trimmed", side_effect=OSError("boom")):
            out = self.run_cli("--segment")
        self.assertRegex(out, r"(?m)^  trimmed\s+<error: boom>$")
        self.assertRegex(out, r"(?m)^  phrases\+context\s")

    def test_totals_cover_only_clips_whose_variants_all_succeeded(self):
        with tempfile.TemporaryDirectory() as directory:
            for name in ("a.wav", "b.wav"):
                with open(os.path.join(directory, name), "wb") as f:
                    f.write(self.clip_bytes)
            # clip a takes requests 0-5; request 7 is clip b's trimmed variant
            server = FakeInteractions(fail_on={7})
            self.addCleanup(server.close)
            out = self.run_cli("--segment", directory=directory, server=server)
            md = self.run_cli("--segment", "--markdown", directory=directory, server=FakeInteractions(fail_on={7}))
        totals = out.split("== totals")[1]
        self.assertIn("1 of 2 clips", totals)
        self.assertIn("1 excluded", totals)
        self.assertRegex(totals, rf"(?m)^  whole\s+{self.duration:.1f}s\s+100% of whole$")
        self.assertRegex(md, r"(?m)^\| total \(1 of 2 clips, 1 excluded\) \| whole \|")

    def test_segment_requires_vad_model(self):
        env = {k: v for k, v in os.environ.items() if k != "VOXTYPE_GEMINI_VAD_MODEL"}
        err = io.StringIO()
        with (
            mock.patch.dict(os.environ, env, clear=True),
            contextlib.redirect_stderr(err),
            self.assertRaises(SystemExit) as ctx,
        ):
            stt_compare.main(["--key-file", self.key_file, "--segment", self.clips])
        self.assertEqual(ctx.exception.code, 2)
        self.assertIn("--vad-model", err.getvalue())

    def test_default_mode_compares_the_four_engines(self):
        out = io.StringIO()
        with (
            mock.patch.object(stt_compare, "gemini_transcribe", return_value="gem text"),
            mock.patch.object(
                stt_compare, "flash_verbatim", side_effect=lambda key, clip, model, level: f"{model}/{level} text"
            ),
            mock.patch.object(stt_compare, "parakeet", return_value="para text"),
            contextlib.redirect_stdout(out),
        ):
            stt_compare.main(["--key-file", self.key_file, self.clips])
        lines = out.getvalue().splitlines()
        lite = re.escape(stt_compare.FLASH_LITE_MODEL)
        flash = re.escape(stt_compare.FLASH_3_8_MODEL)
        self.assertEqual(lines[0], "== clip.wav")
        self.assertRegex(lines[1], r"^  Gemini Transcribe\s+gem text$")
        self.assertRegex(lines[2], rf"^  {lite}\s+{lite}/minimal text$")
        self.assertRegex(lines[3], r"^  Parakeet \(local\)\s+para text$")
        self.assertRegex(lines[4], rf"^  {flash}\s+{flash}/low text$")
        self.assertEqual(len(lines), 5)
        self.assertEqual(self.server.requests, [])


if __name__ == "__main__":
    unittest.main()

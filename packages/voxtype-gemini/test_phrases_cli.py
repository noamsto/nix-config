import contextlib
import io
import json
import os
import shutil
import socket
import stat
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest import mock

import adapter
import numpy as np
import phrases
import silence
import testclips

WAIT = 10  # bound on every synchronisation wait, so a bug fails instead of hanging
FILLERS = "uh|um|er|ah|eh|hmm|hm|mm|mhm"


class FakeAdapter:
    """Loopback stand-in for the adapter; records the multipart fields of each request."""

    def __init__(self, behave=None):
        self.requests = []
        self.behave = behave or (lambda i, fields: (200, {"text": f"reply {i}"}, {}))
        self._lock = threading.Lock()
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_POST(self):
                port = self.server.server_address[1]
                if "Origin" in self.headers or self.headers.get("Host") != f"127.0.0.1:{port}":
                    return self.send_error(403)
                body = self.rfile.read(int(self.headers["Content-Length"]))
                fields = adapter.parse_multipart(self.headers["Content-Type"], body)
                fields["_path"] = self.path
                with owner._lock:
                    i = len(owner.requests)
                    owner.requests.append(fields)
                status, payload, headers = owner.behave(i, fields)
                data = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
                self.send_response(status)
                for k, v in headers.items():
                    self.send_header(k, v)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        self._server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self._server.server_address[1]}"
        threading.Thread(target=self._server.serve_forever, daemon=True).start()

    def close(self):
        self._server.shutdown()
        self._server.server_close()

    def prompts(self):
        return [r["prompt"][1].decode() if "prompt" in r else None for r in self.requests]


def closed_port_url():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return f"http://127.0.0.1:{s.getsockname()[1]}"


class Local:
    def __init__(self, text="local text"):
        self.text = text
        self.calls = []

    def __call__(self, samples, prompt=None):
        self.calls.append((len(samples), prompt))
        return self.text


SAMPLES = np.full(8000, 0.1, dtype=np.float32)


class AdapterClientTest(unittest.TestCase):
    def setUp(self):
        self.server = FakeAdapter()
        self.addCleanup(self.server.close)

    def test_posts_wav_file_field_and_parses_text(self):
        text = phrases.adapter_transcribe(self.server.url, SAMPLES, None)
        self.assertEqual(text, "reply 0")
        (req,) = self.server.requests
        self.assertEqual(req["_path"], "/v1/audio/transcriptions")
        mime, data = req["file"]
        self.assertEqual(mime, "audio/wav")
        wav = silence.read_wav(data)
        self.assertEqual((wav.rate, wav.channels, wav.n_frames), (16000, 1, len(SAMPLES)))

    def test_prompt_field_only_when_truthy(self):
        phrases.adapter_transcribe(self.server.url, SAMPLES, None)
        phrases.adapter_transcribe(self.server.url, SAMPLES, "")
        phrases.adapter_transcribe(self.server.url, SAMPLES, "שלום hello")
        self.assertEqual(self.server.prompts(), [None, None, "שלום hello"])

    def test_samples_clipped_before_int16(self):
        phrases.adapter_transcribe(self.server.url, np.array([2.0, -2.0, 0.0], np.float32), None)
        wav = silence.read_wav(self.server.requests[0]["file"][1])
        self.assertEqual(testclips.samples_of(wav).tolist(), [32767, -32767, 0])

    def test_non_200_raises(self):
        self.server.behave = lambda i, f: (502, {"error": "upstream"}, {})
        with self.assertRaises(OSError):
            phrases.adapter_transcribe(self.server.url, SAMPLES, None)

    def test_malformed_json_and_missing_text_raise(self):
        for payload in (b"not json", {"nope": 1}, {"text": 5}, [1]):
            self.server.behave = lambda i, f, p=payload: (200, p, {})
            with self.assertRaises(ValueError):
                phrases.adapter_transcribe(self.server.url, SAMPLES, None)

    def test_redirect_is_not_followed(self):
        self.server.behave = lambda i, f: (302, b"", {"Location": self.server.url + "/other"})
        with self.assertRaises(OSError):
            phrases.adapter_transcribe(self.server.url, SAMPLES, None)
        self.assertEqual(len(self.server.requests), 1)


class FallbackTest(unittest.TestCase):
    def setUp(self):
        self.notes = []
        self.local = Local()
        self.server = FakeAdapter()
        self.addCleanup(self.server.close)

    def transcriber(self, url, local="default"):
        local = self.local if local == "default" else local
        return phrases.FallbackTranscriber(url, local, self.notes.append, timeout=5.0)

    def quiet(self):
        return contextlib.redirect_stderr(io.StringIO())

    def test_adapter_down_uses_local_and_notifies_once(self):
        t = self.transcriber(closed_port_url())
        with self.quiet():
            results = [t(SAMPLES, "p") for _ in range(3)]
        self.assertEqual(results, ["local text"] * 3)
        self.assertEqual(len(self.local.calls), 3)
        self.assertEqual(self.local.calls[0], (len(SAMPLES), "p"))
        self.assertEqual(self.notes, ["Gemini unreachable, using local model"])

    def test_http_502_falls_back(self):
        self.server.behave = lambda i, f: (502, {"error": "x"}, {})
        t = self.transcriber(self.server.url)
        with self.quiet():
            self.assertEqual(t(SAMPLES, None), "local text")
        self.assertEqual(len(self.notes), 1)

    def test_success_resets_outage_flag(self):
        mode = {"status": 502}
        self.server.behave = lambda i, f: (mode["status"], {"text": "gemini"}, {})
        t = self.transcriber(self.server.url)
        with self.quiet():
            t(SAMPLES, None)
            t(SAMPLES, None)
            self.assertEqual(len(self.notes), 1)
            mode["status"] = 200
            self.assertEqual(t(SAMPLES, None), "gemini")
            self.assertEqual(len(self.local.calls), 2)
            mode["status"] = 502
            t(SAMPLES, None)
        self.assertEqual(len(self.notes), 2)

    def test_no_local_model_reraises_without_notifying(self):
        t = self.transcriber(closed_port_url(), local=None)
        with self.quiet(), self.assertRaises(OSError):
            t(SAMPLES, None)
        self.assertEqual(self.notes, [])

    def test_log_never_contains_text_or_prompt(self):
        self.server.behave = lambda i, f: (200, {"text": "SECRETREPLY"}, {})
        t = self.transcriber(self.server.url)
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            t(SAMPLES, "SECRETPROMPT")
        self.assertNotIn("SECRET", err.getvalue())
        self.assertIn("ok", err.getvalue())


class CleanTextTest(unittest.TestCase):
    def clean(self, text):
        return phrases.clean_text(text, FILLERS)

    def test_leading_filler_dropped_and_next_letter_capitalised(self):
        self.assertEqual(self.clean("um hello world"), "Hello world")
        self.assertEqual(self.clean("Uh, so it works"), "So it works")
        self.assertEqual(self.clean("hmm. okay"), "Okay")

    def test_inner_filler_removed_with_one_trailing_comma(self):
        # the comma before the filler stays: only one trailing comma is eaten
        self.assertEqual(self.clean("so, uh, I think"), "so, I think")
        self.assertEqual(self.clean("it was um fine"), "it was fine")

    def test_filler_only_text_is_empty(self):
        self.assertEqual(self.clean("hmm."), "")
        self.assertEqual(self.clean("Um, uh."), "")
        self.assertEqual(self.clean(""), "")

    def test_space_and_commas_before_terminal_punctuation_removed(self):
        self.assertEqual(self.clean("Hello , world !"), "Hello , world!")
        self.assertEqual(self.clean("wait , ?"), "wait?")

    def test_repeated_spaces_collapsed_and_stripped(self):
        self.assertEqual(self.clean("  a   b  "), "a b")

    def test_whole_words_only(self):
        self.assertEqual(self.clean("the umbrella and human"), "the umbrella and human")

    def test_hebrew_untouched(self):
        self.assertEqual(self.clean("שלום עולם, מה שלומך?"), "שלום עולם, מה שלומך?")
        self.assertEqual(self.clean("שלום um world"), "שלום world")

    def test_newlines_and_tabs_become_single_spaces(self):
        self.assertEqual(self.clean("hello\nworld"), "hello world")
        self.assertEqual(self.clean("a\tb\r\nc"), "a b c")
        self.assertEqual(self.clean("\n"), "")

    def test_control_characters_are_dropped(self):
        self.assertEqual(self.clean("he\x00llo \x1bwor\x07ld"), "hello world")

    def test_lone_surrogates_are_dropped(self):
        self.assertEqual(self.clean("hello \ud83d world"), "hello world")

    def test_format_characters_are_kept(self):
        self.assertEqual(self.clean("שלום\u200f world"), "שלום\u200f world")


class CliArgsTest(unittest.TestCase):
    def test_missing_vad_model_is_an_argparse_error(self):
        err = io.StringIO()
        with contextlib.redirect_stderr(err), self.assertRaises(SystemExit) as ctx:
            phrases.main(["--url", "http://127.0.0.1:1"], environ={})
        self.assertEqual(ctx.exception.code, 2)
        self.assertIn("--vad-model", err.getvalue())

    def test_missing_url_is_an_argparse_error(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as ctx:
            phrases.main([], environ={"VOXTYPE_GEMINI_VAD_MODEL": "m"})
        self.assertEqual(ctx.exception.code, 2)

    def test_defaults_come_from_environment(self):
        env = {
            "VOXTYPE_GEMINI_VAD_MODEL": "model.onnx",
            "VOXTYPE_GEMINI_PHRASE_PAUSE_SECS": "1.1",
            "VOXTYPE_GEMINI_PHRASE_MIN_SECS": "2.5",
        }
        args = phrases.parse_args(["--url", "http://x"], env)
        self.assertEqual((args.vad_model, args.pause, args.min_phrase), ("model.onnx", 1.1, 2.5))
        self.assertEqual((args.hold, args.device, args.wtype), (3.0, "plug:default", "wtype"))
        self.assertIsNone(args.local_model_dir)
        self.assertFalse(args.no_context)


def vad_env():
    return {"VOXTYPE_GEMINI_VAD_MODEL": os.environ["VOXTYPE_GEMINI_VAD_MODEL"]}


class ReadyLineTest(unittest.TestCase):
    """The ready line follows the first audio read, never the capture process start."""

    def run_main(self, stdout):
        capture = mock.Mock()
        capture.stdout = stdout
        capture.poll.return_value = 0
        err = io.StringIO()
        with (
            mock.patch.object(phrases.subprocess, "Popen", return_value=capture),
            contextlib.redirect_stderr(err),
        ):
            code = phrases.main(["--url", "http://127.0.0.1:1"], environ=vad_env())
        return code, err.getvalue()

    def test_ready_line_printed_after_first_audio(self):
        code, err = self.run_main(io.BytesIO(bytes(2 * 1024)))
        self.assertEqual(code, 0)
        self.assertIn("Please speak\n", err)
        self.assertNotIn("capture ended", err)

    def test_dead_capture_exits_1_without_ready_line(self):
        code, err = self.run_main(io.BytesIO(b""))
        self.assertEqual(code, 1)
        self.assertNotIn("Please speak", err)
        self.assertIn("voxtype-gemini-phrases: capture ended before any audio", err)

    def test_empty_input_file_exits_1_without_ready_line(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "empty.wav")
            with open(path, "wb") as f:
                f.write(testclips.to_wav_bytes(np.zeros(0), 16000))
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                code = phrases.main(
                    ["--url", "http://127.0.0.1:1", "--input-file", path], environ=vad_env()
                )
        self.assertEqual(code, 1)
        self.assertNotIn("Please speak", err.getvalue())
        self.assertIn("capture ended before any audio", err.getvalue())


class EndToEndTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.model = os.environ["VOXTYPE_GEMINI_VAD_MODEL"]
        cls.tmp = tempfile.mkdtemp()
        a = cls.say("please open a new account for me today", "a.wav")
        b = cls.say("and then close the old savings account", "b.wav")
        cls.first_end = len(a)
        signal = testclips.clip(16000, [("s", 0.3), ("a", a), ("s", 1.3), ("a", b), ("s", 0.3)])
        cls.clip_path = os.path.join(cls.tmp, "clip.wav")
        with open(cls.clip_path, "wb") as f:
            f.write(testclips.to_wav_bytes(signal, 16000))
        cls.gate = round(0.3 * 16000) + cls.first_end + round(1.2 * 16000)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    @classmethod
    def say(cls, text, name):
        return testclips.to_16k(*testclips.speak(cls.tmp, "en-us", text, name))

    def setUp(self):
        self.server = FakeAdapter()
        self.addCleanup(self.server.close)
        self.typed_file = os.path.join(self.tmp, f"typed-{self.id()}")
        self.wtype = os.path.join(self.tmp, f"wtype-{self.id()}")
        with open(self.wtype, "w") as f:
            f.write(f'#!/bin/sh\nprintf \'%s\\n\' "$@" >> "{self.typed_file}"\n')
        os.chmod(self.wtype, os.stat(self.wtype).st_mode | stat.S_IXUSR)

    def typed(self):
        if not os.path.exists(self.typed_file):
            return []
        with open(self.typed_file) as f:
            return f.read().splitlines()

    def run_main(self, *extra, gated=False):
        argv = [
            "--url", self.server.url,
            "--input-file", self.clip_path,
            "--wtype", self.wtype,
            *extra,
        ]  # fmt: skip
        err = io.StringIO()
        patches = contextlib.ExitStack()
        if gated:
            patches.enter_context(mock.patch.object(phrases, "WavStream", self.gated_stream()))
        with patches, contextlib.redirect_stderr(err):
            phrases.main(argv, environ={"VOXTYPE_GEMINI_VAD_MODEL": self.model})
        return err.getvalue()

    def gated_stream(self):
        """Holds the capture back until phrase 1 has been typed, so phrase 2's context is deterministic."""
        test = self

        class Gated(phrases.WavStream):
            released = False

            def read(self, n):
                if self._pos >= test.gate and not self.released:
                    for _ in range(WAIT * 100):
                        if len(test.typed()) >= 2:
                            break
                        threading.Event().wait(0.01)
                    self.released = True
                return super().read(n)

        return Gated

    def test_two_phrases_typed_in_order_with_context_and_clean_logs(self):
        replies = ["um first phrase.", "second phrase."]
        self.server.behave = lambda i, f: (200, {"text": replies[i]}, {})
        err = self.run_main(gated=True)

        self.assertEqual(self.typed(), ["--", "First phrase. ", "--", "second phrase. "])
        self.assertIn("Please speak\n", err)
        self.assertEqual(self.server.prompts(), [None, "um first phrase."])
        for text in replies:
            self.assertNotIn(text, err)
        self.assertNotIn("first", err)
        for req in self.server.requests:
            wav = silence.read_wav(req["file"][1])
            self.assertEqual((wav.rate, wav.channels), (16000, 1))

    def test_no_context_sends_no_prompt_field(self):
        err = self.run_main("--no-context")
        self.assertEqual(len(self.server.requests), 2)
        self.assertEqual(self.server.prompts(), [None, None])
        self.assertEqual(len(self.typed()), 4)
        self.assertIn("Please speak\n", err)

    def test_filler_only_reply_is_not_typed(self):
        self.server.behave = lambda i, f: (200, {"text": "hmm." if i == 0 else "real words"}, {})
        self.run_main("--no-context")
        self.assertEqual(self.typed(), ["--", "real words "])

    def test_pending_work_after_drain_returns_3_without_exiting(self):
        release = threading.Event()
        self.addCleanup(release.set)
        self.server.behave = lambda i, f: (release.wait(WAIT), (200, {"text": "late"}, {}))[1]
        close = phrases.PhrasePipeline.close
        with (
            mock.patch.object(phrases.os, "_exit") as hard_exit,
            mock.patch.object(
                phrases.PhrasePipeline, "close", lambda self, timeout=8.0: close(self, 0.05)
            ),
        ):
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                code = phrases.main(
                    ["--url", self.server.url, "--input-file", self.clip_path, "--wtype", self.wtype],
                    environ={"VOXTYPE_GEMINI_VAD_MODEL": self.model},
                )
        self.assertEqual(code, 3)
        hard_exit.assert_not_called()
        self.assertIn("still pending", err.getvalue())

    def test_adapter_down_without_local_model_types_nothing_and_exits_cleanly(self):
        self.server.close()
        err = self.run_main("--no-context")
        self.assertEqual(self.typed(), [])
        self.assertIn("Please speak\n", err)
        self.assertIn("failed", err)


if __name__ == "__main__":
    unittest.main()

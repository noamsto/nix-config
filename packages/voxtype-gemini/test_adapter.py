import base64
import contextlib
import io
import json
import os
import shutil
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import adapter
import numpy as np
import silence
import testclips

FAKE_KEY = "fake-key-do-not-leak-0123456789"
# CRLF, boundary-like and non-UTF-8 bytes must survive multipart parsing intact.
AUDIO = b"RIFF\r\n\x00\xff\xfe--boundary\r\n\r\n\x80\x81\r\n" * 3 + b"\r\n"


class FakeGemini:
    def __init__(self, status=200, text="hello shalom", delay=0.0, raw=None, location=None):
        self.raw = raw
        self.location = location
        self.status = status
        self.text = text
        self.delay = delay
        self.requests = []
        self.release = threading.Event()
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format, *args):
                pass

            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"]))
                outer.requests.append((self.path, {k.lower(): v for k, v in self.headers.items()}, json.loads(body)))
                if outer.delay:
                    outer.release.wait(outer.delay)
                payload = outer.raw if outer.raw is not None else json.dumps(
                    {
                        "steps": [
                            {"type": "thought", "content": [{"type": "text", "text": "ignored"}]},
                            {
                                "type": "model_output",
                                "content": [
                                    {"type": "text", "text": outer.text[:5]},
                                    {"type": "text", "text": outer.text[5:]},
                                ],
                            },
                        ]
                    }
                ).encode()
                self.send_response(outer.status)
                if outer.location:
                    self.send_header("Location", outer.location)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def close(self):
        self.release.set()
        self.server.shutdown()
        self.server.server_close()


def multipart(fields, boundary="XbOuNdArYx"):
    out = b""
    for name, filename, ctype, data in fields:
        disposition = f'form-data; name="{name}"' + (f'; filename="{filename}"' if filename else "")
        out += f"--{boundary}\r\nContent-Disposition: {disposition}\r\n".encode()
        if ctype:
            out += f"Content-Type: {ctype}\r\n".encode()
        out += b"\r\n" + data + b"\r\n"
    out += f"--{boundary}--\r\n".encode()
    return out, f"multipart/form-data; boundary={boundary}"


class AdapterTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.key_file = os.path.join(self.tmp.name, "key")
        with open(self.key_file, "w") as handle:
            handle.write(FAKE_KEY + "\n")
        self.stderr = io.StringIO()
        stack = contextlib.ExitStack()
        stack.enter_context(contextlib.redirect_stderr(self.stderr))
        self.addCleanup(stack.close)

    def start(self, fake, **overrides):
        settings = {
            "VOXTYPE_GEMINI_KEY_FILE": self.key_file,
            "VOXTYPE_GEMINI_PORT": "0",
            "VOXTYPE_GEMINI_BASE_URL": fake.url,
            "VOXTYPE_GEMINI_MODEL": "gemini-3.5-transcribe",
            "VOXTYPE_GEMINI_VOCABULARY": "NixOS\nHyprland, voxtype",
            "VOXTYPE_GEMINI_LANGUAGE_CODES": "he-IL,en-US",
            "VOXTYPE_GEMINI_TIMEOUT_SECS": "5",
            "VOXTYPE_GEMINI_SILENCE_TRIM": "0",
        }
        settings.update(overrides)
        server = adapter.make_server(adapter.config_from_environ(settings))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        self.addCleanup(fake.close)
        self.server = server
        return f"http://127.0.0.1:{server.server_address[1]}/v1/audio/transcriptions"

    def post(self, url, fields, headers=None):
        body, ctype = multipart(fields)
        request = urllib.request.Request(
            url, data=body, headers={"Content-Type": ctype, **(headers or {})}, method="POST"
        )
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                return response.status, response.read()
        except urllib.error.HTTPError as err:
            return err.code, err.read()

    def audio_fields(self):
        return [
            ("model", None, None, b"gemini-3.5-transcribe"),
            ("file", "clip.wav", "audio/wav", AUDIO),
        ]

    def test_success_and_request_shape(self):
        fake = FakeGemini()
        url = self.start(fake)
        status, body = self.post(url, self.audio_fields())
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body), {"text": "hello shalom"})
        ((path, headers, sent),) = fake.requests
        self.assertEqual(path, "/v1beta/interactions")
        self.assertEqual(headers["x-goog-api-key"], FAKE_KEY)
        self.assertEqual(sent["model"], "models/gemini-3.5-transcribe")
        self.assertIs(sent["store"], False)
        (part,) = sent["input"]
        self.assertEqual(part["type"], "audio")
        self.assertEqual(part["mime_type"], "audio/wav")
        self.assertEqual(base64.b64decode(part["data"]), AUDIO)
        self.assertEqual(
            sent["generation_config"]["transcription_config"],
            {"custom_vocabulary": ["NixOS", "Hyprland", "voxtype"], "language_codes": ["he-IL", "en-US"]},
        )

    def test_smart_transcription_sets_mode(self):
        fake = FakeGemini()
        url = self.start(fake, VOXTYPE_GEMINI_SMART="1")
        self.post(url, self.audio_fields())
        self.assertEqual(
            fake.requests[0][2]["generation_config"]["transcription_config"],
            {
                "custom_vocabulary": ["NixOS", "Hyprland", "voxtype"],
                "language_codes": ["he-IL", "en-US"],
                "mode": "smart",
            },
        )

    def test_request_never_asks_for_diarization_or_timestamps(self):
        for smart in ("0", "1"):
            fake = FakeGemini()
            url = self.start(fake, VOXTYPE_GEMINI_SMART=smart)
            self.post(url, self.audio_fields())
            body = fake.requests[0][2]
            self.assertNotIn("diarization_mode", json.dumps(body))
            self.assertNotIn("timestamp_granularities", json.dumps(body))
            self.assertLessEqual(len(body["generation_config"]["transcription_config"]["custom_vocabulary"]), 100)

    def test_smart_flag_defaults_off(self):
        self.assertFalse(
            adapter.config_from_environ({"VOXTYPE_GEMINI_KEY_FILE": self.key_file, "VOXTYPE_GEMINI_SILENCE_TRIM": "0"}).smart
        )

    def test_smart_mode_keeps_prompt_vocabulary(self):
        fake = FakeGemini()
        url = self.start(fake, VOXTYPE_GEMINI_SMART="1")
        status, _ = self.post(url, self.audio_fields() + [("prompt", None, None, b"deploy Kubernetes")])
        self.assertEqual(status, 200)
        self.assertEqual(
            fake.requests[0][2]["generation_config"]["transcription_config"],
            {
                "custom_vocabulary": ["NixOS", "Hyprland", "voxtype", "deploy", "Kubernetes"],
                "language_codes": ["he-IL", "en-US"],
                "mode": "smart",
            },
        )

    def test_vocabulary_limit(self):
        def config(count):
            return adapter.config_from_environ(
                {
                    "VOXTYPE_GEMINI_KEY_FILE": self.key_file,
                    "VOXTYPE_GEMINI_VOCABULARY": ",".join(f"term{i}" for i in range(count)),
                    "VOXTYPE_GEMINI_SILENCE_TRIM": "0",
                }
            )

        config(100)
        with self.assertRaises(ValueError):
            config(101)

    def test_upstream_error_is_502_quickly(self):
        fake = FakeGemini(status=500)
        url = self.start(fake)
        started = time.monotonic()
        status, body = self.post(url, self.audio_fields())
        self.assertEqual(status, 502)
        self.assertIn("error", json.loads(body))
        self.assertLess(time.monotonic() - started, 2)

    def test_upstream_timeout_is_504(self):
        fake = FakeGemini(delay=5)
        url = self.start(fake, VOXTYPE_GEMINI_TIMEOUT_SECS="0.3")
        started = time.monotonic()
        status, _ = self.post(url, self.audio_fields())
        elapsed = time.monotonic() - started
        self.assertEqual(status, 504)
        self.assertGreaterEqual(elapsed, 0.25)
        self.assertLess(elapsed, 2)

    def test_key_never_in_logs_or_response(self):
        for status in (200, 500):
            fake = FakeGemini(status=status)
            url = self.start(fake)
            _, body = self.post(url, self.audio_fields())
            self.assertNotIn(FAKE_KEY.encode(), body)
        self.assertTrue(self.stderr.getvalue())
        self.assertNotIn(FAKE_KEY, self.stderr.getvalue())

    def test_origin_header_is_forbidden(self):
        fake = FakeGemini()
        url = self.start(fake)
        status, body = self.post(url, self.audio_fields(), {"Origin": "https://evil.example"})
        self.assertEqual(status, 403)
        self.assertEqual(json.loads(body), {"error": "forbidden"})
        self.assertEqual(fake.requests, [])

    def test_foreign_host_is_forbidden(self):
        fake = FakeGemini()
        url = self.start(fake)
        status, _ = self.post(url, self.audio_fields(), {"Host": "rebind.example:80"})
        self.assertEqual(status, 403)
        self.assertEqual(fake.requests, [])

    def test_localhost_host_is_allowed(self):
        fake = FakeGemini()
        url = self.start(fake)
        port = self.server.server_address[1]
        status, _ = self.post(url, self.audio_fields(), {"Host": f"localhost:{port}"})
        self.assertEqual(status, 200)

    def test_redirect_is_not_followed(self):
        target = FakeGemini()
        self.addCleanup(target.close)
        fake = FakeGemini(status=302, location=f"{target.url}/v1beta/interactions")
        url = self.start(fake)
        status, _ = self.post(url, self.audio_fields())
        self.assertEqual(status, 502)
        self.assertEqual(target.requests, [])

    def test_response_without_model_output_is_502(self):
        for raw in (b'{"steps": []}', b"[]", b'{"steps": [{"type": "thought"}]}'):
            fake = FakeGemini(raw=raw)
            url = self.start(fake)
            status, body = self.post(url, self.audio_fields())
            self.assertEqual(status, 502)
            self.assertEqual(json.loads(body), {"error": "upstream returned no transcript"})

    def test_binds_loopback_only(self):
        self.start(FakeGemini())
        self.assertEqual(self.server.server_address[0], "127.0.0.1")

    def test_missing_file_field_is_400(self):
        fake = FakeGemini()
        url = self.start(fake)
        status, body = self.post(url, [("model", None, None, b"x")])
        self.assertEqual(status, 400)
        self.assertIn("file", json.loads(body)["error"])
        self.assertEqual(fake.requests, [])

    def test_missing_key_file_is_fatal(self):
        with self.assertRaises(SystemExit):
            adapter.config_from_environ({"VOXTYPE_GEMINI_KEY_FILE": os.path.join(self.tmp.name, "nope")})

    def test_multipart_preserves_binary_crlf(self):
        body, ctype = multipart([("file", "c.wav", "audio/wav", AUDIO)])
        self.assertEqual(adapter.parse_multipart(ctype, body)["file"][1], AUDIO)

    @classmethod
    def setUpClass(cls):
        cls.model = os.environ["VOXTYPE_GEMINI_VAD_MODEL"]
        cls.speech_dir = tempfile.mkdtemp()
        cls.en = testclips.speak(
            cls.speech_dir, "en-us", "please open a new account for me today", "en.wav"
        )
        cls.en2 = testclips.speak(
            cls.speech_dir, "en-us", "and then close the old savings account", "en2.wav"
        )

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.speech_dir)

    def trimmed(self, fake, **overrides):
        return self.start(
            fake,
            VOXTYPE_GEMINI_SILENCE_TRIM="1",
            VOXTYPE_GEMINI_VAD_MODEL=self.model,
            **overrides,
        )

    def clip(self, lead=1.0, gap=2.5, tail=1.5):
        (a, rate), (b, _) = self.en, self.en2
        signal = testclips.clip(
            rate, [("s", lead), ("a", a), ("s", gap), ("a", b), ("s", tail)]
        )
        return testclips.to_wav_bytes(signal, rate)

    def wav_fields(self, data, *extra):
        return [("model", None, None, b"x"), ("file", "clip.wav", "audio/wav", data), *extra]

    def sent_wav(self, request):
        _, _, body = request
        (part,) = body["input"]
        self.assertEqual(part["mime_type"], "audio/wav")
        return silence.read_wav(base64.b64decode(part["data"]))

    def test_silent_clips_never_reach_upstream(self):
        rng = np.random.default_rng(1)
        for signal in (
            np.zeros(testclips.RATE * 2, dtype=np.float32),
            rng.normal(0, 0.005, testclips.RATE * 3).astype(np.float32),
        ):
            fake = FakeGemini()
            url = self.trimmed(fake)
            data = testclips.to_wav_bytes(signal, testclips.RATE)
            status, body = self.post(url, self.wav_fields(data))
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(body), {"text": ""})
            self.assertEqual(fake.requests, [])
        self.assertIn("(no speech)", self.stderr.getvalue())

    def test_silence_is_collapsed_before_upstream(self):
        data = self.clip()
        expected = silence.trim(data, self.model, 300, 200, 0.5)
        fake = FakeGemini()
        url = self.trimmed(fake)
        status, body = self.post(url, self.wav_fields(data))
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body), {"text": "hello shalom"})
        (request,) = fake.requests
        sent = self.sent_wav(request)
        self.assertLess(sent.seconds, expected.seconds_in)
        self.assertAlmostEqual(sent.seconds, expected.seconds_sent, delta=0.05)
        spans = silence.speech_spans(silence.read_wav(data), self.model)
        speech = sum(e - s for s, e in spans) / sent.rate
        self.assertAlmostEqual(sent.seconds, speech + 0.3 + 0.4, delta=0.1)

    def test_log_reports_seconds_but_no_content(self):
        data = self.clip()
        expected = silence.trim(data, self.model, 300, 200, 0.5)
        fake = FakeGemini(text="secret transcript words")
        url = self.trimmed(fake)
        prompt = "confidential earlier sentence"
        status, _ = self.post(url, self.wav_fields(data, ("prompt", None, None, prompt.encode())))
        self.assertEqual(status, 200)
        logged = self.stderr.getvalue()
        self.assertIn(
            f"voxtype-gemini: audio in={expected.seconds_in:.2f}s sent={expected.seconds_sent:.2f}s\n",
            logged,
        )
        for secret in ("secret transcript words", "confidential", "earlier sentence", FAKE_KEY):
            self.assertNotIn(secret, logged)

    def test_unparseable_upload_passes_through_untouched(self):
        fake = FakeGemini()
        url = self.trimmed(fake)
        status, _ = self.post(url, self.audio_fields())
        self.assertEqual(status, 200)
        ((_, _, body),) = fake.requests
        (part,) = body["input"]
        self.assertEqual(base64.b64decode(part["data"]), AUDIO)
        self.assertEqual(part["mime_type"], "audio/wav")
        self.assertIn("voxtype-gemini: audio unprocessed\n", self.stderr.getvalue())

    def test_wav_cut_mid_sample_is_trimmed_not_dropped(self):
        data = self.clip()[:-1]
        fake = FakeGemini()
        url = self.trimmed(fake)
        status, body = self.post(url, self.wav_fields(data))
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(body), {"text": "hello shalom"})
        (request,) = fake.requests
        self.assertLess(self.sent_wav(request).seconds, silence.read_wav(data).seconds)

    def test_wav_with_absurd_framerate_passes_through(self):
        data = bytearray(self.clip())
        data[24:28] = (8).to_bytes(4, "little")
        fake = FakeGemini()
        url = self.trimmed(fake)
        status, _ = self.post(url, self.wav_fields(bytes(data)))
        self.assertEqual(status, 200)
        ((_, _, body),) = fake.requests
        self.assertEqual(base64.b64decode(body["input"][0]["data"]), bytes(data))
        self.assertIn("voxtype-gemini: audio unprocessed\n", self.stderr.getvalue())

    def test_nested_multipart_prompt_part_is_ignored(self):
        fake = FakeGemini()
        url = self.start(fake)
        inner = b"--in\r\nContent-Disposition: form-data; name=\"x\"\r\n\r\nv\r\n--in--\r\n"
        body, ctype = multipart(self.audio_fields())
        body = body.replace(
            b"--XbOuNdArYx--\r\n",
            b'--XbOuNdArYx\r\nContent-Disposition: form-data; name="prompt"\r\n'
            b"Content-Type: multipart/mixed; boundary=in\r\n\r\n" + inner + b"\r\n--XbOuNdArYx--\r\n",
        )
        request = urllib.request.Request(url, data=body, headers={"Content-Type": ctype}, method="POST")
        with urllib.request.urlopen(request, timeout=10) as response:
            self.assertEqual(response.status, 200)
        ((_, _, sent),) = fake.requests
        self.assertEqual(sent["generation_config"]["transcription_config"].get("custom_vocabulary"), ["NixOS", "Hyprland", "voxtype"])

    def test_trim_disabled_passes_wav_byte_identical(self):
        data = self.clip()
        fake = FakeGemini()
        url = self.start(fake)
        status, _ = self.post(url, self.wav_fields(data))
        self.assertEqual(status, 200)
        ((_, _, body),) = fake.requests
        self.assertEqual(base64.b64decode(body["input"][0]["data"]), data)
        self.assertIn("voxtype-gemini: audio unprocessed\n", self.stderr.getvalue())

    def test_prompt_rare_words_extend_vocabulary(self):
        fake = FakeGemini()
        url = self.start(fake)
        prompt = "deploy Kubernetes with nixos and Zebrafish"
        status, _ = self.post(url, self.audio_fields() + [("prompt", None, None, prompt.encode())])
        self.assertEqual(status, 200)
        ((_, _, body),) = fake.requests
        config = body["generation_config"]["transcription_config"]
        self.assertEqual(
            config["custom_vocabulary"],
            ["NixOS", "Hyprland", "voxtype", "deploy", "Kubernetes", "Zebrafish"],
        )
        self.assertEqual(config["language_codes"], ["he-IL", "en-US"])
        self.assertNotIn(prompt, json.dumps(body))
        self.assertEqual(set(body), {"model", "input", "store", "generation_config"})
        self.assertEqual(len(body["input"]), 1)
        self.assertNotIn("Zebrafish", self.stderr.getvalue())

    def test_prompt_vocabulary_total_is_capped_and_configured_terms_win(self):
        configured = [f"term{i:02d}x" for i in range(95)]
        fake = FakeGemini()
        url = self.start(fake, VOXTYPE_GEMINI_VOCABULARY="\n".join(configured))
        rare = [f"rare{chr(97 + i)}word" for i in range(12)]
        status, _ = self.post(url, self.audio_fields() + [("prompt", None, None, " ".join(rare).encode())])
        self.assertEqual(status, 200)
        ((_, _, body),) = fake.requests
        vocabulary = body["generation_config"]["transcription_config"]["custom_vocabulary"]
        self.assertEqual(vocabulary, configured + rare[-5:])

    def test_empty_or_absent_prompt_changes_nothing(self):
        for extra in ([], [("prompt", None, None, b"")]):
            fake = FakeGemini()
            url = self.start(fake)
            status, _ = self.post(url, self.audio_fields() + extra)
            self.assertEqual(status, 200)
            ((_, _, body),) = fake.requests
            self.assertEqual(
                body["generation_config"]["transcription_config"]["custom_vocabulary"],
                ["NixOS", "Hyprland", "voxtype"],
            )

    def test_no_vocabulary_and_no_prompt_omits_custom_vocabulary(self):
        fake = FakeGemini()
        url = self.start(fake, VOXTYPE_GEMINI_VOCABULARY="")
        status, _ = self.post(url, self.audio_fields())
        self.assertEqual(status, 200)
        ((_, _, body),) = fake.requests
        self.assertNotIn("custom_vocabulary", body["generation_config"]["transcription_config"])

    def test_concurrent_trimmed_requests_are_independent(self):
        clips = [self.clip(lead=1.0, gap=2.5, tail=1.5), self.clip(lead=0.0, gap=4.0, tail=0.0)]
        expected = [silence.trim(c, self.model, 300, 200, 0.5).seconds_sent for c in clips]
        self.assertGreater(abs(expected[0] - expected[1]), 0.05)
        fake = FakeGemini(delay=0.4)
        url = self.trimmed(fake)
        results = [None, None]

        def run(i):
            results[i] = self.post(url, self.wav_fields(clips[i]))

        threads = [threading.Thread(target=run, args=(i,)) for i in range(2)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(15)
        for status, body in results:
            self.assertEqual(status, 200)
            self.assertEqual(json.loads(body), {"text": "hello shalom"})
        sent = sorted(self.sent_wav(r).seconds for r in fake.requests)
        self.assertEqual(len(sent), 2)
        for got, want in zip(sent, sorted(expected)):
            self.assertAlmostEqual(got, want, delta=0.05)


class ContextTermsTest(unittest.TestCase):
    def test_rare_words_in_order_stopwords_dropped(self):
        prompt = "Please deploy Kubernetes with the new Zebrafish cluster"
        self.assertEqual(
            adapter.context_terms(prompt, []),
            ["Please", "deploy", "Kubernetes", "Zebrafish", "cluster"],
        )

    def test_hebrew_and_english_mix(self):
        prompt = "אני רוצה לפתוח בקשת משיכה עבור Kubernetes"
        self.assertEqual(
            adapter.context_terms(prompt, []),
            ["רוצה", "לפתוח", "בקשת", "משיכה", "Kubernetes"],
        )

    def test_short_words_and_stopwords_dropped(self):
        self.assertEqual(adapter.context_terms("go to the zoo that this with", []), [])

    def test_dedupe_case_insensitive_against_vocabulary_and_self(self):
        self.assertEqual(
            adapter.context_terms(
                "nixos HYPRLAND deploy Deploy DEPLOY voxtype tmux", ["NixOS", "Hyprland", "voxtype"]
            ),
            ["deploy", "tmux"],
        )

    def test_limit_keeps_last_distinct(self):
        words = [f"word{i}" for i in range(20)]
        self.assertEqual(adapter.context_terms(" ".join(words), [], limit=12), words[8:])

    def test_only_tail_of_long_prompt_is_used(self):
        prompt = "ancient " + "a " * 1100 + "recent"
        self.assertEqual(adapter.context_terms(prompt, []), ["recent"])

    def test_apostrophe_and_hyphen_stay_inside_token(self):
        self.assertEqual(
            adapter.context_terms("state-of-the-art isn't", []), ["state-of-the-art", "isn't"]
        )


class TrimConfigTest(unittest.TestCase):
    def test_default_is_on(self):
        self.assertEqual(
            adapter.trim_config_from_environ({"VOXTYPE_GEMINI_VAD_MODEL": "/m.onnx"}),
            adapter.TrimConfig("/m.onnx", 300, 200, 0.5),
        )

    def test_values_parsed(self):
        settings = {
            "VOXTYPE_GEMINI_VAD_MODEL": "/m.onnx",
            "VOXTYPE_GEMINI_SILENCE_MAX_MS": "150",
            "VOXTYPE_GEMINI_SILENCE_PAD_MS": "50",
            "VOXTYPE_GEMINI_VAD_THRESHOLD": "0.7",
        }
        self.assertEqual(
            adapter.trim_config_from_environ(settings), adapter.TrimConfig("/m.onnx", 150, 50, 0.7)
        )

    def test_disabled_values_give_none_without_model(self):
        for value in ("0", "false", ""):
            self.assertIsNone(adapter.trim_config_from_environ({"VOXTYPE_GEMINI_SILENCE_TRIM": value}))

    def test_missing_model_is_fatal(self):
        with self.assertRaises(SystemExit) as raised:
            adapter.trim_config_from_environ({})
        self.assertEqual(str(raised.exception), "VOXTYPE_GEMINI_VAD_MODEL is not set")


if __name__ == "__main__":
    unittest.main()

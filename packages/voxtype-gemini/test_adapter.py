import base64
import contextlib
import io
import json
import os
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import adapter

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
        self.assertFalse(adapter.config_from_environ({"VOXTYPE_GEMINI_KEY_FILE": self.key_file}).smart)

    def test_vocabulary_limit(self):
        def config(count):
            return adapter.config_from_environ(
                {
                    "VOXTYPE_GEMINI_KEY_FILE": self.key_file,
                    "VOXTYPE_GEMINI_VOCABULARY": ",".join(f"term{i}" for i in range(count)),
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


if __name__ == "__main__":
    unittest.main()

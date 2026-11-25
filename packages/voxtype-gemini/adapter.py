"""OpenAI-compatible /v1/audio/transcriptions shim in front of Gemini Transcribe.

voxtype's remote backend speaks the OpenAI transcription API; Gemini Transcribe
is only reachable through the Interactions API, so this translates between them.
"""

import base64
import json
import os
import socket
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from email import policy
from email.parser import BytesParser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFAULT_BASE_URL = "https://generativelanguage.googleapis.com"
DEFAULT_MODEL = "gemini-3.5-transcribe"
MAX_BODY_BYTES = 16 * 1024 * 1024


@dataclass
class Config:
    api_key: str
    port: int = 8923
    model: str = DEFAULT_MODEL
    vocabulary: list[str] = field(default_factory=list)
    language_codes: list[str] = field(default_factory=list)
    timeout_secs: float = 20.0
    base_url: str = DEFAULT_BASE_URL


class UpstreamError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


def audio_part(audio, mime_type):
    return {
        "type": "audio",
        "data": base64.b64encode(audio).decode("ascii"),
        "mime_type": mime_type,
    }


def build_interaction(base_url, model, input_parts, generation_config=None):
    url = f"{base_url.rstrip('/')}/v1beta/interactions"
    body = {"model": f"models/{model}", "input": input_parts, "store": False}
    if generation_config:
        body["generation_config"] = generation_config
    return url, body


def extract_text(response):
    """Return the transcript, or None when the response has no model_output step."""
    if not isinstance(response, dict):
        return None
    texts = []
    found = False
    for step in response.get("steps", []):
        if step.get("type") != "model_output":
            continue
        found = True
        for content in step.get("content", []):
            if content.get("type") == "text":
                texts.append(content.get("text", ""))
    return "".join(texts).strip() if found else None


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Never follow a redirect: it would carry the API key header along."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


OPENER = urllib.request.build_opener(NoRedirect)


def call_gemini(base_url, api_key, timeout_secs, model, input_parts, generation_config=None):
    """Return the transcript text; raise UpstreamError(502|504) on failure."""
    url, body = build_interaction(base_url, model, input_parts, generation_config)
    request = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
        method="POST",
    )
    try:
        with OPENER.open(request, timeout=timeout_secs) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as err:
        raise UpstreamError(502, f"upstream returned HTTP {err.code}") from None
    except TimeoutError:
        raise UpstreamError(504, "upstream timed out") from None
    except urllib.error.URLError as err:
        if isinstance(err.reason, (TimeoutError, socket.timeout)):
            raise UpstreamError(504, "upstream timed out") from None
        raise UpstreamError(502, "upstream unreachable") from None
    except (OSError, ValueError):
        raise UpstreamError(502, "upstream sent an unreadable response") from None
    text = extract_text(payload)
    if text is None:
        raise UpstreamError(502, "upstream returned no transcript")
    return text


def transcribe(config, audio, mime_type):
    transcription = {}
    if config.vocabulary:
        transcription["custom_vocabulary"] = config.vocabulary
    if config.language_codes:
        transcription["language_codes"] = config.language_codes
    return call_gemini(
        config.base_url,
        config.api_key,
        config.timeout_secs,
        config.model,
        [audio_part(audio, mime_type)],
        {"transcription_config": transcription},
    )


def parse_multipart(content_type, body):
    """Return {field name: (content type, bytes)} for a multipart/form-data body."""
    message = BytesParser(policy=policy.HTTP).parsebytes(
        b"Content-Type: " + content_type.encode() + b"\r\nMIME-Version: 1.0\r\n\r\n" + body
    )
    if not message.is_multipart():
        raise ValueError("not multipart")
    parts = {}
    for part in message.iter_parts():
        name = part.get_param("name", header="content-disposition")
        if name:
            parts[name] = (part.get_content_type(), part.get_payload(decode=True))
    return parts


def make_handler(config):
    class Handler(BaseHTTPRequestHandler):
        # Bounds a stalled client (slowloris) on both header and body reads.
        timeout = 30

        def log_message(self, format, *args):
            # Method, path and status only: no headers, no bodies.
            status = args[1] if len(args) > 1 else "?"
            sys.stderr.write(f"voxtype-gemini: {self.command} {self.path.split('?')[0]} -> {status}\n")

        def reply(self, status, payload):
            data = json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def local_request(self):
            # A browser page can POST to loopback (CSRF) or reach it via a
            # rebound DNS name; real clients send neither Origin nor a foreign Host.
            port = self.server.server_address[1]
            return "Origin" not in self.headers and self.headers.get("Host") in (
                f"127.0.0.1:{port}",
                f"localhost:{port}",
            )

        def do_POST(self):
            if not self.local_request():
                return self.reply(403, {"error": "forbidden"})
            if self.path.split("?")[0] != "/v1/audio/transcriptions":
                return self.reply(404, {"error": "not found"})
            try:
                length = int(self.headers.get("Content-Length", ""))
            except ValueError:
                return self.reply(400, {"error": "Content-Length required"})
            if not 0 < length <= MAX_BODY_BYTES:
                return self.reply(400, {"error": "invalid body size"})
            body = self.rfile.read(length)
            try:
                parts = parse_multipart(self.headers.get("Content-Type", ""), body)
            except ValueError:
                return self.reply(400, {"error": "malformed multipart body"})
            if "file" not in parts or not parts["file"][1]:
                return self.reply(400, {"error": "missing file field"})
            mime_type, audio = parts["file"]
            if not mime_type.startswith("audio/"):
                mime_type = "audio/wav"
            try:
                text = transcribe(config, audio, mime_type)
            except UpstreamError as err:
                return self.reply(err.status, {"error": str(err)})
            self.reply(200, {"text": text})

    return Handler


def make_server(config):
    return ThreadingHTTPServer(("127.0.0.1", config.port), make_handler(config))


def split_list(value):
    return [item.strip() for item in value.replace(",", "\n").splitlines() if item.strip()]


def config_from_environ(environ):
    key_file = environ.get("VOXTYPE_GEMINI_KEY_FILE")
    if not key_file:
        raise SystemExit("VOXTYPE_GEMINI_KEY_FILE is not set")
    try:
        with open(key_file) as handle:
            api_key = handle.read().strip()
    except OSError as err:
        raise SystemExit(f"cannot read key file: {err.strerror}") from None
    if not api_key:
        raise SystemExit("key file is empty")
    return Config(
        api_key=api_key,
        port=int(environ.get("VOXTYPE_GEMINI_PORT", "8923")),
        model=environ.get("VOXTYPE_GEMINI_MODEL", DEFAULT_MODEL),
        vocabulary=split_list(environ.get("VOXTYPE_GEMINI_VOCABULARY", "")),
        language_codes=split_list(environ.get("VOXTYPE_GEMINI_LANGUAGE_CODES", "")),
        timeout_secs=float(environ.get("VOXTYPE_GEMINI_TIMEOUT_SECS", "20")),
        base_url=environ.get("VOXTYPE_GEMINI_BASE_URL", DEFAULT_BASE_URL),
    )


def main():
    server = make_server(config_from_environ(os.environ))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()

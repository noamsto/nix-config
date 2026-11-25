"""Phrase-mode dictation core: streaming VAD, phrase merging, ordered concurrent transcription."""

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import unicodedata
import urllib.error
import urllib.request
import uuid
from concurrent import futures
from dataclasses import dataclass

import numpy as np
import sherpa_onnx
import silence

VAD_RATE = 16000
VAD_WINDOW = 512
EXIT_PENDING = 3  # phrases were still transcribing after the drain timeout and are dropped


def log(msg):
    print(f"voxtype-gemini-phrases: {msg}", file=sys.stderr, flush=True)


@dataclass(frozen=True, eq=False)
class Segment:
    start: float  # seconds on the stream clock
    samples: np.ndarray  # float32 mono at VAD_RATE

    @property
    def seconds(self):
        return len(self.samples) / VAD_RATE

    @property
    def end(self):
        return self.start + self.seconds


class StreamingVad:
    """Silero VAD over a live stream; cuts only at pauses of at least pause_s."""

    def __init__(self, model_path, pause_s=0.9, threshold=0.5, max_speech_s=25.0):
        config = sherpa_onnx.VadModelConfig()
        config.silero_vad.model = model_path
        config.silero_vad.threshold = threshold
        config.silero_vad.min_silence_duration = pause_s
        config.silero_vad.max_speech_duration = max_speech_s
        config.silero_vad.window_size = VAD_WINDOW
        config.sample_rate = VAD_RATE
        self._detector = sherpa_onnx.VoiceActivityDetector(config, 60)
        self._pending = np.zeros(0, dtype=np.float32)

    @property
    def speaking(self):
        return self._detector.is_speech_detected()

    def accept(self, samples):
        buf = np.concatenate([self._pending, samples])
        usable = len(buf) - len(buf) % VAD_WINDOW
        for i in range(0, usable, VAD_WINDOW):
            self._detector.accept_waveform(buf[i : i + VAD_WINDOW])
        self._pending = buf[usable:]
        return self._drain()

    def flush(self):
        if len(self._pending):
            self._detector.accept_waveform(
                np.pad(self._pending, (0, VAD_WINDOW - len(self._pending)))
            )
            self._pending = np.zeros(0, dtype=np.float32)
        self._detector.flush()
        return self._drain()

    def _drain(self):
        out = []
        while not self._detector.empty():
            seg = self._detector.front
            out.append(Segment(seg.start / VAD_RATE, np.asarray(seg.samples, dtype=np.float32)))
            self._detector.pop()
        return out


class Merger:
    """Holds segments shorter than min_s and prepends them to the next one."""

    def __init__(self, min_s=1.5, hold_s=3.0, max_gap_s=0.5):
        self.min_s = min_s
        self.hold_s = hold_s
        self.max_gap_s = max_gap_s
        self._held = None

    def feed(self, seg):
        if self._held is not None:
            held, self._held = self._held, None
            gap = max(0.0, seg.start - held.end)
            silence = np.zeros(round(min(gap, self.max_gap_s) * VAD_RATE), dtype=np.float32)
            seg = Segment(held.start, np.concatenate([held.samples, silence, seg.samples]))
        if seg.seconds < self.min_s:
            self._held = seg
            return []
        return [seg]

    def tick(self, now_s):
        if self._held is None or now_s - self._held.end < self.hold_s:
            return []
        return self.flush()

    def flush(self):
        held, self._held = self._held, None
        return [] if held is None else [held]


class OrderedEmitter:
    """Emits results in sequence order, whatever order they complete in."""

    def __init__(self, emit):
        self._emit = emit
        self._lock = threading.Lock()
        # separate from _lock so reserve() never waits behind a slow emit
        self._emit_lock = threading.Lock()
        self._next_seq = 0
        self._expected = 0
        self._results = {}

    def reserve(self):
        with self._lock:
            seq = self._next_seq
            self._next_seq += 1
            return seq

    def complete(self, seq, text):
        with self._lock:
            self._results[seq] = text
        with self._emit_lock:
            while True:
                with self._lock:
                    if self._expected not in self._results:
                        return
                    text = self._results.pop(self._expected)
                    self._expected += 1
                if not text:
                    continue
                try:
                    self._emit(text)
                # an escaped exception would stop the drain and strand every later phrase
                except Exception as exc:  # noqa: BLE001
                    log(f"emit failed: {type(exc).__name__}")


class PhrasePipeline:
    """Transcribes segments concurrently and emits their text in spoken order."""

    def __init__(self, transcribe, emit, workers=4, context=True):
        self._transcribe = transcribe
        self._emitter = OrderedEmitter(emit)
        self._context = context
        self._executor = futures.ThreadPoolExecutor(max_workers=workers)
        self._lock = threading.Lock()
        self._finished = {}  # seq -> non-empty transcript
        self._futures = set()

    def submit(self, segment):
        samples = segment.samples if isinstance(segment, Segment) else segment
        seq = self._emitter.reserve()
        future = self._executor.submit(self._work, seq, samples)
        with self._lock:
            self._futures.add(future)
        future.add_done_callback(self._forget)
        return seq

    def _forget(self, future):
        with self._lock:
            self._futures.discard(future)

    def _prompt(self, seq):
        """Context rule: never wait; use the highest earlier seq that already finished."""
        if not self._context:
            return None
        with self._lock:
            earlier = [s for s in self._finished if s < seq]
            return self._finished[max(earlier)] if earlier else None

    def _work(self, seq, samples):
        text = None
        try:
            text = self._transcribe(samples, self._prompt(seq))
        # a seq that never completes would stall every later phrase in the emitter
        except Exception as exc:  # noqa: BLE001
            log(f"phrase {seq} ({len(samples) / VAD_RATE:.2f}s) failed: {type(exc).__name__}")
        if text:
            with self._lock:
                self._finished[seq] = text
        self._emitter.complete(seq, text)

    @property
    def pending(self):
        with self._lock:
            return any(not f.done() for f in self._futures)

    def close(self, timeout=8.0):
        with self._lock:
            pending = list(self._futures)
        _, not_done = futures.wait(pending, timeout)
        self._executor.shutdown(wait=False, cancel_futures=True)
        if not_done:
            log(f"{len(not_done)} phrase(s) still pending after {timeout:.1f}s")
        return not not_done


def run(stream, vad, merger, pipeline, chunk_samples=512, stop=None):
    """Capture loop: never waits on transcription. Returns the number of segments submitted."""
    submitted = 0

    def submit(segments):
        nonlocal submitted
        for seg in segments:
            pipeline.submit(seg)
            submitted += 1

    consumed = 0
    carry = b""
    while True:
        data = stream.read(chunk_samples * 2)
        if data:
            data = carry + data
            usable = len(data) - len(data) % 2
            carry = data[usable:]
            samples = np.frombuffer(data[:usable], dtype="<i2").astype(np.float32) / 32768.0
            consumed += len(samples)
            for seg in vad.accept(samples):
                submit(merger.feed(seg))
            # the hold timer counts silence only: a held word must not be released mid-sentence
            if not vad.speaking:
                submit(merger.tick(consumed / VAD_RATE))
        if not data or (stop is not None and stop.is_set()):
            break
    for seg in vad.flush():
        submit(merger.feed(seg))
    submit(merger.flush())
    pipeline.close()
    return submitted


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


# An empty ProxyHandler keeps loopback traffic off any proxy in the environment.
_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirect)


def _multipart(fields):
    """fields: list of (name, filename or None, content type or None, bytes)."""
    boundary = uuid.uuid4().hex
    body = bytearray()
    for name, filename, ctype, data in fields:
        disposition = f'form-data; name="{name}"'
        if filename:
            disposition += f'; filename="{filename}"'
        body += f"--{boundary}\r\nContent-Disposition: {disposition}\r\n".encode()
        if ctype:
            body += f"Content-Type: {ctype}\r\n".encode()
        body += b"\r\n" + data + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    return f"multipart/form-data; boundary={boundary}", bytes(body)


def adapter_transcribe(url, samples, prompt, timeout=30.0):
    pcm = (np.clip(samples, -1.0, 1.0) * 32767).astype("<i2")
    wav = silence.write_wav(silence.Wav(VAD_RATE, 1, pcm.tobytes(), len(pcm)))
    fields = [("file", "audio.wav", "audio/wav", wav)]
    if prompt:
        fields.append(("prompt", None, None, prompt.encode()))
    content_type, body = _multipart(fields)
    request = urllib.request.Request(
        f"{url}/v1/audio/transcriptions",
        data=body,
        headers={"Content-Type": content_type},
        method="POST",
    )
    try:
        response = _OPENER.open(request, timeout=timeout)
    except urllib.error.HTTPError as err:
        err.close()
        raise
    with response:
        payload = json.load(response)
    text = payload.get("text") if isinstance(payload, dict) else None
    if not isinstance(text, str):
        raise ValueError("adapter reply has no text")  # noqa: TRY004
    return text


class LocalRecognizer:
    """Offline Parakeet via sherpa-onnx, loaded on first use."""

    def __init__(self, model_dir):
        self._dir = model_dir
        self._lock = threading.Lock()
        self._recognizer = None

    def __call__(self, samples, prompt=None):
        with self._lock:
            if self._recognizer is None:
                d = self._dir
                self._recognizer = sherpa_onnx.OfflineRecognizer.from_transducer(
                    encoder=f"{d}/encoder.int8.onnx",
                    decoder=f"{d}/decoder.int8.onnx",
                    joiner=f"{d}/joiner.int8.onnx",
                    tokens=f"{d}/tokens.txt",
                    num_threads=4,
                    model_type="nemo_transducer",
                )
            stream = self._recognizer.create_stream()
            stream.accept_waveform(VAD_RATE, samples)
            self._recognizer.decode_stream(stream)
            return stream.result.text.strip()


class FallbackTranscriber:
    """Gemini adapter first; the local model for any phrase the adapter fails."""

    def __init__(self, url, local, notify, timeout=30.0):
        self._url = url
        self._local = local
        self._notify = notify
        self._timeout = timeout
        self._lock = threading.Lock()
        self._down = False

    def __call__(self, samples, prompt):
        seconds = len(samples) / VAD_RATE
        try:
            text = adapter_transcribe(self._url, samples, prompt, self._timeout)
        except Exception as exc:
            if self._local is None:
                raise
            with self._lock:
                first_failure, self._down = not self._down, True
            if first_failure:
                self._notify("Gemini unreachable, using local model")
            log(f"phrase {seconds:.2f}s fallback ({type(exc).__name__})")
            return self._local(samples, prompt)
        with self._lock:
            self._down = False
        log(f"phrase {seconds:.2f}s ok")
        return text


DEFAULT_FILLERS = "uh|um|er|ah|eh|hmm|hm|mm|mhm"


def clean_text(text, fillers):
    """Same filler filtering as the sed stage of sherpa-dictate.sh.

    wtype types a newline as Return and a tab as Tab, so the result is one line
    with no control characters.
    """
    flags = re.IGNORECASE
    # lone surrogates (a truncated emoji in JSON) cannot be encoded into argv
    text = "".join(
        c for c in text if c.isspace() or unicodedata.category(c) not in ("Cc", "Cs")
    )
    text = re.sub(
        rf"^(?:{fillers})\b[,.]?\s*([a-z])",
        lambda m: m.group(1).upper(),
        text.lstrip(),
        flags=flags,
    )
    text = re.sub(rf"\b(?:{fillers})\b,?", "", text, flags=flags)
    text = re.sub(r"[\s,]+([.?!])", r"\1", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text if any(c.isalnum() for c in text) else ""


def parse_args(argv, environ):
    p = argparse.ArgumentParser(
        prog="voxtype-gemini-phrases",
        description="Phrase-by-phrase dictation through the voxtype Gemini adapter.",
    )
    p.add_argument("--url", required=True, help="adapter base URL, e.g. http://127.0.0.1:8123")
    p.add_argument(
        "--pause", type=float, default=float(environ.get("VOXTYPE_GEMINI_PHRASE_PAUSE_SECS", 0.9))
    )
    p.add_argument(
        "--min-phrase",
        type=float,
        default=float(environ.get("VOXTYPE_GEMINI_PHRASE_MIN_SECS", 1.5)),
    )
    p.add_argument("--hold", type=float, default=3.0)
    p.add_argument("--no-context", action="store_true")
    p.add_argument("--device", default="plug:default")
    p.add_argument("--vad-model", default=environ.get("VOXTYPE_GEMINI_VAD_MODEL"))
    p.add_argument("--vad-threshold", type=float, default=0.5)
    p.add_argument("--local-model-dir")
    p.add_argument("--fillers", default=DEFAULT_FILLERS)
    p.add_argument("--wtype", default="wtype")
    p.add_argument("--input-file", help="16 kHz mono 16-bit WAV read instead of the microphone")
    args = p.parse_args(argv)
    if not args.vad_model:
        p.error("--vad-model (or VOXTYPE_GEMINI_VAD_MODEL) is required")
    return args


class WavStream:
    """File-backed stand-in for the arecord pipe."""

    def __init__(self, path):
        with open(path, "rb") as f:
            wav = silence.read_wav(f.read())
        if wav is None or wav.rate != VAD_RATE or wav.channels != 1:
            raise SystemExit("--input-file must be a 16 kHz mono 16-bit WAV")
        self._data = wav.frames
        self._pos = 0

    def read(self, n):
        chunk = self._data[self._pos : self._pos + n]
        self._pos += len(chunk)
        return chunk


class ReadyStream:
    """Calls on_ready after the first non-empty read, proving capture delivers audio."""

    def __init__(self, stream, on_ready):
        self._stream = stream
        self._on_ready = on_ready
        self.got_audio = False

    def read(self, n):
        data = self._stream.read(n)
        if data and not self.got_audio:
            self.got_audio = True
            self._on_ready()
        return data


def notify(message):
    if not shutil.which("notify-send"):
        return
    try:
        subprocess.run(
            ["notify-send", "-t", "4000", "-r", "9042", "Dictation", message],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        pass


def main(argv=None, environ=None):
    args = parse_args(argv, os.environ if environ is None else environ)

    def emit(text):
        text = clean_text(text, args.fillers)
        if not text:
            return
        result = subprocess.run([args.wtype, "--", text + " "], check=False)
        if result.returncode:
            log(f"wtype exited {result.returncode}")

    local = LocalRecognizer(args.local_model_dir) if args.local_model_dir else None
    pipeline = PhrasePipeline(
        FallbackTranscriber(args.url, local, notify), emit, context=not args.no_context
    )
    vad = StreamingVad(args.vad_model, pause_s=args.pause, threshold=args.vad_threshold)
    merger = Merger(min_s=args.min_phrase, hold_s=args.hold)

    stop = threading.Event()
    previous = {}
    if threading.current_thread() is threading.main_thread():
        for sig in (signal.SIGTERM, signal.SIGINT):
            previous[sig] = signal.signal(sig, lambda *_: stop.set())

    capture = None
    try:
        if args.input_file:
            stream = WavStream(args.input_file)
        else:
            capture = subprocess.Popen(
                ["arecord", "-q", "-D", args.device, "-f", "S16_LE", "-r", "16000", "-c", "1", "-t", "raw"],
                stdout=subprocess.PIPE,
            )
            stream = capture.stdout
        # The shell startup toast polls the runtime log for exactly this line.
        stream = ReadyStream(stream, lambda: print("Please speak", file=sys.stderr, flush=True))
        run(stream, vad, merger, pipeline, stop=stop)
    finally:
        if capture is not None:
            if capture.poll() is None:
                capture.terminate()
            capture.wait()
        for sig, handler in previous.items():
            signal.signal(sig, handler)

    if not stream.got_audio:
        log("capture ended before any audio")
        return 1

    return EXIT_PENDING if pipeline.pending else 0


if __name__ == "__main__":
    code = main()
    sys.stderr.flush()
    if code == EXIT_PENDING:
        # a stuck HTTP call would block the interpreter-exit join of executor threads
        os._exit(code)
    sys.exit(code)

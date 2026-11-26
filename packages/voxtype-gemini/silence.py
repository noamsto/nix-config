"""Speech-span detection and silence shortening for PCM WAV clips."""

import io
import threading
import wave
from dataclasses import dataclass

import numpy as np
import sherpa_onnx

VAD_RATE = 16000
VAD_WINDOW = 512
MIN_RATE = 8000
MAX_RATE = 48000
MAX_TRIM_SECONDS = 300

# mono_16k peaks at tens of times the clip size; unbounded concurrent requests
# would multiply that past the adapter unit's MemoryMax.
_vad_slots = threading.BoundedSemaphore(2)


@dataclass(frozen=True)
class Wav:
    rate: int
    channels: int
    frames: bytes  # interleaved little-endian int16
    n_frames: int

    @property
    def seconds(self):
        return self.n_frames / self.rate


@dataclass(frozen=True)
class TrimResult:
    audio: bytes
    seconds_in: float
    seconds_sent: float
    speech: bool
    processed: bool


def read_wav(data):
    try:
        with wave.open(io.BytesIO(data)) as w:
            channels = w.getnchannels()
            if w.getsampwidth() != 2 or channels not in (1, 2):
                return None
            rate = w.getframerate()
            # a tiny rate makes mono_16k upsample to a huge array
            if not MIN_RATE <= rate <= MAX_RATE:
                return None
            # header sizes lie: streamed WAVs carry placeholders and uploads get cut off
            raw = w.readframes(w.getnframes())
    except (wave.Error, EOFError):
        return None
    width = channels * 2
    n_frames = len(raw) // width
    return Wav(rate=rate, channels=channels, frames=raw[: n_frames * width], n_frames=n_frames)


def write_wav(wav):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(wav.channels)
        w.setsampwidth(2)
        w.setframerate(wav.rate)
        w.writeframes(wav.frames)
    return buf.getvalue()


def mono_16k(wav):
    pcm = np.frombuffer(wav.frames, dtype="<i2").astype(np.float32) / 32768.0
    mono = pcm.reshape(-1, wav.channels).mean(axis=1)
    if wav.rate == VAD_RATE:
        return mono
    n_out = round(len(mono) * VAD_RATE / wav.rate)
    positions = np.arange(n_out) * wav.rate / VAD_RATE
    return np.interp(positions, np.arange(len(mono)), mono).astype(np.float32)


def speech_spans(wav, model_path, threshold=0.5, min_silence_s=0.25):
    """Speech spans as (start, end) frame indices at the clip's own rate."""
    config = sherpa_onnx.VadModelConfig()
    config.silero_vad.model = model_path
    config.silero_vad.threshold = threshold
    config.silero_vad.min_silence_duration = min_silence_s
    config.sample_rate = VAD_RATE
    detector = sherpa_onnx.VoiceActivityDetector(config, 60)

    samples = mono_16k(wav)
    for i in range(0, len(samples), VAD_WINDOW):
        window = samples[i : i + VAD_WINDOW]
        if len(window) < VAD_WINDOW:
            window = np.pad(window, (0, VAD_WINDOW - len(window)))
        detector.accept_waveform(window)
    detector.flush()

    scale = wav.rate / VAD_RATE
    spans = []
    while not detector.empty():
        seg = detector.front
        start = min(wav.n_frames, round(seg.start * scale))
        end = min(wav.n_frames, round((seg.start + len(seg.samples)) * scale))
        spans.append((start, end))
        detector.pop()
    return spans


def shorten(wav, spans, max_silence_ms=300, pad_ms=200):
    """Cut long silences out of the original audio; None when there is no speech."""
    if not spans:
        return None
    max_silence = round(max_silence_ms * wav.rate / 1000)
    pad = round(pad_ms * wav.rate / 1000)
    width = wav.channels * 2

    def cut(start, end):
        return wav.frames[start * width : end * width]

    parts = [cut(spans[0][0] - min(spans[0][0], pad), spans[0][0])]
    for i, (start, end) in enumerate(spans):
        parts.append(cut(start, end))
        if i + 1 == len(spans):
            break
        next_start = spans[i + 1][0]
        if next_start - end <= max_silence:
            parts.append(cut(end, next_start))
        else:
            head = max_silence // 2
            parts.append(cut(end, end + head))
            parts.append(cut(next_start - (max_silence - head), next_start))
    last_end = spans[-1][1]
    parts.append(cut(last_end, last_end + min(wav.n_frames - last_end, pad)))

    data = b"".join(parts)
    return Wav(wav.rate, wav.channels, data, len(data) // width)


def trim(data, model_path, max_silence_ms, pad_ms, threshold):
    wav = read_wav(data)
    if wav is None:
        return TrimResult(data, 0.0, 0.0, speech=True, processed=False)
    if wav.seconds > MAX_TRIM_SECONDS:
        return TrimResult(data, 0.0, 0.0, speech=True, processed=False)
    with _vad_slots:
        shortened = shorten(
            wav, speech_spans(wav, model_path, threshold), max_silence_ms, pad_ms
        )
    if shortened is None:
        return TrimResult(b"", wav.seconds, 0.0, speech=False, processed=True)
    return TrimResult(
        write_wav(shortened), wav.seconds, shortened.seconds, speech=True, processed=True
    )

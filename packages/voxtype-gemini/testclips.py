"""Synthetic and espeak-generated audio shared by the test modules."""

import os
import subprocess

import numpy as np
import silence

RATE = 16000


def make_wav(samples, rate=RATE, channels=1):
    return silence.Wav(
        rate=rate,
        channels=channels,
        frames=np.asarray(samples, dtype="<i2").tobytes(),
        n_frames=len(samples) // channels,
    )


def samples_of(wav):
    return np.frombuffer(wav.frames, dtype="<i2")


def speak(tmp, voice, text, name):
    """Render text with espeak-ng into tmp; returns (float32 mono samples, rate)."""
    path = os.path.join(tmp, name)
    subprocess.run(
        ["espeak-ng", "-v", voice, "-s", "150", text, "-w", path],
        check=True,
        capture_output=True,
    )
    with open(path, "rb") as f:
        wav = silence.read_wav(f.read())
    assert wav is not None and wav.channels == 1
    return samples_of(wav).astype(np.float32) / 32768.0, wav.rate


def clip(rate, parts):
    """parts: list of ('s', seconds) silence or ('a', float array) audio."""
    out = [
        np.zeros(round(p * rate), dtype=np.float32) if k == "s" else p
        for k, p in parts
    ]
    return np.concatenate(out)


def hum(n, rate, seed):
    """70 Hz mains hum plus white noise: loud, but not speech."""
    rng = np.random.default_rng(seed)
    t = np.arange(n) / rate
    return 0.28 * np.sin(2 * np.pi * 70 * t) + rng.normal(0, 0.05, n)


def to_wav_bytes(signal, rate):
    pcm = np.clip(signal, -1.0, 1.0) * 32767
    return silence.write_wav(make_wav(pcm.astype("<i2"), rate=rate))


def to_16k(signal, rate):
    """float mono at any rate -> float32 mono at the VAD rate."""
    return silence.mono_16k(silence.read_wav(to_wav_bytes(signal, rate)))

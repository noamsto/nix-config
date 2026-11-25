import os
import shutil
import struct
import tempfile
import unittest
from unittest import mock

import numpy as np
import silence
from testclips import RATE, clip, hum, make_wav, samples_of, speak, to_wav_bytes

SPEECH = 1000  # constant non-zero sample so slices are identifiable
HE_TEXT = "שלום, אני רוצה לפתוח בקשת משיכה חדשה"


def frames(seconds):
    return round(seconds * RATE)


def synthetic(layout):
    """layout: list of (seconds, value) runs, value 0 = silence."""
    parts = [np.full(frames(s), v, dtype="<i2") for s, v in layout]
    return make_wav(np.concatenate(parts))


class ShortenTest(unittest.TestCase):
    def test_long_gap_becomes_exactly_300ms_from_both_sides(self):
        # speech 1 (value 1000), gap 2 s whose two ends are marked, speech 2
        gap = np.zeros(frames(2.0), dtype="<i2")
        gap[: frames(0.5)] = 7  # right after the previous span
        gap[-frames(0.5) :] = 9  # right before the next span
        head = np.full(frames(1.0), SPEECH, dtype="<i2")
        wav = make_wav(np.concatenate([head, gap, head]))
        spans = [(0, frames(1.0)), (frames(3.0), frames(4.0))]
        out = silence.shorten(wav, spans)
        got = samples_of(out)
        self.assertEqual(len(got), frames(1.0) + frames(0.3) + frames(1.0))
        mid = got[frames(1.0) : frames(1.3)]
        self.assertTrue((mid[: frames(0.15)] == 7).all())
        self.assertTrue((mid[frames(0.15) :] == 9).all())

    def test_gap_of_250ms_kept_verbatim(self):
        wav = synthetic([(1.0, SPEECH), (0.25, 0), (1.0, SPEECH)])
        spans = [(0, frames(1.0)), (frames(1.25), frames(2.25))]
        out = silence.shorten(wav, spans)
        self.assertEqual(samples_of(out).tolist(), samples_of(wav).tolist())

    def test_gap_of_exactly_300ms_kept(self):
        wav = synthetic([(1.0, SPEECH), (0.3, 0), (1.0, SPEECH)])
        spans = [(0, frames(1.0)), (frames(1.3), frames(2.3))]
        out = silence.shorten(wav, spans)
        self.assertEqual(out.n_frames, wav.n_frames)

    def test_leading_silence_cut_to_200ms(self):
        wav = synthetic([(1.0, 0), (1.0, SPEECH)])
        out = silence.shorten(wav, [(frames(1.0), frames(2.0))])
        got = samples_of(out)
        self.assertEqual(len(got), frames(0.2) + frames(1.0))
        self.assertTrue((got[: frames(0.2)] == 0).all())
        self.assertTrue((got[frames(0.2) :] == SPEECH).all())

    def test_short_leading_silence_kept_entirely(self):
        wav = synthetic([(0.1, 0), (1.0, SPEECH)])
        out = silence.shorten(wav, [(frames(0.1), frames(1.1))])
        self.assertEqual(out.n_frames, wav.n_frames)

    def test_trailing_silence_cut_to_200ms(self):
        wav = synthetic([(1.0, SPEECH), (1.5, 0)])
        out = silence.shorten(wav, [(0, frames(1.0))])
        got = samples_of(out)
        self.assertEqual(len(got), frames(1.0) + frames(0.2))
        self.assertTrue((got[: frames(1.0)] == SPEECH).all())

    def test_short_trailing_silence_kept_entirely(self):
        wav = synthetic([(1.0, SPEECH), (0.05, 0)])
        out = silence.shorten(wav, [(0, frames(1.0))])
        self.assertEqual(out.n_frames, wav.n_frames)

    def test_custom_max_silence_and_pad(self):
        wav = synthetic([(1.0, 0), (1.0, SPEECH), (1.0, 0), (1.0, SPEECH), (1.0, 0)])
        spans = [(frames(1.0), frames(2.0)), (frames(3.0), frames(4.0))]
        out = silence.shorten(wav, spans, max_silence_ms=100, pad_ms=50)
        self.assertEqual(
            out.n_frames, frames(0.05) + frames(1.0) + frames(0.1) + frames(1.0) + frames(0.05)
        )

    def test_no_spans_is_none(self):
        wav = synthetic([(1.0, 0)])
        self.assertIsNone(silence.shorten(wav, []))

    def test_three_span_total_length(self):
        wav = synthetic(
            [
                (2.0, 0),
                (1.0, SPEECH),
                (0.2, 0),
                (1.0, SPEECH),
                (5.0, 0),
                (1.0, SPEECH),
                (3.0, 0),
            ]
        )
        spans = [
            (frames(2.0), frames(3.0)),
            (frames(3.2), frames(4.2)),
            (frames(9.2), frames(10.2)),
        ]
        out = silence.shorten(wav, spans)
        expected = (
            frames(0.2)  # leading, cut
            + 3 * frames(1.0)  # speech
            + frames(0.2)  # short gap, verbatim
            + frames(0.3)  # long gap, collapsed
            + frames(0.2)  # trailing, cut
        )
        self.assertEqual(out.n_frames, expected)

    def test_stereo_8k_keeps_layout(self):
        rate = 8000
        n = rate * 4
        mono = np.zeros(n, dtype="<i2")
        mono[rate : rate * 2] = SPEECH
        stereo = np.repeat(mono, 2)
        wav = make_wav(stereo, rate=rate, channels=2)
        out = silence.shorten(wav, [(rate, rate * 2)])
        self.assertEqual((out.rate, out.channels), (rate, 2))
        # 0.2 s lead + 1 s speech + 0.2 s tail
        self.assertEqual(out.n_frames, round(0.2 * rate) * 2 + rate)
        self.assertEqual(len(out.frames), out.n_frames * 2 * 2)


def raw_wav(payload, rate=RATE, channels=1, declared=None):
    """A PCM WAV whose data chunk declares `declared` bytes (default: all of payload)."""
    declared = len(payload) if declared is None else declared
    fmt = struct.pack("<HHIIHH", 1, channels, rate, rate * channels * 2, channels * 2, 16)
    body = (
        b"WAVEfmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", declared) + payload
    )
    return b"RIFF" + struct.pack("<I", len(body)) + body


class MalformedWavTest(unittest.TestCase):
    def test_data_chunk_cut_mid_sample_keeps_whole_frames(self):
        wav = silence.read_wav(raw_wav(bytes(1001), declared=2000))
        self.assertEqual(wav.n_frames, 500)
        self.assertEqual(len(wav.frames), 1000)

    def test_stereo_with_odd_sample_count_keeps_whole_frames(self):
        wav = silence.read_wav(raw_wav(bytes(38), channels=2, declared=40))
        self.assertEqual(wav.n_frames, 9)
        self.assertEqual(len(wav.frames), 36)
        self.assertEqual(silence.mono_16k(wav).shape, (9,))

    def test_placeholder_header_size_reports_real_duration(self):
        wav = silence.read_wav(raw_wav(bytes(RATE * 2), declared=0xFFFFFFFF))
        self.assertEqual(wav.n_frames, RATE)
        self.assertAlmostEqual(wav.seconds, 1.0)

    def test_framerate_outside_8k_to_48k_is_rejected(self):
        for rate in (0, 8, 7999, 48001, 192000):
            with self.subTest(rate=rate):
                self.assertIsNone(silence.read_wav(raw_wav(bytes(64), rate=rate)))

    def test_framerate_limits_are_accepted(self):
        for rate in (8000, 48000):
            with self.subTest(rate=rate):
                self.assertEqual(silence.read_wav(raw_wav(bytes(64), rate=rate)).rate, rate)

    def test_trim_passes_bad_framerates_through(self):
        for rate in (0, 8, 192000):
            data = raw_wav(bytes(64), rate=rate)
            result = silence.trim(data, "/nonexistent", 300, 200, 0.5)
            self.assertFalse(result.processed)
            self.assertEqual(result.audio, data)

    def test_trim_survives_truncated_data(self):
        model = os.environ.get("VOXTYPE_GEMINI_VAD_MODEL")
        for data in (raw_wav(bytes(1001), declared=2000), raw_wav(bytes(38), channels=2, declared=40)):
            result = silence.trim(data, model, 300, 200, 0.5)
            self.assertTrue(result.processed)


class LongClipTest(unittest.TestCase):
    def test_clip_over_limit_passes_through_without_vad(self):
        data = to_wav_bytes(np.zeros(8000 * (silence.MAX_TRIM_SECONDS + 1), dtype="<i2"), 8000)
        with mock.patch.object(silence, "speech_spans", side_effect=AssertionError("vad ran")):
            result = silence.trim(data, "/nonexistent", 300, 200, 0.5)
        self.assertFalse(result.processed)
        self.assertEqual(result.audio, data)
        self.assertTrue(result.speech)


class WavIoTest(unittest.TestCase):
    def test_round_trip(self):
        wav = synthetic([(0.5, SPEECH), (0.5, 0)])
        back = silence.read_wav(silence.write_wav(wav))
        self.assertEqual(back, wav)
        self.assertAlmostEqual(back.seconds, 1.0)

    def test_float_wav_unsupported(self):
        samples = np.zeros(1600, dtype="<f4").tobytes()
        fmt = struct.pack("<HHIIHH", 3, 1, RATE, RATE * 4, 4, 32)
        body = (
            b"WAVE"
            + b"fmt "
            + struct.pack("<I", len(fmt))
            + fmt
            + b"data"
            + struct.pack("<I", len(samples))
            + samples
        )
        data = b"RIFF" + struct.pack("<I", len(body)) + body
        self.assertIsNone(silence.read_wav(data))

    def test_garbage_unparseable(self):
        self.assertIsNone(silence.read_wav(b"not a wav at all"))

    def test_trim_passes_unparseable_through(self):
        result = silence.trim(b"not a wav", "/nonexistent", 300, 200, 0.5)
        self.assertFalse(result.processed)
        self.assertEqual(result.audio, b"not a wav")
        self.assertTrue(result.speech)
        self.assertEqual((result.seconds_in, result.seconds_sent), (0.0, 0.0))


class RealVadTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.model = os.environ["VOXTYPE_GEMINI_VAD_MODEL"]
        cls.tmp = tempfile.mkdtemp()
        cls.en = speak(cls.tmp, "en-us", "please open a new account for me today", "en.wav")
        cls.en2 = speak(cls.tmp, "en-us", "and then close the old savings account", "en2.wav")
        cls.he = speak(cls.tmp, "he", HE_TEXT, "he.wav")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def long_clip(self, with_hum=False):
        (a, rate), (b, rate_b) = self.en, self.en2
        self.assertEqual(rate, rate_b)
        signal = clip(rate, [("s", 1.0), ("a", a), ("s", 2.0), ("a", b), ("s", 1.5)])
        if with_hum:
            signal = signal + hum(len(signal), rate, seed=0)
        return to_wav_bytes(signal, rate), (len(a) / rate, len(b) / rate)

    def spans_seconds(self, data):
        wav = silence.read_wav(data)
        spans = silence.speech_spans(wav, self.model)
        return sum(e - s for s, e in spans) / wav.rate, len(spans)

    def check_trimmed(self, data):
        speech_s, n_spans = self.spans_seconds(data)
        self.assertEqual(n_spans, 2)
        result = silence.trim(data, self.model, 300, 200, 0.5)
        self.assertTrue(result.processed)
        self.assertTrue(result.speech)
        self.assertLess(result.seconds_sent, result.seconds_in)
        # speech + one collapsed gap (0.3) + both edges (0.2 each)
        self.assertAlmostEqual(result.seconds_sent, speech_s + 0.3 + 0.4, delta=0.1)
        sent = silence.read_wav(result.audio)
        self.assertAlmostEqual(sent.seconds, result.seconds_sent, places=3)

    def test_speech_clip_is_trimmed(self):
        data, _ = self.long_clip()
        self.check_trimmed(data)

    def test_speech_over_hum_is_trimmed(self):
        data, _ = self.long_clip(with_hum=True)
        self.check_trimmed(data)

    def test_interior_silence_and_edges_by_energy(self):
        data, _ = self.long_clip()
        out = silence.read_wav(silence.trim(data, self.model, 300, 200, 0.5).audio)
        x = np.abs(samples_of(out).astype(np.float32)) / 32768.0
        loud = np.flatnonzero(x > 0.02)
        lead = loud[0] / out.rate
        trail = (len(x) - 1 - loud[-1]) / out.rate
        # 0.2 s of kept silence plus the quiet onset/decay inside the span
        self.assertLess(lead, 0.3)
        self.assertLess(trail, 0.3)
        gaps = np.diff(loud) / out.rate
        interior = gaps.max()
        self.assertAlmostEqual(interior, 0.3, delta=0.1)

    def test_hebrew_detected(self):
        a, rate = self.he
        signal = clip(rate, [("s", 1.0), ("a", a), ("s", 1.0)])
        spans = silence.speech_spans(silence.read_wav(to_wav_bytes(signal, rate)), self.model)
        self.assertTrue(spans)

    def assert_no_speech(self, signal, rate):
        result = silence.trim(to_wav_bytes(signal, rate), self.model, 300, 200, 0.5)
        self.assertTrue(result.processed)
        self.assertFalse(result.speech)

    def test_digital_silence_has_no_speech(self):
        self.assert_no_speech(np.zeros(RATE * 3, dtype=np.float32), RATE)

    def test_low_noise_has_no_speech(self):
        rng = np.random.default_rng(1)
        self.assert_no_speech(rng.normal(0, 0.005, RATE * 3).astype(np.float32), RATE)

    def test_hum_only_has_no_speech(self):
        self.assert_no_speech(hum(RATE * 3, RATE, seed=2).astype(np.float32), RATE)


if __name__ == "__main__":
    unittest.main()

import contextlib
import io
import os
import random
import shutil
import tempfile
import threading
import unittest
from concurrent import futures

import numpy as np
import phrases
import testclips
from phrases import VAD_RATE, Merger, OrderedEmitter, PhrasePipeline, Segment

WAIT = 10  # bound on every synchronisation wait, so a bug fails instead of hanging


def seg(start, seconds, value=0.5):
    return Segment(start, np.full(round(seconds * VAD_RATE), value, dtype=np.float32))


def tagged(tag, seconds=2.0):
    """A segment whose samples carry an integer tag, read back by fake transcribers."""
    return seg(float(tag), seconds, value=float(tag))


def tag_of(samples):
    return int(samples[0])


def pcm_bytes(signal):
    return (np.clip(signal, -1.0, 1.0) * 32767).astype("<i2").tobytes()


class FakeStream:
    def __init__(self, data):
        self.data = data
        self.pos = 0
        self.eof = threading.Event()

    def read(self, n):
        chunk = self.data[self.pos : self.pos + n]
        self.pos += len(chunk)
        if not chunk:
            self.eof.set()
        return chunk


class Recorder:
    """Stands in for PhrasePipeline: keeps what run() submits."""

    def __init__(self):
        self.segments = []
        self.closed = False

    def submit(self, segment):
        self.segments.append(segment)
        return len(self.segments) - 1

    def close(self, timeout=8.0):
        self.closed = True
        return True


class MergerTest(unittest.TestCase):
    def test_long_segment_passes_untouched(self):
        m = Merger()
        s = seg(0.0, 2.0)
        (out,) = m.feed(s)
        self.assertIs(out, s)
        self.assertEqual(m.flush(), [])

    def test_short_segment_merged_into_next_with_real_gap(self):
        m = Merger()
        a = seg(1.0, 0.5, value=0.1)
        b = seg(1.8, 1.25, value=0.2)
        self.assertEqual(m.feed(a), [])
        (merged,) = m.feed(b)
        self.assertEqual(merged.start, 1.0)
        self.assertEqual(len(merged.samples), 8000 + 4800 + 20000)
        self.assertTrue((merged.samples[:8000] == np.float32(0.1)).all())
        self.assertTrue((merged.samples[8000:12800] == 0).all())
        self.assertTrue((merged.samples[12800:] == np.float32(0.2)).all())
        self.assertAlmostEqual(merged.end, 3.05)
        self.assertEqual(m.flush(), [])

    def test_gap_capped_at_max_gap(self):
        m = Merger(max_gap_s=0.5)
        m.feed(seg(0.0, 0.5))
        (merged,) = m.feed(seg(3.0, 1.5))
        self.assertEqual(len(merged.samples), 8000 + 8000 + 24000)
        self.assertTrue((merged.samples[8000:16000] == 0).all())

    def test_chain_of_shorts_emitted_once_when_min_reached(self):
        m = Merger(min_s=1.5)
        self.assertEqual(m.feed(seg(0.0, 0.4)), [])
        self.assertEqual(m.feed(seg(0.6, 0.4)), [])
        (merged,) = m.feed(seg(1.2, 0.5))
        self.assertEqual(merged.start, 0.0)
        self.assertEqual(len(merged.samples), 6400 + 3200 + 6400 + 3200 + 8000)
        self.assertEqual(m.flush(), [])

    def test_held_short_then_long_is_one_emission(self):
        m = Merger()
        m.feed(seg(0.0, 0.5))
        (merged,) = m.feed(seg(1.0, 3.0))
        self.assertEqual(merged.start, 0.0)
        self.assertAlmostEqual(merged.seconds, 0.5 + 0.5 + 3.0)
        self.assertEqual(m.flush(), [])

    def test_tick_releases_held_after_hold(self):
        m = Merger(hold_s=3.0)
        s = seg(0.0, 0.5)
        m.feed(s)
        self.assertEqual(m.tick(0.5 + 2.9), [])
        self.assertEqual(m.tick(0.5 + 3.0), [s])
        self.assertEqual(m.tick(10.0), [])
        self.assertEqual(m.flush(), [])

    def test_tick_without_held_is_empty(self):
        self.assertEqual(Merger().tick(100.0), [])

    def test_flush_releases_held(self):
        m = Merger()
        s = seg(0.0, 0.5)
        m.feed(s)
        self.assertEqual(m.flush(), [s])
        self.assertEqual(m.flush(), [])


class OrderedEmitterTest(unittest.TestCase):
    def test_out_of_order_completion_is_emitted_in_order(self):
        emitted = []
        e = OrderedEmitter(emitted.append)
        self.assertEqual([e.reserve() for _ in range(3)], [0, 1, 2])
        e.complete(2, "c")
        self.assertEqual(emitted, [])
        e.complete(0, "a")
        self.assertEqual(emitted, ["a"])
        e.complete(1, "b")
        self.assertEqual(emitted, ["a", "b", "c"])

    def test_missing_results_skipped_without_blocking(self):
        emitted = []
        e = OrderedEmitter(emitted.append)
        for _ in range(4):
            e.reserve()
        e.complete(1, "b")
        e.complete(0, None)
        self.assertEqual(emitted, ["b"])
        e.complete(3, "d")
        e.complete(2, "")
        self.assertEqual(emitted, ["b", "d"])

    def test_emit_failure_is_logged_without_text_and_later_phrases_still_emit(self):
        emitted = []

        def emit(text):
            if text == "secret zero":
                raise OSError("wtype missing")
            emitted.append(text)

        e = OrderedEmitter(emit)
        e.reserve()
        e.reserve()
        e.complete(1, "second")
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            e.complete(0, "secret zero")
        self.assertEqual(emitted, ["second"])
        logged = err.getvalue()
        self.assertIn("emit failed: OSError", logged)
        self.assertNotIn("secret", logged)

    def test_concurrent_completes_never_reorder_or_duplicate(self):
        n, n_threads = 400, 8
        emitted = []
        overlap = []
        active = [0]
        guard = threading.Lock()

        def emit(text):
            with guard:
                active[0] += 1
                if active[0] > 1:
                    overlap.append(text)
            emitted.append(text)
            with guard:
                active[0] -= 1

        e = OrderedEmitter(emit)
        seqs = [e.reserve() for _ in range(n)]
        random.Random(7).shuffle(seqs)
        barrier = threading.Barrier(n_threads, timeout=WAIT)

        def worker(part):
            barrier.wait()
            for s in part:
                e.complete(s, str(s))

        threads = [
            threading.Thread(target=worker, args=(seqs[i::n_threads],)) for i in range(n_threads)
        ]
        for t in threads:
            t.start()
        for t in threads:
            t.join(WAIT)
            self.assertFalse(t.is_alive())
        self.assertEqual(emitted, [str(i) for i in range(n)])
        self.assertEqual(overlap, [])


class EmitCase(unittest.TestCase):
    def setUp(self):
        self.emitted = []
        self.prompts = {}
        self.emitted_cond = threading.Condition()

    def emit(self, text):
        with self.emitted_cond:
            self.emitted.append(text)
            self.emitted_cond.notify_all()

    def wait_emitted(self, n):
        with self.emitted_cond:
            ok = self.emitted_cond.wait_for(lambda: len(self.emitted) >= n, WAIT)
        self.assertTrue(ok, f"only {self.emitted} emitted")


class PipelineTest(EmitCase):
    def test_later_phrase_finishing_first_is_typed_second(self):
        seq1_done = threading.Event()

        def transcribe(samples, prompt):
            if tag_of(samples) == 0:
                self.assertTrue(seq1_done.wait(WAIT))
                return "text0"
            seq1_done.set()
            return "text1"

        p = PhrasePipeline(transcribe, self.emit, workers=2)
        self.assertEqual(p.submit(tagged(0)), 0)
        self.assertEqual(p.submit(tagged(1)), 1)
        self.assertTrue(p.close())
        self.assertEqual(self.emitted, ["text0", "text1"])

    def test_submit_accepts_raw_samples(self):
        p = PhrasePipeline(lambda samples, prompt: f"t{tag_of(samples)}", self.emit, workers=1)
        p.submit(tagged(3).samples)
        self.assertTrue(p.close())
        self.assertEqual(self.emitted, ["t3"])

    def test_capture_continues_while_segments_in_flight(self):
        n_chunks, chunk = 60, 512
        segment_chunks = [5, 15, 25, 35, 45, 55]
        gate = threading.Event()
        started = []

        class FakeVad:
            speaking = False

            def __init__(self):
                self.chunk = 0

            def accept(self, samples):
                self.chunk += 1
                if self.chunk in segment_chunks:
                    return [tagged(segment_chunks.index(self.chunk))]
                return []

            def flush(self):
                return []

        class WatchedPipeline(PhrasePipeline):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                self.count = 0
                self.all_submitted = threading.Event()
                self.closing = threading.Event()

            def submit(self, segment):
                seq = super().submit(segment)
                self.count += 1
                if self.count == len(segment_chunks):
                    self.all_submitted.set()
                return seq

            def close(self, timeout=8.0):
                self.closing.set()
                return super().close(timeout)

        def transcribe(samples, prompt):
            started.append(tag_of(samples))
            gate.wait(WAIT)
            return f"t{tag_of(samples)}"

        stream = FakeStream(bytes(n_chunks * chunk * 2))
        pipeline = WatchedPipeline(transcribe, self.emit, workers=2)
        result = []
        runner = threading.Thread(
            target=lambda: result.append(
                phrases.run(stream, FakeVad(), Merger(), pipeline, chunk_samples=chunk)
            )
        )
        runner.start()
        self.assertTrue(stream.eof.wait(WAIT))
        self.assertTrue(pipeline.all_submitted.wait(WAIT))
        self.assertTrue(pipeline.closing.wait(WAIT))
        self.assertEqual(stream.pos, len(stream.data))
        self.assertEqual(self.emitted, [])
        self.assertLessEqual(len(started), 2)
        gate.set()
        runner.join(WAIT)
        self.assertFalse(runner.is_alive())
        self.assertEqual(result, [6])
        self.assertEqual(self.emitted, [f"t{i}" for i in range(6)])

    def test_close_reports_pending_work_at_timeout(self):
        gate = threading.Event()
        entered = threading.Event()

        def transcribe(samples, prompt):
            entered.set()
            gate.wait(WAIT)
            return "late"

        p = PhrasePipeline(transcribe, self.emit, workers=1)
        p.submit(tagged(0))
        self.assertTrue(entered.wait(WAIT))
        err = io.StringIO()
        try:
            with contextlib.redirect_stderr(err):
                self.assertFalse(p.close(timeout=0.05))
        finally:
            gate.set()
        self.assertIn("1 phrase(s) still pending", err.getvalue())

    def test_finished_future_not_yet_forgotten_is_not_pending(self):
        p = PhrasePipeline(lambda samples, prompt: "x", self.emit, workers=1)
        done = futures.Future()
        done.set_result(None)
        p._futures.add(done)
        self.assertFalse(p.pending)
        self.assertTrue(p.close())

    def test_transcribe_failure_is_logged_without_text_and_skipped(self):
        def transcribe(samples, prompt):
            tag = tag_of(samples)
            self.prompts[tag] = prompt
            if tag == 1:
                raise RuntimeError("secret words from the request")
            return f"phrase number {tag}"

        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            p = PhrasePipeline(transcribe, self.emit, workers=1)
            for i in range(3):
                p.submit(tagged(i))
            self.assertTrue(p.close())
        self.assertEqual(self.emitted, ["phrase number 0", "phrase number 2"])
        self.assertEqual(self.prompts[2], "phrase number 0")
        logged = err.getvalue()
        self.assertEqual(len(logged.splitlines()), 1, logged)
        self.assertIn("RuntimeError", logged)
        for secret in ("secret", "phrase number"):
            self.assertNotIn(secret, logged)


class ContextRuleTest(EmitCase):
    def test_previous_finished_text_is_the_prompt(self):
        texts = {0: "alpha", 1: "beta"}

        def transcribe(samples, prompt):
            self.prompts[tag_of(samples)] = prompt
            return texts[tag_of(samples)]

        p = PhrasePipeline(transcribe, self.emitted.append, workers=1)
        p.submit(tagged(0))
        p.submit(tagged(1))
        self.assertTrue(p.close())
        self.assertEqual(self.prompts, {0: None, 1: "alpha"})

    def test_in_flight_predecessor_is_skipped_for_highest_finished(self):
        texts = {0: "alpha", 1: "beta", 2: "gamma", 3: "delta"}
        seq1_started, seq1_gate, seq2_called = (threading.Event() for _ in range(3))

        def transcribe(samples, prompt):
            tag = tag_of(samples)
            self.prompts[tag] = prompt
            if tag == 1:
                seq1_started.set()
                self.assertTrue(seq1_gate.wait(WAIT))
            if tag == 2:
                seq2_called.set()
            return texts[tag]

        p = PhrasePipeline(transcribe, self.emit, workers=2)
        p.submit(tagged(0))
        self.wait_emitted(1)
        p.submit(tagged(1))
        self.assertTrue(seq1_started.wait(WAIT))
        p.submit(tagged(2))
        self.assertTrue(seq2_called.wait(WAIT))
        self.assertEqual(self.prompts[2], "alpha")
        self.assertEqual(self.emitted, ["alpha"])
        seq1_gate.set()
        self.wait_emitted(3)
        p.submit(tagged(3))
        self.assertTrue(p.close())
        self.assertEqual(self.prompts[1], "alpha")
        # seq2 was transcribed before seq1 finished; context follows seq order, not finish time
        self.assertEqual(self.prompts[3], "gamma")
        self.assertEqual(self.emitted, ["alpha", "beta", "gamma", "delta"])

    def test_context_disabled_never_sends_prompt(self):
        def transcribe(samples, prompt):
            self.prompts[tag_of(samples)] = prompt
            return "words"

        p = PhrasePipeline(transcribe, self.emitted.append, workers=1, context=False)
        for i in range(3):
            p.submit(tagged(i))
        self.assertTrue(p.close())
        self.assertEqual(self.prompts, {0: None, 1: None, 2: None})

    def test_empty_or_failed_transcript_is_not_context(self):
        def transcribe(samples, prompt):
            tag = tag_of(samples)
            self.prompts[tag] = prompt
            if tag == 2:
                raise OSError("down")
            return {0: "alpha", 1: ""}.get(tag, "omega")

        with contextlib.redirect_stderr(io.StringIO()):
            p = PhrasePipeline(transcribe, self.emitted.append, workers=1)
            for i in range(4):
                p.submit(tagged(i))
            self.assertTrue(p.close())
        self.assertEqual(self.prompts, {0: None, 1: "alpha", 2: "alpha", 3: "alpha"})
        self.assertEqual(self.emitted, ["alpha", "omega"])


class RunTest(unittest.TestCase):
    class ScriptedVad:
        """Returns preset segments at chosen chunk numbers; `speaking` per chunk."""

        def __init__(self, at, speaking_chunks=()):
            self.at = at
            self.speaking_chunks = set(speaking_chunks)
            self.chunk = 0
            self.speaking = False

        def accept(self, samples):
            self.chunk += 1
            self.speaking = self.chunk in self.speaking_chunks
            return self.at.get(self.chunk, [])

        def flush(self):
            return self.at.get("flush", [])

    def run_vad(self, vad, seconds, chunk=512, stop=None):
        stream = FakeStream(bytes(round(seconds * VAD_RATE) * 2))
        recorder = Recorder()
        n = phrases.run(stream, vad, Merger(), recorder, chunk_samples=chunk, stop=stop)
        self.assertTrue(recorder.closed)
        self.assertEqual(n, len(recorder.segments))
        return recorder.segments

    def test_held_short_released_by_tick_after_hold_silence(self):
        short = seg(0.0, 0.5)
        vad = self.ScriptedVad({20: [short]})
        submitted_at = []

        class Watch(Recorder):
            def submit(self, segment):
                submitted_at.append(vad.chunk)
                return super().submit(segment)

        recorder = Watch()
        phrases.run(FakeStream(bytes(round(3.6 * VAD_RATE) * 2)), vad, Merger(), recorder)
        self.assertEqual(recorder.segments, [short])
        # 512-sample chunks of 0.032 s: the clock first reaches end 0.5 + hold 3.0 at chunk 110
        self.assertEqual(submitted_at, [110])

    def test_tick_waits_while_speech_is_in_progress(self):
        short = seg(0.0, 0.5)
        long = seg(2.0, 3.0)
        # speaking from chunk 40 (1.28 s) until the long segment lands at chunk 180 (5.76 s)
        vad = self.ScriptedVad({20: [short], 180: [long]}, speaking_chunks=range(40, 180))
        (merged,) = self.run_vad(vad, 6.0)
        self.assertEqual(merged.start, 0.0)
        self.assertAlmostEqual(merged.seconds, 0.5 + 0.5 + 3.0)

    def test_vad_flush_and_merger_flush_at_eof(self):
        short = seg(0.0, 0.5)
        vad = self.ScriptedVad({"flush": [short]})
        self.assertEqual(self.run_vad(vad, 0.5), [short])

    def test_odd_byte_reads_are_carried(self):
        class OddStream(FakeStream):
            def read(self, n):
                return super().read(n - 1)

        samples = np.arange(-500, 500, dtype="<i2")
        got = []

        class Collect:
            speaking = False

            def accept(self, x):
                got.append(x)
                return []

            def flush(self):
                return []

        phrases.run(OddStream(samples.tobytes()), Collect(), Merger(), Recorder(), chunk_samples=7)
        joined = np.concatenate(got)
        self.assertEqual(joined.dtype, np.float32)
        np.testing.assert_array_equal(joined, samples.astype(np.float32) / 32768.0)

    def test_stop_event_ends_capture_like_eof(self):
        stop = threading.Event()
        short = seg(0.0, 0.5)

        class StopAfterFirst(self.ScriptedVad):
            def accept(self, samples):
                stop.set()
                return super().accept(samples)

        vad = StopAfterFirst({1: [short]})
        segments = self.run_vad(vad, 10.0, stop=stop)
        self.assertEqual(vad.chunk, 1)
        self.assertEqual(segments, [short])


class RealVadPhrasesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.model = os.environ["VOXTYPE_GEMINI_VAD_MODEL"]
        cls.tmp = tempfile.mkdtemp()
        cls.a = cls.say("please open a new account for me today", "a.wav")
        cls.b = cls.say("and then close the old savings account", "b.wav")
        cls.yes = cls.say("yes", "yes.wav")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    @classmethod
    def say(cls, text, name):
        return testclips.to_16k(*testclips.speak(cls.tmp, "en-us", text, name))

    def signal(self, *parts):
        return testclips.clip(
            VAD_RATE, [("s", p) if isinstance(p, float) else ("a", p) for p in parts]
        )

    def raw_segments(self, signal, chunk=512):
        vad = phrases.StreamingVad(self.model)
        out = []
        for i in range(0, len(signal), chunk):
            out += vad.accept(signal[i : i + chunk])
        return out + vad.flush()

    def merged_segments(self, signal, chunk=512):
        recorder = Recorder()
        stream = FakeStream(pcm_bytes(signal))
        n = phrases.run(
            stream, phrases.StreamingVad(self.model), Merger(), recorder, chunk_samples=chunk
        )
        self.assertEqual(n, len(recorder.segments))
        return recorder.segments

    def test_pause_longer_than_threshold_splits(self):
        sig = self.signal(0.5, self.a, 1.3, self.b, 1.5)
        first, second = self.merged_segments(sig)
        self.assertAlmostEqual(first.start, 0.5, delta=0.15)
        self.assertAlmostEqual(second.start, 0.5 + len(self.a) / VAD_RATE + 1.3, delta=0.15)
        self.assertAlmostEqual(first.seconds, len(self.a) / VAD_RATE, delta=0.5)
        self.assertAlmostEqual(second.seconds, len(self.b) / VAD_RATE, delta=0.5)

    def test_short_pause_does_not_split(self):
        sig = self.signal(0.5, self.a, 0.4, self.b, 1.5)
        (only,) = self.raw_segments(sig)
        total = (len(self.a) + len(self.b)) / VAD_RATE + 0.4
        self.assertAlmostEqual(only.seconds, total, delta=0.5)

    def test_short_utterance_merged_into_following_phrase(self):
        sig = self.signal(0.5, self.yes, 1.3, self.b, 1.5)
        short, long = self.raw_segments(sig)
        self.assertLess(short.seconds, 1.5)
        (merged,) = self.merged_segments(sig)
        self.assertAlmostEqual(merged.start, short.start, places=3)
        self.assertAlmostEqual(merged.seconds, short.seconds + 0.5 + long.seconds, delta=0.01)

    def test_segment_count_independent_of_chunk_size(self):
        sig = self.signal(0.5, self.a, 1.3, self.b, 1.3, self.yes, 0.4, self.a, 1.5)
        reference = self.merged_segments(sig, chunk=512)
        self.assertEqual(len(reference), 3)
        for chunk in (700, 333, 4096):
            with self.subTest(chunk=chunk):
                got = self.merged_segments(sig, chunk=chunk)
                self.assertEqual(len(got), len(reference))
                for g, r in zip(got, reference):
                    self.assertAlmostEqual(g.start, r.start, delta=0.05)
                    self.assertAlmostEqual(g.seconds, r.seconds, delta=0.05)

    def test_end_to_end_through_pipeline_in_spoken_order(self):
        sig = self.signal(0.5, self.a, 1.3, self.b, 1.3, self.a, 1.5)
        emitted = []

        def transcribe(samples, prompt):
            return f"{len(samples)}"

        expected = [f"{len(s.samples)}" for s in self.merged_segments(sig)]
        pipeline = PhrasePipeline(transcribe, emitted.append, workers=3)
        stream = FakeStream(pcm_bytes(sig))
        n = phrases.run(
            stream, phrases.StreamingVad(self.model), Merger(), pipeline, chunk_samples=700
        )
        self.assertEqual(n, 3)
        self.assertEqual(emitted, expected)


if __name__ == "__main__":
    unittest.main()

"""Compare Gemini Transcribe, Gemini flash-lite, gemini-3.8-flash and local Parakeet on a clip directory.

Clips should be 16 kHz mono WAV, the format voxtype records.

--segment instead measures what silence trimming and phrase splitting save: each
clip is sent whole, trimmed, as VAD phrases, and as phrases with the previous
phrase's transcript as context. The context variant runs phrases sequentially, so
the previous transcript is always available: the IDEAL case of the live pipeline,
which never waits for context and may send a phrase without it.
"""

import argparse
import difflib
import io
import os
import subprocess
import sys
from dataclasses import dataclass, replace
from pathlib import Path

import adapter
import numpy as np
import phrases
import silence

FLASH_LITE_MODEL = "gemini-3.5-flash-lite"
FLASH_3_8_MODEL = "gemini-3.8-flash"
FLASH_LITE_PROMPT = (
    "Transcribe this audio verbatim. The speech may mix Hebrew and English. "
    "Keep each word in the language it was spoken in; do not translate. "
    "Output only the transcript."
)


def gemini_transcribe(key, clip):
    # No VAD model configured means no trimming rather than a startup error.
    trim = adapter.trim_config_from_environ(os.environ) if os.environ.get("VOXTYPE_GEMINI_VAD_MODEL") else None
    config = adapter.Config(
        api_key=key,
        vocabulary=adapter.split_list(os.environ.get("VOXTYPE_GEMINI_VOCABULARY", "")),
        language_codes=adapter.split_list(os.environ.get("VOXTYPE_GEMINI_LANGUAGE_CODES", "")),
        timeout_secs=60,
        smart=adapter.smart_from_environ(os.environ),
        trim=trim,
    )
    return adapter.transcribe(config, clip.read_bytes(), "audio/wav").text


def flash_verbatim(key, clip, model, thinking_level):
    return adapter.call_gemini(
        adapter.DEFAULT_BASE_URL,
        key,
        60,
        model,
        [
            {"type": "text", "text": FLASH_LITE_PROMPT},
            adapter.audio_part(clip.read_bytes(), "audio/wav"),
        ],
        {"thinking_level": thinking_level},
    )


def parakeet(clip):
    result = subprocess.run(
        ["voxtype", "--model", "parakeet-tdt-0.6b-v3", "transcribe", str(clip)],
        capture_output=True,
        text=True,
        timeout=120,
        check=True,
    )
    # stdout carries log lines, then a blank line, then the transcript.
    _, separator, transcript = result.stdout.strip().rpartition("\n\n")
    return transcript.strip() if separator else ""


def attempt(fn, *args):
    try:
        return fn(*args)
    except (adapter.UpstreamError, OSError, subprocess.SubprocessError) as err:
        return f"<error: {err}>"


@dataclass
class Variant:
    text: str
    sent: float
    n_phrases: int | None = None


class PhraseCollector:
    """Stands in for PhrasePipeline: keeps the segments run() would transcribe."""

    def __init__(self):
        self.segments = []

    def submit(self, segment):
        self.segments.append(segment.samples)

    def close(self):
        return True


def word_diff(a, b):
    """Word edits between two transcripts, ignoring case and punctuation."""
    words_a = [w.casefold() for w in adapter.TOKEN.findall(a)]
    words_b = [w.casefold() for w in adapter.TOKEN.findall(b)]
    ops = difflib.SequenceMatcher(None, words_a, words_b, autojunk=False).get_opcodes()
    return sum(max(i2 - i1, j2 - j1) for tag, i1, i2, j1, j2 in ops if tag != "equal")


def split_phrases(wav, args):
    pcm = (np.clip(silence.mono_16k(wav), -1.0, 1.0) * 32767).astype("<i2").tobytes()
    collector = PhraseCollector()
    phrases.run(
        io.BytesIO(pcm),
        phrases.StreamingVad(args.vad_model, pause_s=args.pause),
        phrases.Merger(min_s=args.min_phrase, hold_s=args.hold),
        collector,
    )
    return collector.segments


def phrase_wav(samples):
    pcm = (np.clip(samples, -1.0, 1.0) * 32767).astype("<i2")
    return silence.write_wav(silence.Wav(silence.VAD_RATE, 1, pcm.tobytes(), len(pcm)))


def transcribe_whole(config, data, wav, args):
    result = adapter.transcribe(replace(config, trim=None), data, "audio/wav")
    return Variant(result.text, wav.seconds)


def transcribe_trimmed(config, data, wav, args):
    result = adapter.transcribe(config, data, "audio/wav")
    return Variant(result.text, result.seconds_sent)


def transcribe_phrases(config, data, wav, args, context=False):
    segments = split_phrases(wav, args)
    texts = []
    sent = 0.0
    previous = None
    for samples in segments:
        result = adapter.transcribe(config, phrase_wav(samples), "audio/wav", prompt=previous)
        sent += result.seconds_sent
        if result.text:
            texts.append(result.text)
            if context:
                previous = result.text
    return Variant(" ".join(texts), sent, len(segments))


def transcribe_phrases_with_context(config, data, wav, args):
    return transcribe_phrases(config, data, wav, args, context=True)


def segment_config(key, args):
    return adapter.Config(
        api_key=key,
        vocabulary=adapter.split_list(os.environ.get("VOXTYPE_GEMINI_VOCABULARY", "")),
        language_codes=adapter.split_list(os.environ.get("VOXTYPE_GEMINI_LANGUAGE_CODES", "")),
        timeout_secs=60,
        base_url=args.base_url,
        smart=adapter.smart_from_environ(os.environ),
        trim=adapter.TrimConfig(args.vad_model, args.max_silence_ms, args.pad_ms),
    )


def segment_rows(clip, key, args):
    """Returns (duration, [(label, Variant or error text, word diff vs whole or None)])."""
    data = clip.read_bytes()
    wav = silence.read_wav(data)
    if wav is None:
        raise ValueError("not a 16-bit PCM WAV")
    config = segment_config(key, args)
    variants = (
        ("whole", transcribe_whole),
        ("trimmed", transcribe_trimmed),
        ("phrases", transcribe_phrases),
        ("phrases+context", transcribe_phrases_with_context),
    )
    rows = []
    whole = None
    for label, fn in variants:
        result = attempt(fn, config, data, wav, args)
        if label == "whole":
            whole = result
        diff = None
        if label != "whole" and isinstance(result, Variant) and isinstance(whole, Variant):
            diff = word_diff(whole.text, result.text)
        rows.append((label, result, diff))
    return wav.seconds, rows


def cell(text):
    return " ".join(str(text).replace("|", "\\|").split())


def segment_main(args, key, clips):
    totals = {}
    covered = 0
    if args.markdown:
        print("| clip | variant | sent (s) | vs whole (words) | transcript |")
        print("|---|---|---|---|---|")
    for clip in clips:
        try:
            duration, rows = segment_rows(clip, key, args)
        except (OSError, ValueError) as err:
            duration, rows = None, [("", f"<error: {err}>", None)]
        if not args.markdown:
            print(f"== {clip.name}" + ("" if duration is None else f" ({duration:.1f}s)"))
        # a failed variant would skew the savings percentages, so such clips stay out of the totals
        if all(isinstance(result, Variant) for _, result, _ in rows):
            covered += 1
            for label, result, _ in rows:
                totals[label] = totals.get(label, 0.0) + result.sent
        for label, result, diff in rows:
            if not isinstance(result, Variant):
                if args.markdown:
                    print(f"| {cell(clip.name)} | {label or '-'} | - | - | {cell(result)} |")
                else:
                    print(f"  {label:<18} {result}" if label else f"  {result}")
                continue
            if args.markdown:
                vs = "-" if diff is None else diff
                print(f"| {cell(clip.name)} | {label} | {result.sent:.1f} | {vs} | {cell(result.text)} |")
                continue
            count = "" if result.n_phrases is None else f"{result.n_phrases} phrases  "
            print(f"  {label:<18} {result.sent:.1f}s  {count}{result.text}")
            if diff is not None:
                print(f"    diff vs whole: {diff} words")
    scope = f"{covered} of {len(clips)} clips, {len(clips) - covered} excluded"
    if not args.markdown:
        print(f"== totals (seconds sent; {scope})")
    for label, total in totals.items():
        share = f"{100 * total / totals['whole']:.0f}% of whole" if totals.get("whole") else "-"
        if args.markdown:
            print(f"| total ({scope}) | {label} | {total:.1f} | - | {share} |")
        else:
            print(f"  {label:<18} {total:.1f}s  {share}")


def main(argv=None):
    env = os.environ.get
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--key-file", default=env("VOXTYPE_GEMINI_KEY_FILE"))
    parser.add_argument("--segment", action="store_true", help="compare whole, trimmed, phrases and phrases+context instead of the engines")
    parser.add_argument("--base-url", default=env("VOXTYPE_GEMINI_BASE_URL", adapter.DEFAULT_BASE_URL), help="--segment only")
    parser.add_argument("--vad-model", default=env("VOXTYPE_GEMINI_VAD_MODEL"), help="--segment only; required there")
    parser.add_argument("--pause", type=float, default=float(env("VOXTYPE_GEMINI_PHRASE_PAUSE_SECS", 0.9)))
    parser.add_argument("--min-phrase", type=float, default=float(env("VOXTYPE_GEMINI_PHRASE_MIN_SECS", 1.5)))
    parser.add_argument("--hold", type=float, default=3.0)
    parser.add_argument("--max-silence-ms", type=int, default=int(env("VOXTYPE_GEMINI_SILENCE_MAX_MS", 300)))
    parser.add_argument("--pad-ms", type=int, default=int(env("VOXTYPE_GEMINI_SILENCE_PAD_MS", 200)))
    parser.add_argument("--markdown", action="store_true", help="--segment only: emit a Markdown table")
    parser.add_argument("dir", type=Path)
    args = parser.parse_args(argv)
    if not args.key_file:
        parser.error("--key-file or VOXTYPE_GEMINI_KEY_FILE required")
    if args.segment and not args.vad_model:
        parser.error("--vad-model (or VOXTYPE_GEMINI_VAD_MODEL) is required with --segment")
    key = Path(args.key_file).read_text().strip()

    clips = sorted(args.dir.glob("*.wav"))
    if not clips:
        sys.exit(f"no .wav clips in {args.dir}")
    if args.segment:
        segment_main(args, key, clips)
        return
    for clip in clips:
        print(f"== {clip.name}")
        for label, fn, fn_args in (
            ("Gemini Transcribe", gemini_transcribe, (key, clip)),
            (FLASH_LITE_MODEL, flash_verbatim, (key, clip, FLASH_LITE_MODEL, "minimal")),
            ("Parakeet (local)", parakeet, (clip,)),
            # gemini-3.8-flash cannot turn thinking off and rejects minimal, so low is its floor.
            (FLASH_3_8_MODEL, flash_verbatim, (key, clip, FLASH_3_8_MODEL, "low")),
        ):
            print(f"  {label:<24} {attempt(fn, *fn_args)}")


if __name__ == "__main__":
    main()

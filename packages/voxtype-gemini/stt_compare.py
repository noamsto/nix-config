"""Compare Gemini Transcribe, Gemini flash-lite and local Parakeet on a clip directory.

Clips should be 16 kHz mono WAV, the format voxtype records.
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

import adapter

FLASH_LITE_MODEL = "gemini-3.5-flash-lite"
FLASH_LITE_PROMPT = (
    "Transcribe this audio verbatim. The speech may mix Hebrew and English. "
    "Keep each word in the language it was spoken in; do not translate. "
    "Output only the transcript."
)


def gemini_transcribe(key, clip):
    config = adapter.Config(
        api_key=key,
        vocabulary=adapter.split_list(os.environ.get("VOXTYPE_GEMINI_VOCABULARY", "")),
        language_codes=adapter.split_list(os.environ.get("VOXTYPE_GEMINI_LANGUAGE_CODES", "")),
        timeout_secs=60,
    )
    return adapter.transcribe(config, clip.read_bytes(), "audio/wav")


def flash_lite(key, clip):
    return adapter.call_gemini(
        adapter.DEFAULT_BASE_URL,
        key,
        60,
        FLASH_LITE_MODEL,
        [
            {"type": "text", "text": FLASH_LITE_PROMPT},
            adapter.audio_part(clip.read_bytes(), "audio/wav"),
        ],
        {"thinking_level": "minimal"},
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key-file", default=os.environ.get("VOXTYPE_GEMINI_KEY_FILE"))
    parser.add_argument("dir", type=Path)
    args = parser.parse_args()
    if not args.key_file:
        parser.error("--key-file or VOXTYPE_GEMINI_KEY_FILE required")
    key = Path(args.key_file).read_text().strip()

    clips = sorted(args.dir.glob("*.wav"))
    if not clips:
        sys.exit(f"no .wav clips in {args.dir}")
    for clip in clips:
        print(f"== {clip.name}")
        for label, fn, fn_args in (
            ("Gemini Transcribe", gemini_transcribe, (key, clip)),
            (FLASH_LITE_MODEL, flash_lite, (key, clip)),
            ("Parakeet (local)", parakeet, (clip,)),
        ):
            print(f"  {label:<24} {attempt(fn, *fn_args)}")


if __name__ == "__main__":
    main()

{
  lib,
  writeShellApplication,
  fetchzip,
  sherpa-onnx,
  wtype,
  libnotify,
  coreutils,
  util-linux,
  gnused,
  silero-vad,
  voxtype-gemini,
  # null, or {url, pauseSecs, minSecs}
  geminiPhrases ? null,
}: let
  asrModel = fetchzip {
    url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2";
    hash = "sha256-L8nTk6JQ4IafAC3vostdnMVGlvZn9yN/BtmJtZzvI0k=";
  };
in
  writeShellApplication {
    name = "sherpa-dictate";
    runtimeInputs = [sherpa-onnx wtype libnotify coreutils util-linux gnused] ++ lib.optional (geminiPhrases != null) voxtype-gemini;

    # sherpa-onnx's ALSA layer rejects the PipeWire PCM's hw_params outright
    # ("Operation not permitted"); the plug: wrapper converts for it, which
    # keeps capture on PipeWire's default source instead of pinning a card
    # number that shifts when devices come and go.
    text =
      ''
        VAD_MODEL="${silero-vad}"
        MODEL_DIR="${asrModel}"
        DEVICE="plug:default"
        GEMINI_URL="${lib.optionalString (geminiPhrases != null) geminiPhrases.url}"
        PHRASE_PAUSE="${lib.optionalString (geminiPhrases != null) (toString geminiPhrases.pauseSecs)}"
        PHRASE_MIN="${lib.optionalString (geminiPhrases != null) (toString geminiPhrases.minSecs)}"
      ''
      + builtins.readFile ./sherpa-dictate.sh;

    meta = {
      description = "VAD-segmented streaming dictation: Silero VAD cuts at silence, Parakeet TDT transcribes, wtype types";
      mainProgram = "sherpa-dictate";
    };
  }

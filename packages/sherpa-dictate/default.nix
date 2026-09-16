{
  writeShellApplication,
  fetchurl,
  fetchzip,
  sherpa-onnx,
  wtype,
  libnotify,
  coreutils,
  util-linux,
}: let
  vadModel = fetchurl {
    url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx";
    hash = "sha256-niRJ4Qh0ltjUyrqQfyPgvT942R+lUkebucI6wJy7H9Y=";
  };

  asrModel = fetchzip {
    url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8.tar.bz2";
    hash = "sha256-3zMIAaTYBJZB8rXgaxHZdgBqBbrrLLN7USLH+JNTaDY=";
  };
in
  writeShellApplication {
    name = "sherpa-dictate";
    runtimeInputs = [sherpa-onnx wtype libnotify coreutils util-linux];

    # sherpa-onnx's ALSA layer rejects the PipeWire PCM's hw_params outright
    # ("Operation not permitted"); the plug: wrapper converts for it, which
    # keeps capture on PipeWire's default source instead of pinning a card
    # number that shifts when devices come and go.
    text =
      ''
        VAD_MODEL="${vadModel}"
        MODEL_DIR="${asrModel}"
        DEVICE="plug:default"
      ''
      + builtins.readFile ./sherpa-dictate.sh;

    meta = {
      description = "VAD-segmented streaming dictation: Silero VAD cuts at silence, Parakeet TDT transcribes, wtype types";
      mainProgram = "sherpa-dictate";
    };
  }

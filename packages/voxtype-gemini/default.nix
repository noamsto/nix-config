{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
  espeak-ng,
  silero-vad,
  alsa-utils,
  wtype,
  libnotify,
}: let
  pyEnv = python3.withPackages (ps: [ps.sherpa-onnx ps.numpy]);
in
  stdenvNoCC.mkDerivation {
    pname = "voxtype-gemini";
    version = "0.1.0";

    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./adapter.py
        ./test_adapter.py
        ./silence.py
        ./test_silence.py
        ./phrases.py
        ./test_phrases.py
        ./test_phrases_cli.py
        ./test_compare.py
        ./testclips.py
        ./stt_compare.py
      ];
    };

    nativeBuildInputs = [makeWrapper];
    nativeCheckInputs = [pyEnv espeak-ng];

    doCheck = true;
    checkPhase = ''
      runHook preCheck
      export VOXTYPE_GEMINI_VAD_MODEL=${silero-vad}
      python3 -m unittest -v test_adapter test_silence test_phrases test_phrases_cli test_compare
      runHook postCheck
    '';

    installPhase = ''
      runHook preInstall
      install -Dm444 adapter.py silence.py phrases.py stt_compare.py -t $out/libexec/voxtype-gemini
      makeWrapper ${pyEnv}/bin/python3 $out/bin/voxtype-gemini-adapter \
        --add-flags $out/libexec/voxtype-gemini/adapter.py \
        --set PYTHONPATH $out/libexec/voxtype-gemini \
        --set-default VOXTYPE_GEMINI_VAD_MODEL ${silero-vad}
      makeWrapper ${pyEnv}/bin/python3 $out/bin/voxtype-stt-compare \
        --add-flags $out/libexec/voxtype-gemini/stt_compare.py \
        --set PYTHONPATH $out/libexec/voxtype-gemini \
        --set-default VOXTYPE_GEMINI_VAD_MODEL ${silero-vad}
      makeWrapper ${pyEnv}/bin/python3 $out/bin/voxtype-gemini-phrases \
        --add-flags $out/libexec/voxtype-gemini/phrases.py \
        --set PYTHONPATH $out/libexec/voxtype-gemini \
        --set-default VOXTYPE_GEMINI_VAD_MODEL ${silero-vad} \
        --prefix PATH : ${lib.makeBinPath [alsa-utils wtype libnotify]}
      runHook postInstall
    '';

    meta = {
      description = "OpenAI-compatible transcription adapter for voxtype backed by Gemini Transcribe, plus an STT comparison tool";
      mainProgram = "voxtype-gemini-adapter";
      platforms = lib.platforms.linux;
    };
  }

{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
}:
stdenvNoCC.mkDerivation {
  pname = "voxtype-gemini";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./adapter.py
      ./test_adapter.py
      ./stt_compare.py
    ];
  };

  nativeBuildInputs = [makeWrapper];
  nativeCheckInputs = [python3];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python3 -m unittest -v test_adapter
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm444 adapter.py stt_compare.py -t $out/libexec/voxtype-gemini
    makeWrapper ${python3}/bin/python3 $out/bin/voxtype-gemini-adapter \
      --add-flags $out/libexec/voxtype-gemini/adapter.py \
      --set PYTHONPATH $out/libexec/voxtype-gemini
    makeWrapper ${python3}/bin/python3 $out/bin/voxtype-stt-compare \
      --add-flags $out/libexec/voxtype-gemini/stt_compare.py \
      --set PYTHONPATH $out/libexec/voxtype-gemini
    runHook postInstall
  '';

  meta = {
    description = "OpenAI-compatible transcription adapter for voxtype backed by Gemini Transcribe, plus an STT comparison tool";
    mainProgram = "voxtype-gemini-adapter";
    platforms = lib.platforms.linux;
  };
}

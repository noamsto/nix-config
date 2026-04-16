{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  zstd,
  zlib,
  openssl,
}:
stdenv.mkDerivation rec {
  pname = "lemonade";
  version = "10.2.0";

  src = fetchurl {
    url = "https://github.com/lemonade-sdk/lemonade/releases/download/v${version}/lemonade-embeddable-${version}-ubuntu-x64.tar.gz";
    hash = "sha256-3YNcK4V+izK2lmNBOAt4EPGX0oNARw3sY3r07DE3NYQ=";
  };

  nativeBuildInputs = [autoPatchelfHook];

  buildInputs = [
    stdenv.cc.cc.lib # libstdc++
    zstd
    zlib
    openssl
  ];

  sourceRoot = "lemonade-embeddable-${version}-ubuntu-x64";

  installPhase = ''
    mkdir -p $out/bin

    install -m755 lemonade $out/bin/lemonade
    install -m755 lemond $out/bin/lemond

    # lemond expects resources/ as a sibling of the binary
    cp -r resources $out/bin/resources
    cp LICENSE $out/bin/
  '';

  meta = with lib; {
    description = "Local AI server with OpenAI-compatible API for NPU/GPU inference";
    homepage = "https://github.com/lemonade-sdk/lemonade";
    license = licenses.mit;
    maintainers = [];
    platforms = ["x86_64-linux"];
    mainProgram = "lemonade";
  };
}

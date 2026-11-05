{
  stdenv,
  fetchurl,
  unzip,
  lib,
}:
# Upstream ships only a single release zip holding prebuilt binaries for every
# platform; we install the two static x86_64-linux ones (no autoPatchelf needed).
stdenv.mkDerivation rec {
  pname = "airconnect";
  version = "1.10.1";

  src = fetchurl {
    url = "https://github.com/philippe44/AirConnect/releases/download/${version}/AirConnect-${version}.zip";
    hash = "sha256-6g/a16GuuDfumbLCGq1+TDzoTeA8LoasZL7YBLh1iLA=";
  };

  nativeBuildInputs = [unzip];

  # The zip extracts flat (no top-level directory).
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 aircast-linux-x86_64-static $out/bin/aircast
    install -Dm755 airupnp-linux-x86_64-static $out/bin/airupnp
    runHook postInstall
  '';

  meta = {
    description = "Bridge exposing UPnP/Sonos & Chromecast devices as AirPlay receivers";
    homepage = "https://github.com/philippe44/AirConnect";
    license = lib.licenses.mit;
    platforms = ["x86_64-linux"];
    mainProgram = "airupnp";
  };
}

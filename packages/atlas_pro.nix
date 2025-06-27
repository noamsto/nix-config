{pkgs ? import <nixpkgs> {}, ...}: let
  arch = with pkgs.stdenv.hostPlatform;
    if isx86_64
    then "amd64"
    else if isAarch64
    then "arm64"
    else throw "Unsupported architecture: ${pkgs.stdenv.hostPlatform.system}";
  plat =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "darwin"
    else "linux";

  version = "0.35.0";

  hashes = {
    "amd64-linux" = "sha256-vnAp1hb5tl6WUORy5gmlQKnXWWSg5liiJvAu7i7FwKc=";
    "arm64-linux" = "sha256-aoym+muvy7MnKmfGKajZnOjYa+QZmCRhytQdzpblTZc=";
    "amd64-darwin" = "sha256-ozREhTs0XSfO0gxlFHT4JF4VeI7GJ3r8+p4/1ULq1u4=";
    "arm64-darwin" = "sha256-httLSr7kWWnAb+Sgo0Z0yFPfMWrDpZro0H4pasbONcw=";
  };
in
  pkgs.stdenv.mkDerivation rec {
    pname = "atlas";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://release.ariga.io/atlas/atlas-${plat}-${arch}-v${version}";
      hash = hashes."${arch}-${plat}";
      executable = true;
    };

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/atlas
      chmod +x $out/bin/atlas
    '';

    meta = with pkgs.lib; {
      description = "Atlas CLI - Manage your database schemas with Atlas";
      homepage = "https://atlasgo.io";
      license = licenses.asl20;
      maintainers = [];
      platforms = platforms.unix;
    };
  }

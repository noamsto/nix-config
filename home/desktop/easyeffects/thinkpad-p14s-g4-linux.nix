{
  pkgs ? import <nixpkgs> {},
  easyeffects_config_home ? "~/.config/easyeffects", # Default only for testing
}:
pkgs.stdenv.mkDerivation (finalAttrs: {
  pname = "thinkpad-p14s-g4-linux";
  version = "04.19";
  src = pkgs.fetchFromGitHub {
    owner = "m4tx";
    repo = "thinkpad-p14s-g4-linux";
    rev = "182b476d2966de5f0d9ac05a2f0514928660a7c7";
    sha256 = "sha256-PdpY7eRkWaDazQZoGh8pB4ejf0GqpEKAygd8YaC9B+Q=";
  };

  installPhase = ''
    mkdir -p $out
    cp -R ./* $out/

    substituteInPlace "$out/easyeffects/ThinkPad P14s G4.json" \
                       --replace "<PRESETS_DIRECTORY>" "${easyeffects_config_home}"
  '';
})

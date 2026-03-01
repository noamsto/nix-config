{
  pkgs ? import <nixpkgs> {},
  easyeffects_config_home ? "~/.config/easyeffects", # Default only for testing
}:
pkgs.stdenv.mkDerivation (_finalAttrs: {
  pname = "thinkpad-p14s-g5-linux";
  version = "2024.07.12";
  src = pkgs.fetchFromGitHub {
    owner = "kikislater";
    repo = "thinkpad-p14s-g5-linux";
    rev = "4ef1d59668a0f03f84a2e99555df0e17ce2327a2";
    sha256 = "sha256-qLT5HAw9p+b9wHVjSdQppZ9h9D8L0RMXsyVP1SC4uJ4=";
  };

  installPhase = ''
    mkdir -p $out
    cp -R ./* $out/

    # Update preset paths for all Gen 5 configs
    for preset in "$out/easyeffects/"*.json; do
      substituteInPlace "$preset" \
        --replace "<PRESETS_DIRECTORY>" "${easyeffects_config_home}"
    done
  '';
})

{pkgs ? import <nixpkgs> {}}:
pkgs.stdenv.mkDerivation rec {
  name = "change-kanshi-profile";
  src = ./change-kanshi-profile.sh;

  # Disable the unpack phase
  dontUnpack = true;

  nativeBuildInputs = [pkgs.makeWrapper];

  buildInputs = with pkgs; [
    bash
    ripgrep
    kanshi
  ];

  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/$name
    chmod +x $out/bin/$name
    wrapProgram $out/bin/$name \
      --prefix PATH : ${pkgs.lib.makeBinPath buildInputs}
  '';
}

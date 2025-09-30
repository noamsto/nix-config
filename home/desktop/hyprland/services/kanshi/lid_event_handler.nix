{pkgs ? import <nixpkgs> {}}:
pkgs.stdenv.mkDerivation rec {
  name = "lid-event-handler";
  src = ./lid-event-handler.sh;

  # Disable the unpack phase
  dontUnpack = true;

  nativeBuildInputs = [pkgs.makeWrapper];

  buildInputs = with pkgs; [
    bash
    ripgrep
    kanshi
    glib # Provides gdbus for D-Bus monitoring
    hyprland
  ];

  installPhase = ''
    mkdir -p $out/bin
    cp $src $out/bin/$name
    chmod +x $out/bin/$name
    wrapProgram $out/bin/$name \
      --prefix PATH : ${pkgs.lib.makeBinPath buildInputs}
  '';
}

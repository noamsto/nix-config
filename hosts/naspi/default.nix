{inputs, ...}: {
  imports = [
    ../../options.nix
    "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
    ./hardware.nix
    ./system.nix
    ./xscript.nix
  ];

  # Configuration options
  desktop.mode = "none";
  machine.type = "server";
  profile = "personal";
}

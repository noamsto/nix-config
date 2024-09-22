{
  lib,
  inputs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../nixos
    ../../home
    ../../overlays
    ../../secrets
    ../../options.nix
    ./host_secrets.nix
  ];

  hostname = "thinkpad-p14s-g5";
  desktop.mode = lib.mkDefault "kde";
  machine.type = "laptop";
  email = "noam@factify.com";
  profile = "work";

  environment.shellAliases = {
    naspi-rebuild-switch = ''
      NIX_SSHOPTS="-A" nixos-rebuild --flake .#naspi --use-remote-sudo --build-host noams@naspi.local --target-host noams@naspi.local switch
    '';
  };
}

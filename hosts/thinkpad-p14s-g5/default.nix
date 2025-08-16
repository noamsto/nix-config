{lib, ...}: {
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
  desktop.mode = lib.mkDefault "hyprland";
  machine.type = "laptop";
  email = "noam@factify.com";
  profile = "work";

  # AMD Ryzen 7 PRO 8840HS: 16 cores, 54GB RAM
  nix.settings = {
    max-jobs = 4;
    cores = 4; # 4x4 = 16 threads total
    max-silent-time = 14400;
    timeout = 172800;
  };

  environment.shellAliases = {
    naspi-rebuild-switch = ''
      NIX_SSHOPTS="-A" nixos-rebuild --flake .#naspi --use-remote-sudo --build-host noams@naspi.local --target-host noams@naspi.local switch
    '';
  };
}

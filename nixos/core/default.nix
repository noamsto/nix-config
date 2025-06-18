{
  pkgs,
  config,
  ...
}: let
  isHypr = config.desktop.mode == "hyprland";
in {
  imports = [
    ./networking.nix
    ./nix.nix
    ./locale.nix
    ./bootloader.nix
    ./pc.nix
    ./users.nix
  ];

  users.defaultUserShell = pkgs.zsh;

  programs = {
    zsh.enable = true;
    dconf.enable = true;
    ssh.startAgent = !isHypr;
    nix-ld = {
      enable = true;
      libraries = with pkgs; [libgit2 sqlite];
    };

    nh = {
      enable = true;
      # weekly cleanup
      clean = {
        enable = true;
        extraArgs = "--keep-since 14d";
      };
      flake = "/home/noams/nix-config";
    };
  };

  security.polkit.enable = true;

  environment.shells = with pkgs; [zsh];

  services = {
    dbus.implementation = "broker";

    # Firmware updates
    fwupd.enable = true;

    # Trim SSD
    fstrim.enable = true;
    fstrim.interval = "daily";
  };

  system.activationScripts.binbash = {
    deps = ["binsh"];
    text = ''
      [ -f /bin/bash ] || ln -s /bin/sh /bin/bash
    '';
  };

  # For RaspberryPi 4 image generating
  boot.binfmt.emulatedSystems = ["aarch64-linux"];

  system.stateVersion = "23.05";
}

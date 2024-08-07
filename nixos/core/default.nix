{
  config,
  pkgs,
  ...
}: let
in {
  imports = [
    ./networking.nix
    ./nix.nix
    ./locale.nix
    ./bootloader.nix
    ./pc.nix
  ];

  users.defaultUserShell = pkgs.zsh;

  programs = {
    zsh.enable = true;
    dconf.enable = true;
    ssh.startAgent = true;
    nix-ld.enable = true;

    nh = {
      enable = true;
      # clean.enable = true;
      # clean.extraArgs = "--keep-since 4d --keep 3";
      flake = "/home/noams/nix-config";
    };
  };

  security.polkit.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.${config.username} = {
    isNormalUser = true;
    description = config.user-full-name;
    extraGroups = ["adbusers" "networkmanager" "wheel" "video"];
    hashedPasswordFile = config.age.secrets.noams_password.path;
  };

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

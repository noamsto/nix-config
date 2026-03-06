{
  lib,
  pkgs,
  inputs,
  ...
}: let
  # Import shared host configuration
  hostConfig = (import ../../lib/host-configs.nix).thinkpad-p14s-g5;
in {
  imports = [
    ./hardware-configuration.nix
    ../../nixos
    ../../home
    ../../overlays
    ../../secrets
    ../../options.nix
    ./host_secrets.nix
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  # Secure Boot with Lanzaboote
  boot = {
    initrd.systemd.enable = true; # Required for TPM unlock
    loader.systemd-boot.enable = lib.mkForce false; # Lanzaboote replaces systemd-boot
    lanzaboote = {
      enable = true;
      pkiBundle = "/etc/secureboot";
      autoGenerateKeys.enable = true;
      autoEnrollKeys.enable = true;
    };
  };

  environment.systemPackages = with pkgs; [
    sbctl # Secure boot key management
    tpm2-tools # TPM utilities
  ];

  # Import shared configuration
  inherit (hostConfig) hostname email profile;
  desktop.mode = lib.mkDefault hostConfig.desktop.mode;
  machine.type = hostConfig.machine.type;

  # Thinkfan configuration
  hardware.thinkpad.thinkfan = {
    enable = true;
    generation = "gen5";
  };

  # AMD Ryzen 7 PRO 8840HS: 16 cores, 54GB RAM
  nix.settings = {
    max-jobs = 4;
    cores = 4; # 4x4 = 16 threads total
    max-silent-time = 14400;
    timeout = 172800;
  };

  # Allow access to hardware monitoring and power interfaces for btop
  services.udev.extraRules = ''
    # Allow all users to read hardware monitoring (not sensitive data)
    SUBSYSTEM=="hwmon", KERNEL=="hwmon*", MODE="0644"

    # Allow access to power supply info (TDP, battery, etc)
    SUBSYSTEM=="power_supply", MODE="0644"

    # Allow access to RAPL (Running Average Power Limit) for power monitoring
    SUBSYSTEM=="powercap", MODE="0644"
  '';

  # Host-specific overrides can go here
}

{
  lib,
  pkgs,
  inputs,
  ...
}: let
  hostConfig = (import ../../lib/host-configs.nix).thinkpad-p14s-g6;
in {
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../nixos
    ../../home
    ../../overlays
    ../../secrets
    ../../options.nix
    inputs.disko.nixosModules.disko
    inputs.lanzaboote.nixosModules.lanzaboote
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-p14s-amd-gen6
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
    sbctl
    tpm2-tools
  ];

  # Import shared configuration
  inherit (hostConfig) hostname email profile;
  desktop.mode = lib.mkDefault hostConfig.desktop.mode;
  machine.type = hostConfig.machine.type;

  # Thinkfan configuration
  hardware.thinkpad.thinkfan = {
    enable = true;
    generation = "gen6";
  };

  # Btrfs swapfile for hibernate support
  # After install, run: sudo btrfs filesystem mkswapfile --size 32G /swap/swapfile
  # Then uncomment:
  # swapDevices = [{ device = "/swap/swapfile"; }];
  # boot.resumeDevice = "/dev/mapper/cryptroot";
  # boot.kernelParams = [ "resume_offset=<offset>" ];
  # Get offset with: sudo btrfs inspect-internal map-swapfile -r /swap/swapfile

  # Adjust cores/jobs to match actual CPU — Ryzen AI 300 series expected
  nix.settings = {
    max-jobs = 4;
    cores = 4;
    max-silent-time = 14400;
    timeout = 172800;
  };

  # Allow access to hardware monitoring for btop
  services.udev.extraRules = ''
    SUBSYSTEM=="hwmon", KERNEL=="hwmon*", MODE="0644"
    SUBSYSTEM=="power_supply", MODE="0644"
    SUBSYSTEM=="powercap", MODE="0644"
  '';
}

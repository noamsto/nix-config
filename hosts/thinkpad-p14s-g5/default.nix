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

    # Disable WLAN wakeup to prevent spurious wakes during s2idle (ath11k/GPP6 GPIO 18)
    # Must disable both the device and its parent PCI bridge
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x17cb", ATTR{device}=="0x1103", ATTR{power/wakeup}="disabled"
    ACTION=="add", SUBSYSTEM=="pci", KERNEL=="0000:00:02.2", ATTR{power/wakeup}="disabled"

    # Enable Wake-on-LAN (magic packet) on Realtek NIC at device add time.
    # Required for AMD PMC deepest sleep state — firmware quirk on this platform.
    # udev rule ensures WoL is set regardless of NM connection state (e.g. undocked).
    # See: https://wiki.archlinux.org/title/Lenovo_ThinkPad_P14s_(AMD)_Gen_5
    ACTION=="add", SUBSYSTEM=="net", KERNEL=="eth0", RUN+="${pkgs.ethtool}/bin/ethtool -s eth0 wol g"
  '';

  # Also tell NM to use magic-packet WoL when it manages the connection (docked).
  # The udev rule above handles the undocked case; this prevents NM from resetting WoL to disabled.
  networking.networkmanager.settings.connection."ethernet.wake-on-lan" = 64;
}

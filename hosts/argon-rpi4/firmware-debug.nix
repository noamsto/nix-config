# Firmware debugging utilities for Raspberry Pi 4
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Install firmware debugging tools
  environment.systemPackages = with pkgs; [
    # General utilities
    file
    hexdump
    tree

    # FAT32/VFAT tools
    dosfstools
    mtools

    # Raspberry Pi specific
    raspberrypi-eeprom # For bootloader updates

    # Text processing for config analysis
    jq
    yq
  ];

  # Create firmware monitoring script
  environment.etc."firmware-debug.sh" = {
    text = ''
      #!/usr/bin/env bash
      # Firmware partition debugging script

      FIRMWARE_PATH="/boot/firmware"

      echo "=== Raspberry Pi Firmware Debug Info ==="
      echo "Date: $(date)"
      echo "Kernel: $(uname -r)"
      echo

      echo "=== Firmware Partition Mount Info ==="
      mount | grep firmware
      df -h "$FIRMWARE_PATH"
      echo

      echo "=== Firmware Directory Structure ==="
      tree -a "$FIRMWARE_PATH" 2>/dev/null || ls -la "$FIRMWARE_PATH"
      echo

      echo "=== Boot Configuration ==="
      if [ -f "$FIRMWARE_PATH/config.txt" ]; then
        echo "--- config.txt ---"
        cat "$FIRMWARE_PATH/config.txt"
        echo
      fi

      if [ -f "$FIRMWARE_PATH/cmdline.txt" ]; then
        echo "--- cmdline.txt ---"
        cat "$FIRMWARE_PATH/cmdline.txt"
        echo
      fi

      echo "=== NixOS Boot Files ==="
      ls -la "$FIRMWARE_PATH"/*nixos* 2>/dev/null || echo "No NixOS-specific files found"
      echo

      echo "=== Boot Files by Date ==="
      ls -lat "$FIRMWARE_PATH" | head -20
      echo

      echo "=== Firmware File Sizes ==="
      du -sh "$FIRMWARE_PATH"/*
      echo

      echo "=== Recent Changes (if available) ==="
      find "$FIRMWARE_PATH" -type f -mtime -1 -exec ls -la {} \; 2>/dev/null
      echo

      echo "=== EEPROM Version ==="
      vcgencmd bootloader_version 2>/dev/null || echo "vcgencmd not available"
    '';
    mode = "0755";
  };

  # Systemd service to capture firmware state before/after rebuilds
  systemd.services.firmware-snapshot = {
    description = "Capture firmware state for debugging";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c 'mkdir -p /var/log/firmware-snapshots && /etc/firmware-debug.sh > /var/log/firmware-snapshots/firmware-state-$(date +%Y%m%d-%H%M%S).log'";
    };
  };

  # Create aliases for easy debugging
  environment.shellAliases = {
    firmware-debug = "/etc/firmware-debug.sh";
    firmware-ls = "ls -la /boot/firmware";
    firmware-tree = "tree -a /boot/firmware";
    firmware-config = "cat /boot/firmware/config.txt";
    firmware-cmdline = "cat /boot/firmware/cmdline.txt";
    firmware-space = "df -h /boot/firmware";
    firmware-changes = "find /boot/firmware -type f -mtime -1 -exec ls -la {} \\;";
  };

  # Optional: Enable firmware partition backup before rebuilds
  # Uncomment if you want automatic backups
  # systemd.services.firmware-backup = {
  #   description = "Backup firmware partition before changes";
  #   before = [ "nixos-rebuild.service" ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "${pkgs.bash}/bin/bash -c 'mkdir -p /var/backups/firmware && cp -r /boot/firmware/* /var/backups/firmware/backup-$(date +%Y%m%d-%H%M%S)/'";
  #   };
  # };

  # Ensure firmware partition is properly accessible
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = lib.mkDefault true;

  # Additional kernel parameters for debugging
  boot.kernelParams = [
    "console=ttyS1,115200" # Serial console for debugging
    "console=tty1" # Local console
  ];
}

{
  config,
  lib,
  pkgs,
  ...
}: {
  # Hardware-specific configuration for Raspberry Pi 4
  hardware = {
    raspberry-pi."4" = {
      apply-overlays-dtmerge.enable = true;
      fkms-3d.enable = true; # GPU support
    };

    deviceTree = {
      enable = true;
      filter = lib.mkDefault "*rpi-4-*.dtb";

      # Enable PWM overlay for pins 18,19
      overlays = [
        {
          name = "pwm-2chan";
          dtsFile = ./pwm-2chan.dts;
        }
      ];
    };

    # Enable redistributable firmware
    enableRedistributableFirmware = true;
  };

  # Boot configuration for RPi4
  boot = {
    # Kernel modules needed for RPi4
    initrd.availableKernelModules = ["xhci_pci" "usbhid" "usb_storage"];

    # Kernel parameters for audio support
    kernelParams = [
      "snd_bcm2835.enable_hdmi=1"
      "snd_bcm2835.enable_headphones=1"
    ];

    # Boot loader configuration for RPi4
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };
  };

  # File systems - standard layout for RPi4
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
    options = ["noatime"];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/FIRMWARE";
    fsType = "vfat";
    options = ["noatime"];
  };

  # Enable zram swap for RPi4
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
  };

  # SD Image configuration
  sdImage = {
    firmwareSize = 64; # MB - increase from default 30MB for RPi4 firmware + dtoverlays
    expandOnBoot = true; # Auto-expand root partition (default)
  };

  # Platform specification
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}

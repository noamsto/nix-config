{lib, ...}: {
  # Workaround for missing kernel modules issue on RPi4
  # See: https://github.com/NixOS/nixpkgs/issues/154163
  nixpkgs.overlays = [
    (final: super: {
      makeModulesClosure = x:
        super.makeModulesClosure (x // {allowMissing = true;});
    })
  ];
  # Hardware-specific configuration for Raspberry Pi 4
  hardware = {
    raspberry-pi."4" = {
      apply-overlays-dtmerge.enable = true;
      fkms-3d.enable = true; # GPU support
    };

    deviceTree = {
      enable = true;
      # Enable PWM overlay for pins 18,19
      overlays = [
        {
          name = "pwm-2chan";
          dtsFile = ./pwm-2chan.dts;
        }
      ];
    };
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
  };

  # File systems - standard layout for RPi4
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
    options = ["noatime"];
  };

  fileSystems."/boot/firmware" = {
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

  # Platform specification
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}

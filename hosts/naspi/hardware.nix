{nixos-raspberrypi, ...}: {
  imports = with nixos-raspberrypi.nixosModules; [
    ./configtxt.nix

    raspberry-pi-4.base
    raspberry-pi-4.display-vc4
  ];
  # # Hardware device tree configuration
  hardware.deviceTree = {
    # Filter to only include Raspberry Pi 4 device trees (speeds up build)
    # filter = "*rpi-4-*.dtb";

    # # Enable PWM 2-channel overlay (official Raspberry Pi implementation)
    # overlays = [
    #   {
    #     name = "pwm-2chan";
    #     dtsFile = ./pwm-2chan.dts;
    #   }
    # ];
  };

  boot.initrd.availableKernelModules = ["xhci_pci" "usbhid" "usb_storage" "nvme"];
  hardware.enableRedistributableFirmware = true;

  fileSystems = {
    "/boot/firmware" = {
      device = "/dev/disk/by-label/FIRMWARE";
      fsType = "vfat";
      options = [
        "noatime"
        "noauto"
        "x-systemd.automount"
        "x-systemd.idle-timeout=1min"
      ];
    };
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      options = ["noatime"];
    };
  };
}

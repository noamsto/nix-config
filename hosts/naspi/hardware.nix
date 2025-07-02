{pkgs, ...}: {
  imports = [
    ./configtxt.nix
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

  boot.loader = {
    grub.enable = false;
    generic-extlinux-compatible.enable = true;
  };

  boot.initrd.availableKernelModules = ["xhci_pci" "usbhid" "usb_storage"];
  boot.kernelPackages = pkgs.linuxKernel.packages.linux_rpi4;
  hardware.enableRedistributableFirmware = true;

  # Root filesystem
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };
}

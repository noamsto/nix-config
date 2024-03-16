{
  pkgs,
  config,
  lib,
  ...
}: {
  # This causes an overlay which causes a lot of rebuilding
  environment.noXlibs = lib.mkForce false;
  # "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix" creates a
  # disk with this label on first boot. Therefore, we need to keep it. It is the
  # only information from the installer image that we need to keep persistent
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
    options = ["noatime"];
  };

  fileSystems."/mnt/main-ssd" = {
    device = "/dev/disk/by-uuid/d19f513e-ec59-4807-94ce-942f6f711a3e";
    fsType = "ext4";
    options = ["noatime"];
  };

  boot = {
    kernelPackages = pkgs.linuxKernel.packages.linux_rpi4;

    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };
  };

  environment.shellAliases = {
    raspi-cpu = ''
      sudo vcgencmd get_throttled && sudo vcgencmd measure_temp
    '';
    raspi-firmware-update = ''
      sudo mkdir -p /mnt && \
      sudo mount /dev/disk/by-label/FIRMWARE /mnt && \
      BOOTFS=/mnt FIRMWARE_RELEASE_STATUS=stable sudo -E rpi-eeprom-update -d -a && \
      sudo umount /mnt
    '';
    xoff = ''sudo x-c1-softsd.sh 3'';

    xreboot = ''sudo x-c1-softsd.sh 1'';
  };

  nix.settings = {
    experimental-features = lib.mkDefault "nix-command flakes";
    trusted-users = ["root" "@wheel"];
  };
}

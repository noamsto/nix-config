# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{hostname, ...}: {
  imports = [
    ../../nixos/core.nix
    ../../nixos/kde.nix
    ../../nixos/docker
    ../../nixos/tailscale
    ../../nixos/xremap
    # ../../nixos/access
    ./barracuda_secrets.nix
  ];

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot/efi";
  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
    enableCryptodisk = true;
    useOSProber = true;
  };

  boot.initrd = {
    luks.devices."root" = {
      device = "/dev/disk/by-uuid/ff066183-b3a3-43f3-af0b-515d1e80155f"; # UUID for /dev/nvme01np2
      preLVM = true;
      keyFile = "/keyfile0.bin";
      allowDiscards = true;
    };
    secrets = {
      # Create /mnt/etc/secrets/initrd directory and copy keys to it
      # Reference: https://gist.github.com/ladinu/bfebdd90a5afd45dec811296016b2a3f
      "keyfile0.bin" = "/etc/secrets/initrd/keyfile0.bin";
    };
  };

  environment.shellAliases = {
    nix-rebuild-host = ''
      sudo nixos-rebuild switch  --flake .#${hostname}
    '';

    nix-rebuild-host-debug = ''
      sudo nixos-rebuild build  --flake  .#${hostname} --show-trace  --option eval-cache false
    '';
    naspi-rebuild-switch = ''
      NIX_SSHOPTS="-A" nixos-rebuild --flake .#naspi --use-remote-sudo --build-host noams@naspi.local --target-host noams@naspi.local switch
    '';
  };
}

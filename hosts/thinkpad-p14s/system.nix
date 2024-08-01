# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{hostname, ...}: {
  imports = [
    ../../nixos/core.nix
    ../../nixos/kde.nix
    ../../nixos/docker
    ../../nixos/tailscale
    ../../nixos/xremap
    ../../nixos/notes
    # ./host_secrets.nix
  ];
  boot.loader.efi.canTouchEfiVariables = true;

  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
    useOSProber = true;
    fontSize = 36;
  };

  boot.initrd = {
    luks.devices.root = {
      device = "/dev/disk/by-uuid/4982a096-bf14-47a7-8f14-1e7b7c63f2d4"; # UUID for /dev/nvme01np5
      allowDiscards = true;
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

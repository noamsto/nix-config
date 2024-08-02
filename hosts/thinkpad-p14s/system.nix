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
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.luks.devices = {
      root = {
        # Use https://nixos.wiki/wiki/Full_Disk_Encryption
        device = "/dev/disk/by-uuid/a93bff25-8164-4b2f-ae87-19311112c84c";
        preLVM = true;
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

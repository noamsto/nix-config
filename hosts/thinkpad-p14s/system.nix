# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{...}: {
  imports = [
    ../../nixos/desktop-kde.nix
    # ./host_secrets.nix
  ];

  #TODO:
  # Maybe define here The default username and hostname
  # Also, define if a desktop or Server, Laptop or not
  hostname = "thinkpad-p14s";

  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 12;
    };
    efi.canTouchEfiVariables = true;
  };

  environment.shellAliases = {
    naspi-rebuild-switch = ''
      NIX_SSHOPTS="-A" nixos-rebuild --flake .#naspi --use-remote-sudo --build-host noams@naspi.local --target-host noams@naspi.local switch
    '';
  };
}

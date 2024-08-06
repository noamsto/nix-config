{...}: {
  imports = [
    ./hardware-configuration.nix
    ../../nixos
    ../../home
    ../../overlays
    ../../secrets
    ../../options.nix
    # ./host_secrets.nix
  ];

  #TODO:
  # Maybe define here The default username and hostname
  # Also, define if a desktop or Server, Laptop or not
  hostname = "thinkpad-p14s";
  desktop.mode = "kde";

  environment.shellAliases = {
    naspi-rebuild-switch = ''
      NIX_SSHOPTS="-A" nixos-rebuild --flake .#naspi --use-remote-sudo --build-host noams@naspi.local --target-host noams@naspi.local switch
    '';
  };
}

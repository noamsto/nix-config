# Shared shell aliases for all hosts
# Dynamically generates aliases based on available configurations
_: {
  environment.shellAliases = {
    # Remote Pi rebuilds
    naspi-rebuild-switch = ''
      NIX_SSHOPTS="-A" nixos-rebuild --flake .#naspi --use-remote-sudo --build-host noams@naspi.local --target-host noams@naspi.local switch
    '';
  };
}

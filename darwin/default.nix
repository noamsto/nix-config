{applyKeyed, ...}: {
  imports = [
    ../options.nix
    (applyKeyed ../overlays)
    # The one file under nixos/ that darwin shares: priors' trust file and binary.
    (applyKeyed ../nixos/core/priors.nix)
    (applyKeyed ./base.nix)
  ];
}

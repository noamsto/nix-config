{applyKeyed, ...}: {
  imports = [
    ../options.nix
    (applyKeyed ../overlays)
    (applyKeyed ./core)
    ./desktop
    ./hardware
    ./laptop
    ./packages.nix
    ./virtualization
    (applyKeyed ./xremap)
    ./hyprland
    (applyKeyed ./services)
  ];
}

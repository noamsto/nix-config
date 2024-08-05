{...}: {
  desktop.enable = true;
  imports = [
    ./core
    ./sddm
    ./kde.nix
    ./packages.nix
    ./docker
    ./xremap
  ];
}

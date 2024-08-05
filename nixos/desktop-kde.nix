{lib, ...}: {
  options = {
    isDesktop = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };
  imports = [
    ./core
    ./sddm
    ./kde.nix
    ./packages.nix
    ./docker
    ./xremap
  ];
}

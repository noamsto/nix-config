_: {
  systems = ["x86_64-linux"];

  perSystem = {pkgs, ...}: {
    packages = {
      atlas-pro = pkgs.callPackage ./atlas_pro.nix {inherit pkgs;};
      claude-squad = pkgs.callPackage ./claude-squad {};
      hyprvoice = pkgs.callPackage ./hyprvoice.nix {};
    };
  };
}

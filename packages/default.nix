{
  systems = ["x86_64-linux"];

  perSystem = {pkgs, ...}: {
    packages = {
      atlas-pro = pkgs.callPackage ./atlas_pro.nix {inherit pkgs;};
    };
  };
}

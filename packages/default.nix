{
  systems = ["x86_64-linux"];

  perSystem = {pkgs, ...}: {
    packages = {
      aicommit2 = pkgs.callPackage ./aicommit2 {};
      atlas-pro = pkgs.callPackage ./atlas_pro.nix {inherit pkgs;};
    };
  };
}

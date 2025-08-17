{
  systems = ["x86_64-linux" "aarch64-linux"];

  perSystem = {pkgs, ...}: {
    packages = {
      # Check if atlas-pro supports current architecture
      atlas-pro = pkgs.callPackage ./atlas_pro.nix {inherit pkgs;};
    };
  };
}

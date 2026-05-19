{inputs, ...}: {
  systems = ["x86_64-linux"];

  perSystem = {pkgs, ...}: let
    pkgsUnfree = import inputs.nixpkgs {
      inherit (pkgs.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };
  in {
    packages = {
      atlas-pro = pkgs.callPackage ./atlas_pro.nix {inherit pkgs;};
      claude-squad = pkgs.callPackage ./claude-squad {};
      hyprvoice = pkgs.callPackage ./hyprvoice.nix {};
      sentinelone = pkgsUnfree.callPackage ./sentinelone {};
    };
  };
}

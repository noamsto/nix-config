{
  inputs,
  lib,
  ...
}: {
  perSystem = {pkgs, ...}: let
    pkgsUnfree = import inputs.nixpkgs {
      inherit (pkgs.stdenv.hostPlatform) system;
      config.allowUnfree = true;
    };
  in {
    # All Linux-only (Hyprland voice, SentinelOne agent, …). Guarding them keeps
    # `packages.aarch64-darwin` empty, so adding aarch64-darwin to the flake's
    # `systems` (for the darwin devShell) doesn't try to build them on macOS.
    packages = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      airconnect = pkgs.callPackage ./airconnect.nix {};
      atlas-pro = pkgs.callPackage ./atlas_pro.nix {inherit pkgs;};
      claude-squad = pkgs.callPackage ./claude-squad {};
      hyprvoice = pkgs.callPackage ./hyprvoice.nix {};
      sentinelone = pkgsUnfree.callPackage ./sentinelone {};
    };
  };
}

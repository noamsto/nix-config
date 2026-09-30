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
    # linear-cli ships prebuilt binaries for both linux and darwin, and the pi
    # extensions are portable npm packages, so both live outside the Linux-only
    # guard below and build on every system.
    #
    # The rest are Linux-only (AirConnect, SentinelOne agent, …). Guarding them
    # keeps `packages.aarch64-darwin` from trying to build them on macOS.
    packages =
      {
        deja-vu = pkgs.callPackage ./deja-vu.nix {};
        gh-repo-defaults = pkgs.callPackage ./gh-repo-defaults {};
        linear-cli = pkgs.callPackage ./linear-cli.nix {};
        inherit (pkgs.callPackage ./pi-extensions {}) pi-lens pi-vim pi-web-access rpiv-todo;
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        airconnect = pkgs.callPackage ./airconnect.nix {};
        atlas-pro = pkgs.callPackage ./atlas_pro.nix {inherit pkgs;};
        claude-squad = pkgs.callPackage ./claude-squad {};
        halo-wlan0-suspend-repro = pkgs.callPackage ./halo-wlan0-suspend-repro {};
        sentinelone = pkgsUnfree.callPackage ./sentinelone {};
        sherpa-dictate = pkgs.callPackage ./sherpa-dictate {};
      };
  };
}

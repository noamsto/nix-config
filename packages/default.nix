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
    # linear-cli ships prebuilt binaries for both linux and darwin, so it lives
    # outside the Linux-only guard below and builds on every system.
    #
    # The rest are Linux-only (AirConnect, SentinelOne agent, …). Guarding
    # them keeps `packages.aarch64-darwin` empty, so adding aarch64-darwin to the
    # flake's `systems` (for the darwin devShell) doesn't try to build them on macOS.
    packages =
      {
        gh-repo-defaults = pkgs.callPackage ./gh-repo-defaults {};
        linear-cli = pkgs.callPackage ./linear-cli.nix {};
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        airconnect = pkgs.callPackage ./airconnect.nix {};
        atlas-pro = pkgs.callPackage ./atlas_pro.nix {inherit pkgs;};
        claude-squad = pkgs.callPackage ./claude-squad {};
        halo-wlan0-suspend-repro = pkgs.callPackage ./halo-wlan0-suspend-repro {};
        inherit (pkgs.callPackage ./pi-extensions {}) pi-lens pi-vim pi-web-access rpiv-todo;
        sentinelone = pkgsUnfree.callPackage ./sentinelone {};
        sherpa-dictate = pkgs.callPackage ./sherpa-dictate {};
      };
  };
}

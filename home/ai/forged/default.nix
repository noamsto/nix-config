# forged's module defines systemd user units, which Home Manager only
# supports on Linux (modules/systemd.nix asserts it). macOS gets the CLI only,
# no daemon: there is no launchd agent for it yet.
{inputs, ...}: {
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (pkgs.stdenv.hostPlatform) isDarwin isLinux;
in {
  imports = [inputs.forged.homeManagerModules.default];

  services.forged.enable = isLinux;
  home.packages = lib.optional isDarwin config.services.forged.package;
}

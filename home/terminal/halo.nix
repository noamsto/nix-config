{
  lib,
  osConfig,
  pkgs,
  ...
}: let
  halo = pkgs.writeShellApplication {
    name = "halo";
    runtimeInputs = with pkgs; [openssh git nixos-rebuild-ng coreutils];
    runtimeEnv.FLAKE = osConfig.flakePath;
    text = builtins.readFile ./halo.sh;
  };
in {
  home.packages = lib.optionals (osConfig.hostname != "halo") [halo];
}

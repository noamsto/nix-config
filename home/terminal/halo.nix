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
  isHalo = osConfig.hostname == "halo";
in {
  home.packages = lib.optionals (!isHalo) [halo];
  xdg.configFile."fish/completions/halo.fish" = lib.mkIf (!isHalo) {
    source = import ./halo-completions.nix {
      inherit pkgs;
      command = "halo";
      flake = osConfig.flakePath;
    };
  };
}

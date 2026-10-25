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
  isLocalServer = osConfig.nix-config.ai.localServer.enable;
in {
  home.packages = lib.optionals (!isLocalServer) [halo];
  xdg.configFile."fish/completions/halo.fish" = lib.mkIf (!isLocalServer) {
    source = import ./halo-completions.nix {
      inherit pkgs;
      command = "halo";
      flake = osConfig.flakePath;
    };
  };
}

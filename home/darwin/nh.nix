{
  lib,
  pkgs,
  osConfig,
  ...
}:
# On macOS, home-manager is a nix-darwin module (not a standalone
# homeConfigurations output), so the rebuild command is `nh darwin switch`, not
# `nh home switch`. Enabling programs.nh here sets NH_FLAKE to the repo path so
# `nh darwin switch` (and `nh os`/`nh home`) work with no flake argument.
lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
  programs.nh = {
    enable = true;
    flake = osConfig.flakePath; # /Users/<user>/nix-config → exports NH_FLAKE
  };
}

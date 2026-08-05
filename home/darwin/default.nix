{
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./aerospace.nix
    ./karabiner.nix
    ./nh.nix
    ./xcodebuildmcp.nix
  ];

  # GUI apps not covered by Homebrew casks. pear-desktop (Electron YouTube Music
  # wrapper) has no matching cask but a working aarch64-darwin build; AeroSpace
  # binds Hyper+Y to launch it, mirroring the Hyprland $mainMod+Y bind.
  home.packages = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin [pkgs.pear-desktop];

  # NOTE: trust.json is no longer managed here. Homebrew 6.0's `brew bundle`
  # self-grants trust (the Brewfile marks entries `trusted: true`) and *writes*
  # ~/.config/homebrew/trust.json plus a `.lock` sibling, so a read-only store
  # symlink at that path would make brew abort with `Permission denied`. brew
  # owns the file now; activation points XDG_CONFIG_HOME here too — see
  # hosts/mbp-m4-pro/default.nix.
}

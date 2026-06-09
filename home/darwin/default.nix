{
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./aerospace.nix
    ./karabiner.nix
    ./nh.nix
  ];

  # GUI apps not covered by Homebrew casks. pear-desktop (Electron YouTube Music
  # wrapper) has no matching cask but a working aarch64-darwin build; AeroSpace
  # binds Hyper+Y to launch it, mirroring the Hyprland $mainMod+Y bind.
  home.packages = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin [pkgs.pear-desktop];
}

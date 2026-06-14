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

  # Homebrew 6.0 Tap Trust: the interactive-shell copy of the trust list, so a
  # manual `brew`/`brew bundle` (which reads $XDG_CONFIG_HOME/homebrew) also
  # loads swipeaerospace from the third-party mediosz/tap. The darwin activation
  # run uses a store-baked copy instead — see hosts/mbp-m4-pro/default.nix for
  # why (it runs before this file is written). Cask-scoped on purpose:
  # `trustedcasks` suffices because the tap is a non-git nix store dir, so its
  # `remote` is blank and `uses_custom_remote?` is false, keeping the per-cask
  # trust path active.
  xdg.configFile."homebrew/trust.json" = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    text = builtins.toJSON {trustedcasks = ["mediosz/tap/swipeaerospace"];};
  };
}

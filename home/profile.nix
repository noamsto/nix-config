{applyKeyed, ...}: {
  lib,
  pkgs,
  osConfig,
  ...
}: {
  imports =
    [
      (applyKeyed ./packages.nix)
      # Cross-platform theme module (palette color data + theme-toggle option).
      # Imported unconditionally so it's available on darwin too; the desktop
      # tree consumes the same palette for its GTK/catppuccin bits.
      ./theme
      ./desktop/youtube-music
      (applyKeyed ./terminal)
      ./xdg
      ./git
      (applyKeyed ./direnv)
      ./ssh
      ./checkout-check.nix
      (applyKeyed ./nvim)
      ./ipython
      (applyKeyed ./ai)
      (applyKeyed ./nix-tools)
      # Darwin-only config; self-gates with mkIf internally (referencing pkgs in
      # `imports` would infinite-recurse, so it can't be a lib.optionals guard).
      ./darwin
      # Self-gates: Firefox on darwin, desktop hosts on Linux.
      ./firefox
    ]
    ++ lib.optionals (osConfig.desktop.mode != "none") [
      (applyKeyed ./desktop)
    ];

  home = {
    inherit (osConfig) username;
    homeDirectory =
      if pkgs.stdenv.hostPlatform.isDarwin
      then "/Users/${osConfig.username}"
      else "/home/${osConfig.username}";
    stateVersion = "23.05";

    # HM master labels its release ahead of nixpkgs-unstable, so the version
    # check warns spuriously on this unstable-tracking setup.
    enableNixpkgsReleaseCheck = false;

    # NOTE: Chromium's own flags live in programs.chromium.commandLineArgs
    # (home/desktop/default.nix), since the nixpkgs wrapper does not read
    # CHROMIUM_USER_FLAGS. The env var set in
    # home/desktop/hyprland/settings/default.nix only reaches other Chromium-based
    # browsers (Chrome, Edge, Vivaldi) started from the Hyprland session.
  };

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}

{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}: {
  imports =
    [
      ./packages.nix
      # Theme palette (pure color data) — provides config.theme.palette, which
      # the cross-platform terminal modules (kitty, ghostty, btop, …) consume.
      # Imported unconditionally so it's available on darwin too; the desktop
      # tree re-imports the same path (deduped) for its GTK/catppuccin bits.
      ./desktop/theme/palette.nix
      ./terminal
      ./xdg
      ./git
      ./direnv
      ./ssh
      ./nvim
      ./ipython
      ./ai
      ./nix-tools
    ]
    ++ lib.optionals (osConfig.desktop.mode != "none") [
      ./desktop
      ./flatpak.nix
    ]
    ++ lib.optionals (osConfig.profile == "work") [
      ./kubernetes
      ./work
    ];

  home = {
    inherit (osConfig) username;
    homeDirectory =
      if pkgs.stdenv.hostPlatform.isDarwin
      then "/Users/${osConfig.username}"
      else "/home/${osConfig.username}";
    stateVersion = "23.05";

    # NOTE: Chromium-based browser flags (Brave, Chromium, Chrome, Edge, Vivaldi)
    # are configured in home/desktop/hyprland/settings/default.nix as Hyprland env variables:
    # - BRAVE_USER_FLAGS
    # - CHROMIUM_USER_FLAGS
    # This ensures flags are available to all processes launched in the Hyprland session,
    # including applications started from launchers like Vicinae.
  };

  # FlakeHub authentication (symlink to agenix-managed secret).
  # Linux only: /run/agenix doesn't exist on darwin — FlakeHub auth there is
  # handled by `determinate-nixd login`.
  xdg.configFile = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    "flakehub/auth".source = config.lib.file.mkOutOfStoreSymlink "/run/agenix/noams_flakehub";
  };

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}

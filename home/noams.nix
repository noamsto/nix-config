{
  lib,
  osConfig,
  ...
}: {
  imports =
    [
      ./packages.nix
      ./terminal
      ./xdg
      ./git
      ./direnv
      ./ssh
      ./nvim
      ./ipython
      ./ai
    ]
    ++ lib.optionals (osConfig.desktop.mode != "none") [
      ./desktop
    ]
    ++ lib.optionals (osConfig.profile == "work") [
      ./kubernetes
    ];

  home = {
    username = osConfig.username;
    homeDirectory = "/home/${osConfig.username}";
    stateVersion = "23.05";

    # NOTE: Chromium-based browser flags (Brave, Chromium, Chrome, Edge, Vivaldi)
    # are configured in home/desktop/hyprland/settings/default.nix as Hyprland env variables:
    # - BRAVE_USER_FLAGS
    # - CHROMIUM_USER_FLAGS
    # This ensures flags are available to all processes launched in the Hyprland session,
    # including applications started from launchers like Vicinae/Walker.
  };

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}

{
  config,
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
    homeDirectory = "/home/${osConfig.username}";
    stateVersion = "23.05";

    # NOTE: Chromium-based browser flags (Brave, Chromium, Chrome, Edge, Vivaldi)
    # are configured in home/desktop/hyprland/settings/default.nix as Hyprland env variables:
    # - BRAVE_USER_FLAGS
    # - CHROMIUM_USER_FLAGS
    # This ensures flags are available to all processes launched in the Hyprland session,
    # including applications started from launchers like Vicinae.
  };

  # FlakeHub authentication (symlink to agenix-managed secret)
  xdg.configFile."flakehub/auth".source = config.lib.file.mkOutOfStoreSymlink "/run/agenix/noams_flakehub";

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}

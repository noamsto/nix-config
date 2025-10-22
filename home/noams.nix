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
      ./claude-code
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

    # Chromium-based browser fixes:
    # 1. --disable-accelerated-2d-canvas: Fix AMD Radeon 780M PDF rendering artifacts
    #    Upstream bug: https://issues.chromium.org/40184451
    # 2. --disable-features=WaylandWpColorManagerV1: Fix crashes when moving between monitors
    #    Upstream bug: Chrome 141 Wayland regression (fixed in main, Oct 2025)
    #    Issue: https://github.com/brave/brave-browser/issues/49921
    #    Discussion: https://github.com/hyprwm/Hyprland/discussions/11843
    # Affects: Chromium, Brave, Chrome, Edge, Vivaldi
    sessionVariables = {
      CHROMIUM_USER_FLAGS = "--disable-accelerated-2d-canvas --disable-features=WaylandWpColorManagerV1";
    };
  };

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}

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

    # Fix for AMD Radeon 780M canvas rendering artifacts in Chromium-based browsers
    # Affects: Chromium, Brave, Chrome, Edge, Vivaldi
    # Upstream bug: https://issues.chromium.org/40184451
    sessionVariables = {
      CHROMIUM_USER_FLAGS = "--disable-accelerated-2d-canvas";
    };
  };

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}

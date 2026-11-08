{applyKeyed, ...}: {
  osConfig,
  lib,
  ...
}: {
  imports =
    [
      (applyKeyed ./theme)
      ./easyeffects
      ./wireplumber
      ./bt-headset
      ./mpv.nix
      ./chromium-claude.nix
      ./kdenlive.nix
      ./obsidian.nix
    ]
    ++ lib.optionals (osConfig.desktop.mode == "hyprland") [
      (applyKeyed ./hyprland)
      (applyKeyed ./noctalia)
    ];

  # Hardware-accelerated video for Electron apps using system Electron
  # Apps with bundled Electron (Slack, etc.) get flags via overlays in lib/overlays.nix
  xdg.configFile."electron-flags.conf".text = ''
    --enable-features=VaapiVideoDecodeLinuxGL,VaapiVideoEncoder,VaapiIgnoreDriverChecks
    --enable-gpu-rasterization
    --enable-zero-copy
    --ignore-gpu-blocklist
  '';

  programs = {
    obs-studio.enable = true;

    chromium = {
      enable = true;
      commandLineArgs = [
        "--disable-features=WaylandWpColorManagerV1"
        # AMD Radeon 780M PDF rendering artifacts: https://issues.chromium.org/40184451
        "--disable-accelerated-2d-canvas"
      ];
    };
  };
}

{
  osConfig,
  lib,
  ...
}: {
  imports =
    [
      ./theme
      ./easyeffects
      ./wireplumber
      ./bt-headset
      ./mpv.nix
      ./kdenlive.nix
      ./obsidian.nix
    ]
    ++ lib.optionals (osConfig.desktop.mode == "hyprland") [
      ./hyprland
      ./noctalia
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

    brave = {
      enable = true;
      # NOTE: Command-line flags are applied via overlay in lib/overlays.nix
      # Also set via BRAVE_USER_FLAGS env var in Hyprland as a fallback
    };

    chromium = {
      enable = lib.mkIf (osConfig.profile == "work") true;
      commandLineArgs = [
        "--disable-features=WaylandWpColorManagerV1"
      ];
    };
  };
}

{
  osConfig,
  lib,
  pkgs,
  ...
}: {
  imports =
    [
      ./theme
      ./easyeffects
    ]
    ++ lib.optionals (osConfig.desktop.mode == "kde") [
      ./kde
    ]
    ++ lib.optionals (osConfig.desktop.mode == "hyprland") [
      ./hyprland
    ];
  programs = {
    obs-studio.enable = true;

    brave.nativeMessagingHosts = [
      pkgs.kdePackages.plasma-browser-integration
    ];

    firefox = {
      enable = true;
      package = pkgs.firefox.override {
        # See nixpkgs' firefox/wrapper.nix to check which options you can use
        nativeMessagingHosts = [
          pkgs.kdePackages.plasma-browser-integration
        ];
      };
    };
  };
}

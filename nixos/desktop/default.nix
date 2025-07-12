{
  pkgs,
  config,
  lib,
  ...
}: {
  imports = [
    ./sddm
    ./kde.nix
    ./1password
  ];

  programs = {
    zoom-us.enable = true;
    chromium.enable = true;
  };

  # Enable Qt system-wide for proper QML module resolution
  qt = {
    enable = true;
    platformTheme = "gnome";
    style = "adwaita-dark";
  };

  services = {
    # Enable flatpak
    flatpak.enable = true;
    libinput = lib.mkIf (config.machine.type == "laptop") {
      enable = true;
      touchpad = {
        naturalScrolling = true;
        tapping = true;
        disableWhileTyping = true;
      };
    };
  };

  services.xserver = {
    # Configure keymap in X11
    xkb.layout = "us,il";
    xkb.options = "compose:menu, grp:win_space_toggle";
  };

  xdg.portal.enable = true;

  specialisation = {
    hypr.configuration = {
      desktop.mode = "hyprland";
      services.displayManager = {
        autoLogin.enable = true;
        autoLogin.user = config.username;
        sddm = {
          package = pkgs.kdePackages.sddm;
          wayland.compositor = "kwin";
          extraPackages = [pkgs.kdePackages.qt5compat];
        };
      };
    };
  };

  # tell Electron/Chromium to run on Wayland
  environment.variables.NIXOS_OZONE_WL = "1";
}

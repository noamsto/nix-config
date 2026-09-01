{
  config,
  lib,
  ...
}: {
  imports = [
    ./sddm
    ./1password
  ];

  # services.flatpak asserts on xdg.portal.enable, which only programs.hyprland
  # turns on — so without this gate a desktop-less host fails to evaluate.
  config = lib.mkIf config.desktop.isEnabled {
    programs = {
      zoom-us.enable = true;
      chromium.enable = true;

      steam = lib.mkIf (config.profile == "personal") {
        enable = true;
        remotePlay.openFirewall = true;
        localNetworkGameTransfers.openFirewall = true;
      };
    };

    # Enable Qt system-wide for proper QML module resolution
    # qt5ct works with Kvantum on non-KDE desktops (Hyprland)
    # Kvantum handles style (widget colors), qt5ct handles platform integration
    qt = {
      enable = true;
      platformTheme = "qt5ct";
      style = "kvantum";
    };

    services = {
      # Enable flatpak
      flatpak.enable = true;
      libinput = lib.mkIf config.machine.isLaptop {
        enable = true;
        touchpad = {
          naturalScrolling = true;
          tapping = true;
          disableWhileTyping = true;
          # clickMethod: buttonAreas (default) or clickfinger
          # clickfinger enables: 2-finger = right-click, 3-finger = middle-click
          clickMethod = "clickfinger";
        };
      };

      # Disable scroll-on-button-down for ThinkPad TrackPoint
      # By default, libinput converts middle-button + TrackPoint movement into scroll events.
      # This prevents middle-click + drag from working as pan in 3D apps (Bambu Studio, Blender, etc.)
      udev.extraRules = lib.mkIf config.machine.isLaptop ''
        ACTION=="add|change", KERNEL=="event*", ATTRS{name}=="TPPS/2 Elan TrackPoint", ENV{LIBINPUT_ATTR_SCROLL_METHOD}="none"
      '';
    };

    services.xserver = {
      # Configure keymap in X11
      xkb.layout = "us,il";
      xkb.options = "compose:menu, grp:win_space_toggle";
    };

    # Portal is enabled and extraPortals are added by programs.hyprland NixOS module.
    # Only set the config here to avoid duplicate portal packages when hyprland is overridden.
    xdg.portal.config = {
      common.default = "hyprland";
      hyprland.default = ["hyprland" "gtk"];
    };

    # tell Electron/Chromium to run on Wayland
    environment.variables.NIXOS_OZONE_WL = "1";
  };
}

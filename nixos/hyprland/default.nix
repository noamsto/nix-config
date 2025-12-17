{
  pkgs,
  lib,
  config,
  ...
}: let
  isHypr = config.desktop.mode == "hyprland";
in {
  imports = [./gnome-services.nix];
  config = lib.mkIf isHypr {
    programs.hyprland = {
      withUWSM = true;
      enable = true;
      package = pkgs.hyprland;
    };

    services.greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.tuigreet}/bin/tuigreet --time --time-format '%I:%M %p | %a • %h %d %Y' --theme border=magenta;text=cyan;prompt=cyan;time=white;action=blue;button=yellow;container=black;input=gray --asterisks --greeting 'Welcome to NixOS' --width 80 --container-padding 2 --prompt-padding 1 --remember --remember-user-session --user-menu";
        };
      };
    };

    services.blueman.enable = true;
    security.pam.services.hyprlock = {
      enableGnomeKeyring = true;
    };

    # Ensure video group permissions for backlight control
    users.users.${config.username}.extraGroups = ["video" "i2c"];
    hardware.i2c.enable = true;
    boot.kernelModules = ["i2c_dev"];

    environment.systemPackages = with pkgs; [
      pavucontrol
      # Valent - lightweight KDE Connect protocol implementation (GTK-based)
      # Replaced KDE Connect which pulled heavy KDE dependencies
      valent
    ];
  };
}

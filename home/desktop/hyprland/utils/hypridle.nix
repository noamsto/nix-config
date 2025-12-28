{
  pkgs,
  lib,
  config,
  ...
}: let
  brightnessctl = lib.getExe pkgs.brightnessctl;
in {
  services.hypridle = {
    enable = true;

    settings = {
      general = {
        lock_cmd = "noctalia-ipc lockScreen lock";
        before_sleep_cmd = "${pkgs.systemd}/bin/loginctl lock-session";
        after_sleep_cmd = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on 2>/dev/null || true";
        ignore_dbus_inhibit = false;
      };

      listener = [
        # Dim screen
        {
          timeout = 285;
          on-timeout = "${brightnessctl} -s set 10%";
          on-resume = "${brightnessctl} -r";
        }
        # Dim keyboard backlight
        {
          timeout = 285;
          on-timeout = "${brightnessctl} -sd tpacpi::kbd_backlight set 0";
          on-resume = "${brightnessctl} -rd tpacpi::kbd_backlight";
        }
        # Lock screen
        {
          timeout = 300;
          on-timeout = "${pkgs.systemd}/bin/loginctl lock-session";
        }
        # Turn off displays (conservative delay)
        {
          timeout = 360; # 1 minute after lock
          on-timeout = "${pkgs.hyprland}/bin/hyprctl dispatch dpms off 2>/dev/null || true";
          on-resume = "${pkgs.hyprland}/bin/hyprctl dispatch dpms on 2>/dev/null || true";
        }
        # Suspend (long delay)
        {
          timeout = 1800; # 30 minutes
          on-timeout = "${pkgs.systemd}/bin/systemctl suspend";
        }
      ];
    };
  };
}

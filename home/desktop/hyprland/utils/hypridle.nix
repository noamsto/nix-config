{
  pkgs,
  lib,
  config,
  ...
}: let
  brightnessctl = lib.getExe pkgs.brightnessctl;

  # Wrapper for loginctl lock-session with logging
  loginctl-lock = pkgs.writeShellScript "loginctl-lock-logged" ''
    LOG="/tmp/aegis-lock.log"
    log() {
      echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] [loginctl-lock] $*" | tee -a "$LOG"
    }

    log "lock-session called from: ''${0##*/}"
    log "  Calling loginctl lock-session..."
    ${pkgs.systemd}/bin/loginctl lock-session
    log "  loginctl returned: $?"
  '';

  # Wrapper that kills stale aegis-lock instances before spawning a new one.
  # Defense-in-depth: aegis-lock should exit on unlock (Qt.quit), but if a
  # stale process lingers, this prevents accumulation.
  aegis-lock-cmd = pkgs.writeShellScript "aegis-lock-cmd" ''
    ${pkgs.procps}/bin/pkill -f 'quickshell.*aegis-lock' 2>/dev/null || true
    sleep 0.1
    exec aegis-lock
  '';
in {
  services.hypridle = {
    enable = true;

    settings = {
      general = {
        lock_cmd = "${aegis-lock-cmd}";
        before_sleep_cmd = "${loginctl-lock}";
        # Display turn-on is handled by hyprdynamicmonitors-resume service
        # to ensure monitor configuration is stable before lockscreen renders
        after_sleep_cmd = "";
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
          on-timeout = "${loginctl-lock}";
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

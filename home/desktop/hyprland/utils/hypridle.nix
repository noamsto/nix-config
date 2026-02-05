{
  pkgs,
  lib,
  config,
  ...
}: let
  brightnessctl = lib.getExe pkgs.brightnessctl;
  lockLogFile = "/tmp/noctalia-lock.log";

  # Wrapper for loginctl lock-session with logging
  loginctl-lock = pkgs.writeShellScript "loginctl-lock-logged" ''
    LOG="${lockLogFile}"
    log() {
      echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] [loginctl-lock] $*" | tee -a "$LOG"
    }

    log "lock-session called from: ''${0##*/}"
    log "  Caller: $(${pkgs.procps}/bin/ps -o comm= $PPID 2>/dev/null || echo unknown)"

    # Check if Noctalia is running
    noctalia_pid=$(${pkgs.procps}/bin/pgrep -f 'quickshell.*noctalia-shell' | head -1)
    if [ -n "$noctalia_pid" ]; then
      log "  Noctalia running (PID: $noctalia_pid)"
    else
      log "  WARNING: Noctalia NOT running!"
    fi

    # Check monitor state
    log "  Monitors before lock:"
    ${pkgs.hyprland}/bin/hyprctl monitors -j 2>/dev/null | ${pkgs.jq}/bin/jq -r '.[] | "    \(.name): \(.width)x\(.height) disabled=\(.disabled)"' >> "$LOG" 2>&1 || log "    (failed to get monitors)"

    # Actually lock
    log "  Calling loginctl lock-session..."
    ${pkgs.systemd}/bin/loginctl lock-session
    result=$?
    log "  loginctl returned: $result"
  '';
in {
  services.hypridle = {
    enable = true;

    settings = {
      general = {
        lock_cmd = "noctalia-ipc lockScreen lock";
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

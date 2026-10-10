{
  pkgs,
  lib,
  osConfig,
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

  # A lid-close suspend delivers two Lock signals ~1s apart (logind Lock, then
  # before_sleep_cmd re-issuing lock-session), so hypridle runs lock_cmd twice.
  # Killing the incumbent would tear down the client currently holding the
  # ext-session-lock, which leaves Hyprland on its "lock client died" screen
  # with no way back except a TTY. A running instance already owns the lock.
  aegis-lock-cmd = pkgs.writeShellScript "aegis-lock-cmd" ''
    if ${pkgs.procps}/bin/pgrep -f 'quickshell.*aegis-lock' >/dev/null; then
      exit 0
    fi
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

      listener =
        [
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
            on-timeout = "${pkgs.hyprland}/bin/hyprctl dispatch 'hl.dsp.dpms({ action = \"off\" })' 2>/dev/null || true";
            on-resume = "${pkgs.hyprland}/bin/hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })' 2>/dev/null || true";
          }
        ]
        # In server mode the box must stay awake for SSH/tmux — drop idle suspend.
        ++ lib.optionals (!(osConfig.machine.serverMode or false)) [
          # Suspend (long delay)
          {
            timeout = 1800; # 30 minutes
            on-timeout = "${pkgs.systemd}/bin/systemctl suspend";
          }
        ];
    };
  };
}

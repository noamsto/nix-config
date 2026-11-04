{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (config.machine) isLaptop serverMode;

  lidCheckScript = pkgs.writeShellScript "lid-suspend-fallback" ''
    # If lid is open, nothing to do
    lid_state=$(cat /proc/acpi/button/lid/LID0/state 2>/dev/null || echo "state: open")
    if echo "$lid_state" | grep -q "open"; then
      exit 0
    fi

    # If Hyprland is running, HDM handles lid events — don't interfere
    if ${pkgs.procps}/bin/pgrep -x Hyprland >/dev/null 2>&1; then
      exit 0
    fi

    # Lid is closed and Hyprland is not running — suspend
    echo "lid-suspend-fallback: lid closed, no Hyprland — suspending" | ${pkgs.systemd}/bin/systemd-cat -t lid-suspend-fallback
    ${pkgs.systemd}/bin/systemctl suspend
  '';
in {
  config = lib.mkIf (isLaptop && !serverMode) {
    systemd.services.lid-suspend-fallback = {
      description = "Suspend when lid is closed and Hyprland is not running";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lidCheckScript;
      };
    };

    systemd.timers.lid-suspend-fallback = {
      description = "Periodic lid-close suspend check (fallback for when Hyprland is dead)";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "30s";
      };
    };
  };
}

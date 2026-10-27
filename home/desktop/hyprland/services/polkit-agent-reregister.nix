{
  pkgs,
  lib,
  ...
}: let
  # An agent registers with polkitd once at startup; a polkitd restart drops
  # that registration and hyprpolkitagent never re-registers, so restart it.
  watcher = pkgs.writeShellApplication {
    name = "polkit-agent-reregister";
    runtimeInputs = [pkgs.glib pkgs.coreutils pkgs.systemd];
    text = ''
      seen=0
      stdbuf -oL gdbus monitor --system --dest org.freedesktop.PolicyKit1 |
        while read -r line; do
          case $line in
            "The name "*" is owned by "*)
              # The first report is the owner at watcher start, not a restart.
              if [ "$seen" = 1 ]; then
                systemctl --user restart hyprpolkitagent.service ||
                  echo "polkit-agent-reregister: agent restart failed" >&2
              fi
              seen=1
              ;;
            "The name "*" does not have an owner") seen=1 ;;
          esac
        done
    '';
  };
in {
  systemd.user.services.polkit-agent-reregister = {
    Unit = {
      Description = "Restart the polkit agent when polkitd restarts";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
    };

    Service = {
      ExecStart = lib.getExe watcher;
      Restart = "on-failure";
      RestartSec = "1s";
    };

    Install.WantedBy = ["graphical-session.target"];
  };
}

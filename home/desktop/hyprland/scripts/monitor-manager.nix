{
  pkgs,
  config,
  ...
}: let
  configHome = config.xdg.configHome;

  monitorManager = pkgs.writeShellScriptBin "monitor-manager" (builtins.readFile ./monitor-manager.sh);

  monitorIpcListener = pkgs.writeShellScript "monitor-ipc-listener" ''
    SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

    if [ ! -S "$SOCKET" ]; then
        echo "ERROR: Hyprland IPC socket not found at $SOCKET"
        exit 1
    fi

    echo "Listening for Hyprland monitor events..."

    # Listen to socket and filter for monitor events
    ${pkgs.socat}/bin/socat -u "UNIX-CONNECT:$SOCKET" - | while read -r line; do
        event=$(echo "$line" | cut -d'>' -f1)

        case "$event" in
            monitoradded*|monitorremoved*)
                echo "$(date): Monitor event detected: $event"
                # Small delay to let Hyprland finish processing
                sleep 0.5
                # Run monitor manager with full path
                ${monitorManager}/bin/monitor-manager
                ;;
        esac
    done
  '';
in {
  # Unified monitor management replacing hyprdynamicmonitors
  home.packages = [
    monitorManager
    pkgs.socat # Required for IPC socket listening
  ];

  # Systemd service to listen for Hyprland monitor events
  systemd.user.services.hyprland-monitor-listener = {
    Unit = {
      Description = "Hyprland Monitor Event Listener";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.writeShellScript "monitor-ipc-listener-wrapped" ''
        # Wait for Hyprland to be ready
        until [ -S "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" ]; do
          sleep 1
        done
        exec ${monitorIpcListener}
      ''}";
      Restart = "always";
      RestartSec = "5";
    };

    Install = {
      WantedBy = ["graphical-session.target"];
    };
  };
}

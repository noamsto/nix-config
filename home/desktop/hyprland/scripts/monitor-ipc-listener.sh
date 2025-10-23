#!/usr/bin/env bash
# Hyprland IPC event listener for monitor hotplug events
# Calls monitor-manager when monitors are added/removed

SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

if [ ! -S "$SOCKET" ]; then
  echo "ERROR: Hyprland IPC socket not found at $SOCKET"
  exit 1
fi

echo "Listening for Hyprland monitor events..."

# Listen to socket and filter for monitor events
socat -u "UNIX-CONNECT:$SOCKET" - | while read -r line; do
  event=$(echo "$line" | cut -d'>' -f1)

  case "$event" in
  monitoradded* | monitorremoved*)
    echo "$(date): Monitor event detected: $event"
    # Small delay to let Hyprland finish processing
    sleep 0.5
    # Run monitor manager
    monitor-manager
    ;;
  esac
done

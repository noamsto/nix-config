#!/usr/bin/env bash
# Generic workspace manager for hyprdynamicmonitors
# Dependencies provided by Nix writeShellApplication: gdbus, hyprctl, xrdb

set -euo pipefail

# Constants
readonly SUSPEND_LOCK_FILE="/tmp/hyprdynamicmonitors-suspend.lock"
readonly LOG_FILE="/tmp/workspace-manager.log"
readonly LOCK_LOG_FILE="/tmp/noctalia-lock.log"

# Arguments
readonly PROFILE="${1:-}"
readonly LEFT_MONITOR="${2:-}"
readonly RIGHT_MONITOR="${3:-}"
readonly LAPTOP_MONITOR="${4:-eDP-1}"

# Logging
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$PROFILE] $*" >>"$LOG_FILE"
}

# Wait for Hyprland IPC to be ready
wait_for_hyprland() {
  local timeout=10
  local elapsed=0

  log "Waiting for Hyprland IPC to be ready..."

  while [ $elapsed -lt $timeout ]; do
    if hyprctl monitors &>/dev/null; then
      log "Hyprland IPC ready after ${elapsed}s"
      return 0
    fi
    sleep 0.5
    elapsed=$((elapsed + 1))
  done

  log "ERROR: Hyprland IPC not ready after ${timeout}s"
  return 1
}

# Check if lid is closed
is_lid_closed() {
  gdbus call --system \
    --dest org.freedesktop.UPower \
    --object-path /org/freedesktop/UPower \
    --method org.freedesktop.DBus.Properties.Get \
    org.freedesktop.UPower LidIsClosed 2>/dev/null | grep -q "true"
}

# Configure dual monitor docked setup
configure_docked() {
  local left="$1"
  local right="$2"

  log "Configuring docked: left=$left, right=$right"

  # Move existing workspaces to match profile rules BEFORE reload
  # This ensures workspaces are positioned correctly even if reload triggers HDM re-evaluation

  # Left monitor: workspaces 1-4
  for ws in {1..4}; do
    log "Moving workspace $ws to left monitor"
    if ! hyprctl dispatch moveworkspacetomonitor "$ws $left"; then
      log "WARNING: Failed to move workspace $ws to $left"
    fi
  done

  # Right monitor: workspaces 5-8
  for ws in {5..8}; do
    log "Moving workspace $ws to right monitor"
    if ! hyprctl dispatch moveworkspacetomonitor "$ws $right"; then
      log "WARNING: Failed to move workspace $ws to $right"
    fi
  done

  # Laptop screen: workspace 9 (if lid open)
  if ! is_lid_closed; then
    log "Moving workspace 9 to laptop monitor"
    if ! hyprctl dispatch moveworkspacetomonitor "9 $LAPTOP_MONITOR"; then
      log "WARNING: Failed to move workspace 9 to $LAPTOP_MONITOR"
    fi
  fi

  # Reload Hyprland to apply profile's monitor + workspace rules from config
  log "Reloading Hyprland configuration..."
  if ! hyprctl reload; then
    log "WARNING: Failed to reload Hyprland configuration"
  fi
}

# Configure undocked (laptop only)
configure_undocked() {
  log "Configuring undocked"

  # Log current monitor state for debugging
  log "Current Hyprland monitors:"
  hyprctl monitors -j 2>/dev/null | jq -r '.[] | "  \(.name): \(.width)x\(.height) disabled=\(.disabled)"' >>"$LOG_FILE" 2>&1 || log "  (failed to get monitors)"

  # Check Noctalia status
  noctalia_pid=$(pgrep -f 'quickshell.*noctalia-shell' | head -1)
  if [ -n "$noctalia_pid" ]; then
    log "Noctalia running (PID: $noctalia_pid)"
  else
    log "WARNING: Noctalia NOT running!"
  fi

  # Always turn DPMS on and reload when undocking, REGARDLESS of lid state.
  # When docked with lid closed, eDP-1 was disabled and DPMS may be off.
  # Without resetting the display pipeline here, suspend+resume leaves eDP-1
  # in a broken state (black screen on lid open after resume).
  log "Turning DPMS on (unconditional on undock)..."
  hyprctl dispatch dpms on 2>/dev/null || true

  log "Reloading Hyprland configuration..."
  hyprctl reload 2>/dev/null || true

  # Let the display pipeline settle before any further actions
  sleep 0.5

  # Check lid state - spawn detached suspend handler if closed
  # Must use setsid to survive HDM killing this script on profile switch
  if is_lid_closed; then
    log "Lid closed while undocked - spawning suspend handler"

    # Check for stale lock (older than 30 seconds = way past the 2s debounce)
    if [ -f "$SUSPEND_LOCK_FILE" ]; then
      local lock_age
      lock_age=$(($(date +%s) - $(stat -c %Y "$SUSPEND_LOCK_FILE" 2>/dev/null || echo 0)))
      if [ "$lock_age" -gt 30 ]; then
        log "Removing stale lock file (age: ${lock_age}s)"
        rm -f "$SUSPEND_LOCK_FILE"
      else
        log "Suspend already in progress (lock age: ${lock_age}s), skipping"
        return
      fi
    fi

    # Create lock BEFORE spawning to prevent race condition
    touch "$SUSPEND_LOCK_FILE"

    # Spawn detached suspend handler - survives HDM killing this script
    # Uses setsid to create new session, immune to parent termination
    setsid bash -c "
      LOG_FILE='$LOG_FILE'
      LOCK_LOG_FILE='$LOCK_LOG_FILE'
      SUSPEND_LOCK_FILE='$SUSPEND_LOCK_FILE'

      log() {
        local msg=\"[\$(date '+%Y-%m-%d %H:%M:%S.%3N')] [suspend-handler] \$*\"
        echo \"\$msg\" >>\"\$LOG_FILE\"
        echo \"\$msg\" >>\"\$LOCK_LOG_FILE\"
      }

      is_lid_closed() {
        gdbus call --system \
          --dest org.freedesktop.UPower \
          --object-path /org/freedesktop/UPower \
          --method org.freedesktop.DBus.Properties.Get \
          org.freedesktop.UPower LidIsClosed 2>/dev/null | grep -q 'true'
      }

      trap 'rm -f \"\$SUSPEND_LOCK_FILE\"' EXIT

      log 'Debouncing for 2s...'

      # Confirm lid still closed after 2s
      for _ in {1..4}; do
        sleep 0.5
        if ! is_lid_closed; then
          log 'Lid opened during debounce - canceling suspend'
          exit 0
        fi
      done

      # Check Noctalia before lock
      noctalia_pid=\$(pgrep -f 'quickshell.*noctalia-shell' | head -1)
      if [ -n \"\$noctalia_pid\" ]; then
        log \"Noctalia running before lock (PID: \$noctalia_pid)\"
      else
        log 'ERROR: Noctalia NOT running before lock!'
      fi

      log 'Initiating lock + suspend'
      rm -f \"\$SUSPEND_LOCK_FILE\"
      trap - EXIT

      loginctl lock-session
      lock_result=\$?
      log \"loginctl lock-session returned: \$lock_result\"

      # Check Noctalia after lock
      sleep 0.5
      noctalia_pid=\$(pgrep -f 'quickshell.*noctalia-shell' | head -1)
      if [ -n \"\$noctalia_pid\" ]; then
        log \"Noctalia still running after lock (PID: \$noctalia_pid)\"
      else
        log 'ERROR: Noctalia DIED after lock!'
      fi

      sleep 0.5
      log 'Calling systemctl suspend...'
      systemctl suspend
      suspend_result=\$?

      log \"Resumed from suspend (suspend returned: \$suspend_result)\"
    " &>/dev/null &

    log "Suspend handler spawned (detached)"
    return
  fi

  # Lid is open - move all workspaces to laptop
  for ws in {1..9}; do
    if ! hyprctl dispatch moveworkspacetomonitor "$ws $LAPTOP_MONITOR"; then
      log "WARNING: Failed to move workspace $ws to $LAPTOP_MONITOR"
    fi
  done
}

# Main
main() {
  if [ -z "$PROFILE" ]; then
    echo "Usage: $0 <profile> [left_monitor] [right_monitor] [laptop_monitor]" >&2
    echo "Profiles: docked, undocked, undocked-lid-closed" >&2
    exit 1
  fi

  log "=== Starting: $PROFILE ==="
  # Also log to lock log for unified timeline
  echo "[$(date '+%Y-%m-%d %H:%M:%S.%3N')] [workspace-manager] Profile switch to: $PROFILE" >>"$LOCK_LOG_FILE"

  # Wait for Hyprland IPC to be ready
  if ! wait_for_hyprland; then
    log "ERROR: Cannot proceed - Hyprland IPC not ready"
    exit 1
  fi

  # Load XWayland settings in background
  if [ "$PROFILE" = "docked" ]; then
    xrdb -merge ~/.Xresources.docked 2>/dev/null &
  else
    xrdb -merge ~/.Xresources.laptop 2>/dev/null &
  fi

  # Configure workspaces
  case "$PROFILE" in
  docked)
    if [ -z "$LEFT_MONITOR" ] || [ -z "$RIGHT_MONITOR" ]; then
      log "ERROR: docked profile requires left and right monitor arguments"
      exit 1
    fi
    configure_docked "$LEFT_MONITOR" "$RIGHT_MONITOR"
    ;;
  undocked | undocked-lid-closed)
    configure_undocked
    ;;
  *)
    log "ERROR: Unknown profile: $PROFILE"
    exit 1
    ;;
  esac

  # Noctalia Shell auto-adapts to monitor changes, no restart needed

  log "=== Completed successfully ==="
}

main

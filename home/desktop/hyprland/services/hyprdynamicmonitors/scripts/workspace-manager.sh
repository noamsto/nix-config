#!/usr/bin/env bash
# Generic workspace manager for hyprdynamicmonitors
# Dependencies provided by Nix writeShellApplication: gdbus, hyprctl, xrdb

set -euo pipefail

# Constants
readonly SUSPEND_LOCK_FILE="/tmp/hyprdynamicmonitors-suspend.lock"
readonly LOG_FILE="/tmp/workspace-manager.log"

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

  # Check lid state FIRST - spawn detached suspend handler if closed
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
      SUSPEND_LOCK_FILE='$SUSPEND_LOCK_FILE'

      log() { echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] [suspend-handler] \$*\" >>\"\$LOG_FILE\"; }

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

      log 'Initiating lock + suspend'
      rm -f \"\$SUSPEND_LOCK_FILE\"
      trap - EXIT

      loginctl lock-session
      sleep 1
      systemctl suspend

      log 'Resumed from suspend'
    " &>/dev/null &

    log "Suspend handler spawned (detached)"
    return
  fi

  # Lid is open - proceed with normal undocked configuration
  log "Reloading Hyprland configuration..."
  if ! hyprctl reload; then
    log "WARNING: Failed to reload Hyprland configuration"
  fi

  # Small delay to let Hyprland process the reload
  sleep 0.3

  # Move all workspaces to laptop
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

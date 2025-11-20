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

  # Make workspaces 5-8 persistent
  for ws in {5..8}; do
    hyprctl keyword workspace "$ws,persistent:true" 2>/dev/null || true
  done

  # Left monitor: workspaces 1-4
  for ws in {1..4}; do
    hyprctl keyword workspace "$ws,monitor:$left" 2>/dev/null || true
    hyprctl dispatch moveworkspacetomonitor "$ws $left" 2>/dev/null || true
  done

  # Right monitor: workspaces 5-8
  for ws in {5..8}; do
    hyprctl keyword workspace "$ws,monitor:$right" 2>/dev/null || true
    hyprctl dispatch moveworkspacetomonitor "$ws $right" 2>/dev/null || true
  done

  # Laptop screen: workspace 9 (if lid open)
  if ! is_lid_closed; then
    hyprctl keyword workspace "9,monitor:$LAPTOP_MONITOR" 2>/dev/null || true
    hyprctl dispatch moveworkspacetomonitor "9 $LAPTOP_MONITOR" 2>/dev/null || true
  fi

  # Cleanup workspaces 10+
  for ws in {10..20}; do
    hyprctl keyword workspace "$ws,persistent:false" 2>/dev/null || true
  done

  hyprctl dispatch workspace 1 2>/dev/null || true
}

# Configure undocked (laptop only)
configure_undocked() {
  log "Configuring undocked"

  # Move all workspaces to laptop
  for ws in {1..9}; do
    hyprctl keyword workspace "$ws,monitor:$LAPTOP_MONITOR" 2>/dev/null || true
    hyprctl dispatch moveworkspacetomonitor "$ws $LAPTOP_MONITOR" 2>/dev/null || true
  done

  # Cleanup
  for ws in {10..20}; do
    hyprctl keyword workspace "$ws,persistent:false" 2>/dev/null || true
  done

  hyprctl dispatch workspace 1 2>/dev/null || true

  # Handle lid-closed suspend
  if is_lid_closed; then
    log "Lid closed while undocked - triggering suspend"

    [ -f "$SUSPEND_LOCK_FILE" ] && return
    touch "$SUSPEND_LOCK_FILE"

    # Confirm lid still closed after 2s
    for _ in {1..4}; do
      sleep 0.5
      if ! is_lid_closed; then
        log "Lid opened, canceling suspend"
        rm -f "$SUSPEND_LOCK_FILE"
        return
      fi
    done

    systemctl suspend
    rm -f "$SUSPEND_LOCK_FILE"
  fi
}

# Main
main() {
  if [ -z "$PROFILE" ]; then
    echo "Usage: $0 <profile> [left_monitor] [right_monitor] [laptop_monitor]" >&2
    echo "Profiles: docked, undocked, undocked-lid-closed" >&2
    exit 1
  fi

  log "=== Starting: $PROFILE ==="

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

  # Launch dock (unless undocked with lid closed or about to suspend)
  if [ "$PROFILE" = "docked" ] || ! is_lid_closed; then
    launch-dock &
  fi

  # Manage fingerprint daemon
  if is_lid_closed; then
    systemctl stop fprintd.service 2>/dev/null &
  else
    systemctl start fprintd.service 2>/dev/null &
  fi

  log "=== Completed successfully ==="
}

main

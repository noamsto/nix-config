#!/usr/bin/env bash
# Apply the active monitor profile's X resources (notably Xft.dpi) to the
# running X server, and optionally record that profile.
#
# Usage:
#   xresources-apply <profile>   record <profile>, then merge its resources
#   xresources-apply             merge the recorded profile's resources
#
# Hyprland's `hyprland.start` hook calls the no-argument form, so a Hyprland
# (and thus XWayland) restart re-applies the profile that was active before the
# restart. workspace-manager calls the one-argument form on every switch, which
# both applies the resources and records the profile for that replay.

set -euo pipefail

readonly STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprland"
readonly STATE_FILE="$STATE_DIR/monitor-profile"

resolve_file() {
  # No recorded profile: keep the historical default (~/.Xresources, laptop DPI
  # on this host) so undocked behaviour is unchanged.
  case "$1" in
  docked) printf '%s\n' "$HOME/.Xresources.docked" ;;
  "") printf '%s\n' "$HOME/.Xresources" ;;
  *) printf '%s\n' "$HOME/.Xresources.laptop" ;;
  esac
}

profile="${1:-}"
if [ -n "$profile" ]; then
  mkdir -p "$STATE_DIR"
  # Atomic rename: a concurrent no-arg replay must never read a truncated file.
  tmp=$(mktemp "$STATE_DIR/.monitor-profile.XXXXXX")
  printf '%s\n' "$profile" >"$tmp"
  mv -f "$tmp" "$STATE_FILE"
elif [ -r "$STATE_FILE" ]; then
  profile=$(cat "$STATE_FILE")
fi

xrdb -merge "$(resolve_file "$profile")"

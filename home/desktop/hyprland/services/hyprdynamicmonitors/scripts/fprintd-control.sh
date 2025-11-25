#!/usr/bin/env bash
# Fingerprint daemon control based on lid state
# Used as pre_apply_exec hook in hyprdynamicmonitors

set -euo pipefail

# Check if lid is closed
is_lid_closed() {
  gdbus call --system \
    --dest org.freedesktop.UPower \
    --object-path /org/freedesktop/UPower \
    --method org.freedesktop.DBus.Properties.Get \
    org.freedesktop.UPower LidIsClosed 2>/dev/null | grep -q "true"
}

# Main
if is_lid_closed; then
  # Lid closed - stop fingerprint daemon (can't use fingerprint reader when lid closed)
  systemctl --user stop fprintd.service 2>/dev/null || true
else
  # Lid open - ensure fingerprint daemon is running
  systemctl --user start fprintd.service 2>/dev/null || true
fi

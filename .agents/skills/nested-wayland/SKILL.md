---
name: nested-wayland
description: Use when launching a nested Hyprland or other nested Wayland compositor for testing, or when portals fail with "Couldn't connect to a wayland compositor", "cannot open display" or start-limit-hit after a nested run, or nh os switch activation exits 4.
---

# Nested Wayland compositors

Hyprland runs `systemctl --user import-environment DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE ...` at every startup, nested instances included. An unguarded nested run points the systemd user manager at a socket that dies with it. Nothing looks broken until the next `nh os switch` or `test` restarts user units: `xdg-desktop-portal-hyprland` exits with `Couldn't connect to a wayland compositor`, `xdg-desktop-portal-gtk` with `cannot open display:`, systemd reports `start-limit-hit`, and activation exits 4. One stale variable fails the whole rebuild.

Launch nested runs with a private runtime dir. It cuts the import chain off from the live user manager, and the absolute `WAYLAND_DISPLAY` still finds the parent socket:

```bash
rt=$(mktemp -d)
XDG_RUNTIME_DIR=$rt WAYLAND_DISPLAY=/run/user/$UID/wayland-1 Hyprland -c nested.conf
```

`HYPRLAND_NO_SD_VARS=1` is not a guard. It exists in hyprland 0.56.2 but does not gate that call; a tested nested run clobbered the user manager's variables anyway.

## Repairing a clobbered session

No logout needed. Compare the `WAYLAND_DISPLAY` line of the user manager's variables (`systemctl --user show-environment`, filtered to that one name) against the `wl socket:` line in `hyprctl instances`, then:

```bash
dbus-update-activation-environment --systemd WAYLAND_DISPLAY=<live> HYPRLAND_INSTANCE_SIGNATURE=<live> XDG_CURRENT_DESKTOP=Hyprland
systemctl --user start xdg-desktop-portal{,-gtk,-hyprland}.service
```

The first journal entry is the signal; start-limit-hit is only its echo.

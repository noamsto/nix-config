# ThinkPad TrackPoint Middle Button Issue

## Problem

Middle-click + TrackPoint drag **zooms** instead of **panning** in 3D apps (Bambu Studio, etc.).

- External mouse middle-click + drag = **pan** (works correctly)
- TrackPoint middle-click + drag = **zoom** (broken - sends scroll events)
- Middle-click paste works fine in other apps (Firefox, Kitty, other XWayland apps)

## Root Cause

libinput enables **scroll-on-button-down** by default for devices with `INPUT_PROP_POINTING_STICK` (like TrackPoint). When you hold middle button and move the TrackPoint, libinput converts pointer movement into scroll events. 3D apps interpret scroll as zoom.

## Device Info

```
TrackPoint: TPPS/2 Elan TrackPoint
- Handlers: event7 mouse2
- PROP=21 (POINTER + BUTTONPAD + POINTING_STICK)
- Has BTN_LEFT, BTN_RIGHT, BTN_MIDDLE

Touchpad: SYNA8018:00 06CB:CE67
- Physical buttons above touchpad are part of this device
```

## Solution Attempted

Added udev rule in `nixos/desktop/default.nix` to disable scroll-on-button-down:

```nix
services.udev.extraRules = lib.mkIf (config.machine.type == "laptop") ''
  ACTION=="add|change", KERNEL=="event*", ATTRS{name}=="TPPS/2 Elan TrackPoint", ENV{LIBINPUT_ATTR_SCROLL_METHOD}="none"
'';
```

## Current Status: UNTESTED

The udev rule has been added but **not yet applied**. Need to:

1. Run `nh os switch .` to rebuild system
2. Either reboot OR run:
   ```bash
   sudo udevadm control --reload-rules && sudo udevadm trigger
   ```
3. Test middle-click + TrackPoint drag in Bambu Studio

## If udev rule doesn't work

Alternative approaches to try:

1. **libinput quirks file** - Create `/etc/libinput/local-overrides.quirks`:
   ```ini
   [TPPS/2 Elan TrackPoint]
   MatchName=TPPS/2 Elan TrackPoint
   AttrScrollMethod=none
   ```

2. **Different udev attribute** - Try `LIBINPUT_ATTR_SCROLL_BUTTON` instead:
   ```
   ENV{LIBINPUT_ATTR_SCROLL_BUTTON}="0"
   ```

3. **xinput for XWayland** - Set property at X level (only affects XWayland apps):
   ```bash
   xinput set-prop "TPPS/2 Elan TrackPoint" "libinput Scroll Method Enabled" 0 0 0
   ```

4. **Check if it's the touchpad** - The physical buttons might be sending events through the touchpad device, not TrackPoint. May need to configure `syna8018:00-06cb:ce67-touchpad` instead.

## Files Modified

- `nixos/desktop/default.nix` - Added udev rule (staged)
- `home/desktop/hyprland/settings/default.nix` - Tried Hyprland device config (reverted, didn't work)

## Useful Commands

```bash
# Check TrackPoint device info
cat /proc/bus/input/devices | grep -A10 "TrackPoint"

# List Hyprland input devices
hyprctl devices

# Check if udev rule is loaded
udevadm info -a -n /dev/input/event7 | grep LIBINPUT

# Test input events (need evtest package)
sudo evtest /dev/input/event7
```

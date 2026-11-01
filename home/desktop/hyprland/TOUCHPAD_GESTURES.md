# Touchpad Gesture Configuration

This document explains the touchpad gesture optimizations for both fluid workflow and 3D modeling applications (Blender, Bambu Studio).

**Version:** Hyprland 0.51+ with new gesture system

## Configuration Overview

### Touchpad Settings

**Hyprland touchpad config** (`home/desktop/hyprland/settings/default.nix:72-78`)
- `scroll_factor = 0.6` - Finer scroll control in 3D viewports (40% reduction for precision)
- `natural_scroll = true` - Intuitive scrolling direction
- `tap-to-click = true` - Quick tapping for clicks
- `disable_while_typing = true` - Prevents accidental touchpad input while typing

**System-level libinput config** (`nixos/desktop/default.nix:29-38`)
- `clickMethod = "clickfinger"` - Multi-touch clicking:
  - 2-finger tap = right-click
  - 3-finger tap = middle-click (great for 3D viewport panning in Blender)
- `dragLock = true` - Continue dragging after brief finger release (precision dragging)
- `naturalScrolling = true` - System-wide natural scroll
- `tapping = true` - Tap-to-click enabled
- `disableWhileTyping = true` - Prevents typing conflicts

## Native Hyprland Gestures (0.51+)

### 3-Finger Gestures (Primary Navigation)
- **3-finger swipe left/right** → Switch workspaces (e+1/e-1)
- **3-finger swipe down** → Toggle special workspace (magic)
- **3-finger swipe up** → Hyprexpo overview

### 4-Finger Gestures (Window Management)
- **4-finger swipe up** → Launch Vicinae application launcher
- **4-finger swipe down** → Hyprexpo overview (alternative trigger)
- **4-finger swipe left/right** → Move active window to adjacent workspace

## Advanced Gestures (libinput-gestures)

**Note:** Most gestures are now handled natively by Hyprland 0.51+. The libinput-gestures package is included for future custom gesture additions (like pinch-based brightness/volume control).

## 3D Modeling App Usage

### Blender
**Native touchpad support:**
- **2-finger drag** → Pan viewport
- **2-finger pinch** → Zoom viewport
- **3-finger tap** → Middle-click equivalent (great for view rotation with clickfinger_behavior)
- **Scroll** → Zoom (finer control with scroll_factor = 0.6)

**Recommended Blender settings:**
- Preferences → Input → Emulate 3 Button Mouse: OFF (not needed with clickfinger)
- Navigation style: Set to your preference

### Bambu Studio
**Working touchpad gestures:**
- ✅ **2-finger pinch** → Zoom viewport (confirmed working!)
- ✅ **2-finger drag** → Pan viewport
- ✅ **3-finger tap + drag** → Rotate view (using clickfinger middle-click)
- ✅ **Scroll** → Zoom (finer control with scroll_factor = 0.6)

## Testing Your Configuration

### 1. Apply the configuration:
```bash
nh home switch .
```

### 2. Start libinput-gestures service:
The service should auto-start with your graphical session. To check status:
```bash
systemctl --user status libinput-gestures
```

To manually restart:
```bash
systemctl --user restart libinput-gestures
```

### 3. Debug gestures (optional):
Watch gesture events in real-time:
```bash
libinput debug-events --show-keycodes
```

### 4. Test workflow:
- [ ] 3-finger swipe left/right → Switch workspaces
- [ ] 4-finger swipe up → Launch Vicinae
- [ ] 4-finger swipe down → Show all windows
- [ ] Open Blender → Test 2-finger pan, pinch zoom, 3-finger tap + drag for rotate
- [ ] Open Bambu Studio → Test scroll zoom, 3-finger tap + drag for rotate
- [ ] Try canceling workspace swipe mid-gesture (should be easier now)

## Troubleshooting

### Gestures not working?
1. **Check user group membership:**
   ```bash
   groups | grep input
   ```
   If "input" is not listed, you may need to add your user to the input group:
   ```bash
   sudo usermod -aG input $USER
   ```
   Then log out and back in.

2. **Check libinput-gestures service:**
   ```bash
   journalctl --user -u libinput-gestures -f
   ```

3. **Verify device detection:**
   ```bash
   libinput list-devices | grep -i touchpad
   ```

### Gestures too sensitive or not sensitive enough?
Edit `~/.config/libinput-gestures.conf` and adjust:
```conf
# Increase number for less sensitive (requires more movement)
# Decrease for more sensitive (less movement needed)
gesture_threshold 0
```

### Conflicts with 3D app gestures?
If Hyprland's 3-finger workspace switching conflicts with 3D rotation:
1. Disable workspace swipe temporarily for focused 3D app
2. Use keyboard shortcuts for workspace switching when in 3D apps
3. Consider creating window rules to disable gestures for specific apps

## Configuration Files

- Main touchpad config: `home/desktop/hyprland/settings/default.nix`
- Gesture service: `home/desktop/hyprland/services/libinput-gestures.nix`
- Service import: `home/desktop/hyprland/services/default.nix`
- Package list: `home/packages.nix`

## Additional Resources

- [Hyprland Gestures Wiki](https://wiki.hypr.land/Configuring/Gestures/)
- [libinput-gestures GitHub](https://github.com/bulletmark/libinput-gestures)
- [Blender Input Preferences](https://docs.blender.org/manual/en/latest/editors/preferences/input.html)

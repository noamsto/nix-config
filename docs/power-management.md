# Power Management Research

This document captures research on ThinkPad P14s Gen 5 power management issues and solutions.

## System Overview

- **Model**: ThinkPad P14s Gen 5 (AMD)
- **Sleep State**: `s2idle` (modern standby, no S3 support)
- **Kernel**: Linux with AMD platform

## Issues Investigated (2024-12-30)

### 1. Spurious Wake on AC Plug/Unplug

**Problem**: Laptop wakes from suspend when AC adapter is plugged or unplugged.

**Root Cause**: On modern AMD laptops without S3 sleep, ACPI EC (Embedded Controller) events can trigger wake from s2idle.

**Solution**: Kernel parameter `acpi.ec_no_wakeup=1`

```nix
# In hardware-configuration.nix
boot.kernelParams = [ "acpi.ec_no_wakeup=1" ];
```

**Trade-off**: This also blocks dock wake from suspend (see below).

### 2. Dock Wake Not Working

**Problem**: Connecting Thunderbolt dock while laptop is suspended doesn't wake it.

**Investigation**:
- Thunderbolt wake sources are enabled in ACPI:
  ```
  NHI0  S3  *enabled  pci:0000:c6:00.5
  NHI1  S4  *enabled  pci:0000:c6:00.6
  ```
- Thunderbolt IRQ is 45, separate from ACPI IRQ 9
- USB wake is disabled on all devices (autosuspend)

**Findings**: Dock wake doesn't work on this system regardless of `acpi.ec_no_wakeup` setting. This is likely due to:
1. **s2idle limitations**: Modern standby doesn't fully support Thunderbolt wake on some AMD systems
2. **Firmware/BIOS**: May require BIOS update or specific settings
3. **Known AMD issue**: Thunderbolt wake from s2idle is unreliable on many AMD laptops

**Decision**: Since dock wake doesn't work anyway, use the simpler kernel parameter approach to block spurious AC wakes. Revisit if dock wake becomes functional (BIOS/kernel updates).

### 3. External Keyboard Not Waking Screen from DPMS Off

**Problem**: Logitech Bolt keyboard doesn't wake screen when DPMS turns monitors off.

**Root Cause**: USB autosuspend (2 second timeout) puts Logitech receiver to sleep. When user presses key, receiver doesn't wake fast enough to generate HID event.

**Solution**: udev rule to disable autosuspend for Logitech devices:

```nix
# In nixos/core/pc.nix
services.udev.extraRules = ''
  ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="046d", TEST=="power/control", ATTR{power/control}="on"
'';
```

**Why this works**:
- `046d` is Logitech's USB vendor ID (covers Bolt, Unifying, wired devices)
- `power/control="on"` forces device to stay powered
- Receiver stays active, immediately sends HID events on keypress
- hypridle detects activity and runs `on-resume` (DPMS on)

### 4. hyprdynamicmonitors-resume Service Issues

#### 4a. Service Can't Connect to Hyprland (Original Issue)

**Problem**: Service runs as root but needs to communicate with user's Hyprland session.

**Root Cause**: Missing `XDG_RUNTIME_DIR` export.

**Solution**: Export environment variables for user session.

#### 4b. Stale Socket Selection (2026-01-28)

**Problem**: Resume service connects to stale/old Hyprland socket instead of active one.

**Root Cause**: `ls /run/user/1000/hypr/ | head -1` picks alphabetically first directory, which may be from a previous session that hasn't been cleaned up.

**Symptoms in journal**:
```
Couldn't connect to /run/user/1000/hypr/ab1d80f3..._OLD_SIGNATURE/.socket.sock. (4)
```

**Solution**: Use `ls -t` to sort by modification time (most recent first), and verify socket responds:
```bash
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr/ 2>/dev/null | head -1)
# Also verify socket is accessible before proceeding
hyprctl monitors &>/dev/null || exit 0
```

#### 4c. Lockscreen Crash on Resume (2026-01-28)

**Problem**: Lockscreen occasionally crashes when opening laptop lid after suspend.

**Root Cause**: Race condition - DPMS turns on before laptop monitor (eDP-1) is enabled:
1. Docked with lid closed: eDP-1 is disabled
2. User undocks while asleep, opens lid to wake
3. Resume service disables phantom external monitors
4. DPMS turns on
5. Lockscreen tries to render but eDP-1 is still disabled → crash

**Solution**: Enable eDP-1 with safe defaults BEFORE turning on DPMS:
```bash
# Enable laptop monitor first (lockscreen needs a render target)
hyprctl keyword monitor "eDP-1,preferred,auto,2.0"
sleep 0.3
# Now safe to turn on display
hyprctl dispatch dpms on
sleep 0.2
# HDM will refine monitor config
systemctl --user restart hyprdynamicmonitors.service
```

#### 4d. Duplicate Resume Services (2026-01-28)

**Problem**: Both system-level and user-level services were restarting HDM on resume, causing race conditions.

**Solution**: Removed user-level `hyprdynamicmonitors-resume` service. Only the system-level service in `nixos/laptop/suspend-handling.nix` handles resume now.

## Wake Source Detection (Future Reference)

If dock wake becomes functional and we want to differentiate dock vs AC wakes:

### Method 1: Check Wake IRQ
```bash
# After resume, check what caused wake
wake_irq=$(cat /sys/power/pm_wakeup_irq)
# IRQ 45 = Thunderbolt (dock)
# IRQ 9  = ACPI (AC plug, lid, power button)
```

### Method 2: Check /proc/interrupts
```bash
cat /proc/interrupts | grep -E "thunderbolt|acpi"
#  9:  ... IR-IO-APIC  9-fasteoi  acpi
# 45:  ... IR-PCI-MSIX ... thunderbolt
```

### ACPI Wake Sources
```bash
cat /proc/acpi/wakeup
# GPP5  S0  *enabled  pci:0000:00:02.1
# NHI0  S3  *enabled  pci:0000:c6:00.5  <- Thunderbolt
# XHC0  S3  *enabled  pci:0000:c4:00.3  <- USB
# LID   S4  *enabled  platform:PNP0C0D:00
```

### 5. Lid Close Not Triggering Suspend (Race Condition)

**Problem**: Sometimes closing the lid doesn't trigger suspend, especially if other events (AC plug/unplug) occur during the 2s debounce window.

**Root Cause**: HDM monitors power events and re-evaluates profiles when AC state changes. If a power event occurs during the suspend debounce:
1. HDM kills the `workspace-manager` script
2. The debounce loop dies before reaching `systemctl suspend`
3. Suspend never happens

**Solution**: Spawn suspend handler as a detached process using `setsid`:
- Parent creates lock file, spawns handler via `setsid bash -c "..." &`
- Handler runs in its own session, immune to parent termination
- HDM can kill/restart parent scripts freely
- Handler completes debounce and suspend independently

**Lock file mechanism**:
- Lock created in parent BEFORE spawning (prevents race)
- Lock cleaned up by handler via `trap ... EXIT`
- Stale locks (>30s) are removed automatically
- Prevents duplicate handlers from spawning

## Current Configuration Summary

| Feature | Solution | Location |
|---------|----------|----------|
| Block AC spurious wake | `acpi.ec_no_wakeup=1` | host config in the private host flake |
| Logitech USB wake | udev rule disable autosuspend | `nixos/core/pc.nix` |
| Phantom monitors on resume | hyprdynamicmonitors-resume service | `nixos/laptop/suspend-handling.nix` |
| Lockscreen crash prevention | Enable eDP-1 before DPMS on | `nixos/laptop/suspend-handling.nix` |
| Lid close suspend | Detached setsid handler with debounce | `home/.../scripts/workspace-manager.sh` |

## References

- [Arch Wiki: Power management/Wakeup triggers](https://wiki.archlinux.org/title/Power_management/Wakeup_triggers)
- [Kernel docs: /sys/power/pm_wakeup_irq](https://www.kernel.org/doc/Documentation/ABI/testing/sysfs-power)
- [Framework community: Thunderbolt dock wake issues](https://community.frame.work/t/laptop-powers-on-after-hibernate-when-unplugging-unpowering-dock/17622)

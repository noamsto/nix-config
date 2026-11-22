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

## Ownership

| Concern | Owner | Notes |
|---------|-------|-------|
| Lid-close suspend | systemd-logind | `HandleLidSwitch` / `HandleLidSwitchExternalPower` = suspend on laptops that are not `serverMode`; `HandleLidSwitchDocked` = ignore (serverMode ignores the lid entirely) |
| `system-awake` semantics | systemd-logind | The timed `handle-lid-switch:sleep` inhibitor blocks suspend while held. logind re-checks a closed lid continuously, so releasing the inhibitor (expiry or `system-awake off`), or unplugging the last external with the lid shut, suspends at once |
| Post-boot / post-resume holdoff | systemd-logind | `HoldoffTimeoutSec` = 30 s: lid events inside it are ignored |
| Monitor layout, workspace planner | hyprmoncfgd (user service) | Profile `exec` runs `hyprmoncfg-post-apply`, which sets Xft.dpi via `xresources-apply` |
| Clamshell panel-off | hyprmoncfgd | Panel disabled when docked with the lid shut |
| Resume DPMS wake, panel rescue | hyprmoncfgd | Retries until a render target exists, so the lockscreen does not crash |
| Idle lock, DPMS, suspend | hypridle | `after_sleep_cmd` is empty; displays are woken by hyprmoncfgd |
| Spurious AC-plug wakes | kernel `acpi.ec_no_wakeup=1` | See issue 1 |

`SleepOperation = "suspend"` is set because systemd 259 defaults the `Sleep()` D-Bus method to suspend-then-hibernate, which resolves to hybrid-sleep; anything calling `Sleep()` would otherwise hibernate unexpectedly. The login settings live in `nixos/core/default.nix`; the 30 s holdoff is logind's default.

## If phantom monitors return

If outputs stay enabled after undocking while suspended, reintroduce a oneshot ordered after `suspend.target` that disables the DRM-disconnected outputs:

```bash
hyprctl eval 'hl.monitor({ output = "<name>", disabled = true })'
```

The removed `hyprdynamicmonitors-resume` service did this: see `git show d03f2e75:nixos/laptop/suspend-handling.nix`. It runs as root, so it must export `XDG_RUNTIME_DIR=/run/user/<uid>` and pick the newest `HYPRLAND_INSTANCE_SIGNATURE` with `ls -t /run/user/<uid>/hypr/`; a stale socket dir otherwise gives "Couldn't connect".

## Debugging

```bash
journalctl --user -u hyprmoncfgd -f
hyprmoncfg status
hyprmoncfg doctor
systemd-inhibit --list
busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager Docked
journalctl -u systemd-logind
```

## Current Configuration Summary

| Feature | Solution | Location |
|---------|----------|----------|
| Block AC spurious wake | `acpi.ec_no_wakeup=1` | host config in the private host flake |
| Logitech USB wake | udev rule disable autosuspend | `nixos/core/pc.nix` |
| Lid close suspend | systemd-logind lid switch handling | `nixos/core/default.nix` (`logind.settings.Login`) |
| Monitor layout, panel rescue, resume DPMS wake | hyprmoncfgd | `home/desktop/hyprland/services/hyprmoncfg/` |
| Keep-awake | timed logind inhibitor | `home/desktop/hyprland/scripts/system-awake.nix` |

## References

- [Arch Wiki: Power management/Wakeup triggers](https://wiki.archlinux.org/title/Power_management/Wakeup_triggers)
- [Kernel docs: /sys/power/pm_wakeup_irq](https://www.kernel.org/doc/Documentation/ABI/testing/sysfs-power)
- [Framework community: Thunderbolt dock wake issues](https://community.frame.work/t/laptop-powers-on-after-hibernate-when-unplugging-unpowering-dock/17622)

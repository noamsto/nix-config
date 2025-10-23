# Hyprland Monitor Management - Verification Checklist

## Current Status
- ✅ hyprdynamicmonitors (HDM) running with lid events enabled
- ✅ Power events using correct path: `/org/freedesktop/UPower/devices/line_power_AC`
- ⏳ Testing in progress

## Critical Test Scenarios

### 1. Basic Lid Functionality (Undocked)
**Setup:** Laptop only, no external monitors

- [ ] **Close lid** → System should suspend immediately
  - Expected: Notification, hyprlock activates, suspend within 2 seconds
  - Status: ✅ PASSED (tested)

- [ ] **Open lid** → System resumes to undocked profile
  - Expected: Single laptop screen active, workspaces on eDP-1

### 2. Docked Lid Functionality
**Setup:** External monitors connected (Samsung at home OR Dell at work)

- [ ] **Dock laptop** → HDM switches to appropriate docked-lid-open profile
  - Expected: Correct profile based on monitor descriptions
  - Home: Samsung monitors detected → home-docked-lid-open
  - Work: Dell monitors detected → work-docked-lid-open

- [ ] **Close lid while docked** → Laptop screen disables
  - Expected: HDM switches to docked-lid-closed profile
  - Laptop screen (eDP-1) should be disabled
  - All workspaces should remain on external monitors
  - NO suspend (external monitors still connected)

- [ ] **Open lid while docked** → Laptop screen re-enables
  - Expected: HDM switches to docked-lid-open profile
  - Laptop screen (eDP-1) re-enabled
  - Workspaces 9-10 should move to laptop screen (if workspace scripts added)

### 3. ⚠️ CRITICAL EDGE CASE: Undock While Lid Closed
**This is the most important test for the "suspend on undock" requirement**

**Setup:** Docked with lid closed

- [ ] **Start docked with lid open** → verify correct profile
- [ ] **Close lid** → verify switched to docked-lid-closed
- [ ] **While lid still closed, physically disconnect laptop (unplug/undock)**
  - Expected behavior: IMMEDIATE SUSPEND
  - Why: lid=closed AND monitors=0 → should suspend
  - **This tests if HDM's post_apply_exec scripts check lid state**

**If this FAILS (stays awake):**
- HDM alone is insufficient
- Need unified solution or enhanced post_apply_exec scripts

### 4. Spurious Keyboard Events
**Setup:** Lid closed, external keyboard connected

- [ ] **Type on external keyboard** → No lid events should fire
  - Expected: No spurious lid-open events from keyboard
  - No unwanted profile switches
  - Check logs: `journalctl --user -u hyprdynamicmonitors.service -n 20`

### 5. Dynamic Workspace Allocation
**Setup:** Multiple docking locations (home vs work)

- [ ] **Dock at home (Samsung monitors)**
  - Verify workspaces assigned appropriately
  - Check which workspaces are on which monitors

- [ ] **Dock at work (Dell monitors)**
  - Verify workspaces assigned appropriately
  - Should work despite different monitor descriptors

- [ ] **Workspace persistence**
  - Open lid: workspaces 9-10 should move to eDP-1
  - Close lid: workspaces should stay on external monitors

**Current status:** Needs workspace movement scripts added to HDM post_apply_exec

### 6. Monitor Hotplug (Without Lid Events)
**Setup:** Lid open

- [ ] **Plug in external monitor** → HDM switches to docked profile
  - Check logs for monitor detection
  - Verify correct profile applied

- [ ] **Unplug external monitor** → HDM switches to undocked profile
  - Should detect monitor removal
  - Switch to undocked profile

## Decision Matrix

### If ALL tests pass with HDM:
**✅ Keep HDM + Add Enhancements:**
- Add workspace management to post_apply_exec scripts
- Add lid-state check to undocked profile script (for edge case #3)
- Simpler: uses proven tool for monitor detection

### If Test #3 FAILS (undock-while-lid-closed doesn't suspend):
**→ Use Unified Solution:**
- Single script handles all events
- Always checks both lid state AND monitor count
- Guaranteed to handle all edge cases
- More code to maintain, but more robust

## Files to Clean Up After Decision

### If keeping HDM:
- Remove: `home/desktop/hyprland/scripts/monitor-manager.sh`
- Remove: `home/desktop/hyprland/scripts/monitor-manager.nix`
- Remove: `home/desktop/hyprland/scripts/monitor-ipc-listener.sh`
- Remove: `home/desktop/hyprland/scripts/lid-handler.sh`
- Remove: `home/desktop/hyprland/scripts/lid-handler.nix`
- Disable: `systemd.user.services.hyprland-monitor-listener`
- Keep: HDM config, profiles, scripts (enhanced)

### If keeping Unified:
- Disable: `home.hyprdynamicmonitors.enable = false`
- Remove: `home/desktop/hyprland/services/hyprdynamicmonitors/` directory
- Keep: `monitor-manager.sh`, `monitor-manager.nix`, IPC listener service

## Outstanding Issues

### Workspace Allocation
**Current:** HDM doesn't manage workspaces
**Need:** Scripts to move workspaces based on monitor positions
- Implementation needed in either solution
- post_apply_exec scripts if using HDM
- Built into monitor-manager.sh if using unified

### hyprlock Best Practices
**Current:** ✅ Already correct
- hypridle configured with before_sleep_cmd
- Fingerprint enabled
- No changes needed

## Commands for Verification

```bash
# Check HDM status
systemctl --user status hyprdynamicmonitors.service

# Monitor HDM events
journalctl --user -u hyprdynamicmonitors.service -f

# Check current profile
ls -la ~/.config/hypr/monitors.conf

# Check lid state
cat /proc/acpi/button/lid/LID/state

# List connected monitors
hyprctl monitors | grep -E "(Monitor|description)"

# Check workspace assignments
hyprctl workspaces
```

## Next Steps

1. ⏳ **Test edge case #3** (undock while lid closed)
2. Based on results, finalize HDM vs unified decision
3. Implement workspace allocation
4. Clean up unused code
5. Document final configuration

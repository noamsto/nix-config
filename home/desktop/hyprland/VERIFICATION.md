# hyprmoncfg On-Hardware Checklist

hyprmoncfg replaced hyprdynamicmonitors. hyprmoncfgd owns layout, clamshell panel-off, resume DPMS wake and the workspace planner; systemd-logind owns lid-close suspend (see `docs/power-management.md`).

## Docking

- [ ] **Dock**: externals lit, workspaces 1-4 on the left monitor, 5-8 on the right, 9 on the panel, Xft.dpi 96
- [ ] **Undock**: panel at laptop scale, workspaces 1-9 on the panel, Xft.dpi at the laptop value

## Lid, docked

- [ ] **Close lid**: panel off, workspace 9 moves to the right monitor (when the profile's `monitor_order` lists right first), no suspend
- [ ] **Open lid**: panel back

## Lid, undocked

- [ ] **Close lid**: suspends (after up to 30 s of logind holdoff if the machine just resumed)
- [ ] **Close lid with `system-awake` active**: no suspend
- [ ] **`system-awake off` with the lid shut**: suspends at once
- [ ] **serverMode host, close lid**: stays awake

## Resume

- [ ] **Resume with lid open**: panel lit
- [ ] **Undock while suspended, then resume**: panel lit, no phantom outputs
- [ ] `hyprmoncfg doctor` passes

## Debugging

```bash
journalctl --user -u hyprmoncfgd -f
hyprmoncfg status
hyprmoncfg doctor
systemd-inhibit --list
busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager Docked
journalctl -u systemd-logind
cat /proc/acpi/button/lid/LID/state
hyprctl monitors | grep -E "(Monitor|description)"
hyprctl workspaces
```

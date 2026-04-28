# profile-sync-daemon removal — per-host migration

`services.psd` was removed from the config in commit `75d96c6` (2026-04-28).
The Nix change is global, but each host that previously ran psd has persistent
on-disk state that needs a one-time cleanup the first time it switches to a
generation without psd. **Delete this file once all hosts are ✅.**

## Why a manual step is needed

While psd was running it replaced `~/.config/mozilla/firefox/default/` with a
symlink to a tmpfs path under `/run/user/$UID/psd/...` and stashed the persistent
copy in `default-backup/`. When NixOS switches to a generation that no longer
declares the unit, it stops `psd.service` and runs its `ExecStop`
(`profile-sync-daemon unsync`), which rsyncs tmpfs back to `default-backup/`,
removes the symlink, and renames `default-backup/` → `default/`.

If firefox is **open** during the switch the profile files are locked and
unsync can race itself, leaving a half-migrated state (dangling symlink +
stale `default-backup/`). Closing firefox first avoids the race.

## Steps (run on the host being migrated)

```fish
# 1. Close firefox completely. unsync needs the profile files unlocked.
pkill -x firefox; sleep 2

# 2. Pull and apply. psd.service is stopped and unsync runs as the unit
#    is removed by switch-to-configuration.
cd ~/nix-config
git pull
nh os switch

# 3. Verify on-disk state.
ls -la ~/.config/mozilla/firefox/ | rg 'default'
#  Want: 'default' as drwx------ (real directory, no '->'),
#        and no 'default-backup' line.

# 4. (Optional) Remove leftover dangling symlinks for old/unused profiles —
#    they may exist if psd was once managing additional profiles. Anything
#    pointing into /run/user/.../psd/... can go.
ls -la ~/.config/mozilla/firefox/ | rg '/run/user'
# gtrash put any matches.

# 5. Reboot, then confirm boot HM activation now exits cleanly:
journalctl -b 0 -u home-manager-noams.service | tail -20
#  Want: 'Activating ...' for every step including reloadSystemd, restoreTheme,
#        flatpak-managed-install, xfconfSettings; service reaches 'active (exited)'.
#  Pre-fix the journal showed:
#    mkdir: cannot create directory '.../mozilla/firefox/default': File exists
#    ln: failed to create symbolic link '.../default/.keep': No such file or directory
#    home-manager-noams.service: Failed with result 'exit-code'.
```

## Recovery

If step 3 still shows `default ->` (symlink) or `default-backup/` is still
there — firefox was up, unsync raced. Recover with:

```fish
pkill -x firefox; sleep 2
gtrash put ~/.config/mozilla/firefox/default                                # dangling symlink
mv ~/.config/mozilla/firefox/default-backup ~/.config/mozilla/firefox/default
```

## Per-host status

- `thinkpad-p14s-g5`: ✅ migrated 2026-04-28
- `thinkpad-p14s-g6`: ⏳ pending — apply on next login
- `thinkpad-p14s`:    ⏳ pending — apply if still in use; if retired, mark ✅

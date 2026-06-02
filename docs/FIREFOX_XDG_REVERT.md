# Firefox profile path — XDG → legacy revert (per-host migration)

`programs.firefox.configPath` was reverted from `${config.xdg.configHome}/mozilla/firefox`
back to the firefox-default `~/.mozilla/firefox/`, undoing commit `f3753ed`
(2026-04-26). The Nix change is global, but each host has on-disk profile state
that needs to be physically moved from the XDG path to the legacy path.
**Delete this file once all hosts are ✅.**

## Why

After `f3753ed` (XDG path) and `75d96c6` (psd removal, 2026-04-28), firefox
sometimes spawned a fresh profile at `~/.mozilla/firefox/<random>.default/`
during HM activation symlink swap, despite the configPath pointing at XDG.
`MOZ_LEGACY_HOME` is unset and FF 147+ should default to XDG, but the binary
still lands in `~/.mozilla/firefox/` when it can't find an XDG `profiles.ini`
at launch — looks like an upstream gap (see chat history 2026-04-30). Aligning
HM with FF's own preferred path eliminates the second location entirely so the
race can't recur.

## Steps (run on the host being migrated)

```fish
# 1. Close firefox completely. The XDG profile must be unlocked to move it.
pkill -x firefox; sleep 2

# 2. Pull the config change (configPath drop).
cd ~/nix-config
git pull

# 3. Discard the empty fresh profile created by the fallback (if present).
test -e ~/.mozilla/firefox; and gtrash put ~/.mozilla/firefox

# 4. Move the real profile to FF's native location.
mv ~/.config/mozilla/firefox/default ~/.mozilla/firefox/default

# 5. Clean up the now-empty XDG remnants (Profile Groups, Crash Reports,
#    the HM-managed profiles.ini symlink).
gtrash put ~/.config/mozilla/firefox

# 6. Apply. HM regenerates ~/.mozilla/firefox/profiles.ini.
nh home switch

# 7. Verify.
ls -la ~/.mozilla/firefox/
#  Want: 'default' as drwx------ (your real profile, ~100M+, has extensions/),
#        'profiles.ini' present (HM-managed),
#        no '<random>.default' fresh profile.

# 8. Open firefox. Should land on your real profile (extensions, history, tabs).
```

## Per-host status

- `thinkpad-p14s-g6`: ✅ migrated 2026-04-30
- `thinkpad-p14s-g5`: ⏳ pending

# HANDOFF — lazytmux darwin port (in progress)

Started 2026-06-02. Goal: make `lazytmux` work on macOS (`mbp-m4-pro`) so kitty/ghostty
launch tmux instead of crashing, with FiraCode rendering.

## State (all pushed)

- **lazytmux** (`~/Data/git/noamsto/lazytmux`): branch `feat/darwin-launchd` (`b546187`).
  `modules/home-manager.nix` is now a `mkMerge` of `mkIf isLinux { systemd.user = … }`
  (unchanged) and a new `mkIf isDarwin { launchd.agents = … }` mirroring the 3 units
  (`tmux-startup` → RunAtLoad, `lazytmux-state-save` → StartInterval, `lazytmux-state-gc`
  → weekly), minus the systemd-isms (`%t`/`TMUX_TMPDIR`, import-environment,
  graphical-session.target). Shared startup script + `persistEnabled` hoisted to the
  top-level `let`. The **Linux** build was regression-tested and still works.
- **nix-config** (`main`, `427e7b8`): un-gated `programs.lazytmux`; kitty/ghostty startup
  commands are platform-aware (darwin: `tmux attach || tmux new` on the default /tmp
  socket, no `systemctl`/`/run/user`); added `fonts.packages` (nerd-fonts incl. FiraCode)
  to `hosts/mbp-m4-pro`. The lazytmux flake input is **NOT bumped** — tested via
  `--override-input`.

## Build it on the Mac

```fish
cd ~/nix-config && git pull

# lazytmux branch (path override = edits picked up without pushing)
cd ~/Data/git/noamsto && git clone git@github.com:noamsto/lazytmux.git
cd lazytmux && git switch feat/darwin-launchd

cd ~/nix-config
sudo nix run nix-darwin -- switch --flake .#mbp-m4-pro \
  --override-input lazytmux path:$HOME/Data/git/noamsto/lazytmux
```

## Remaining work

1. **Get the darwin build green.** Biggest risk: `tmux-state` (Go) has never been built
   on aarch64-darwin. If it fails to build, gate `persist` to Linux as a fallback
   (`persist.enable = pkgs.stdenv.hostPlatform.isLinux;` in the nix-config lazytmux block,
   or condition the launchd save/gc agents out).
2. **Verify behavior:** kitty + ghostty attach the `nix-config` tmux session; FiraCode
   Nerd Font renders; (from earlier commits) nix apps appear in Spotlight, no Gatekeeper
   quarantine prompts, no "Refusing to untap" nag.
3. **Finalize:**
   ```fish
   cd ~/Data/git/noamsto/lazytmux && git switch main && git merge feat/darwin-launchd && git push
   cd ~/nix-config && nix flake update lazytmux
   git commit -am "chore(flake): bump lazytmux (darwin support)" && git push
   ```
   Then drop the `--override-input` and delete this file.

## Notes

- Can't build/test darwin from the Linux box (g5) — the Mac is the only verifier, hence
  the path-override dev loop.
- Other macOS fixes already landed this session: `mac-app-util` (Spotlight/Launchpad),
  `homebrew.caskArgs.no_quarantine`, `nix-homebrew.autoMigrate`, freecad cask dropped
  (install the official .dmg), and two `rev = "main"/"master"` fetchers pinned to commits.

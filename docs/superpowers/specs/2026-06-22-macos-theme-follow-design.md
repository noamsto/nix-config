# Design: Follow macOS Appearance for Light/Dark Theme

**Issue:** [#24](https://github.com/noamsto/nix-config/issues/24)
**Date:** 2026-06-22
**Status:** Approved design — pending implementation plan

## Problem

On macOS (`mbp-m4-pro`) light/dark theming does not work:

- System appearance is pinned to `Dark` via `AppleInterfaceStyle = "Dark"` in
  `hosts/mbp-m4-pro/default.nix` — a fixed value, not "follow" and not a toggle.
- The runtime theme-switching machinery (`theme-toggle`, the Catppuccin
  Mocha↔Latte swap, per-app config rewriting, live reload) lives under
  `home/desktop/hyprland/scripts/`. That tree is gated behind
  `osConfig.desktop.mode != "none"` (`home/noams.nix`), and the Mac has
  `desktop.mode = "none"` (`lib/host-configs.nix`). So none of it is imported on
  macOS.
- Result: terminal/CLI apps on the Mac are frozen on a static dark theme
  (e.g. kitty bakes a fixed `include themes/catppuccin-mocha.conf`) and do not
  follow the OS.

## Goal

CLI/terminal apps on macOS follow the system Light/Dark appearance
**automatically** — the OS is the single source of truth, no keybind. Parity
with the Linux setup for every themeable app that actually runs on the Mac.

## Behavior decisions (from brainstorming)

- **Trigger model:** follow macOS appearance (chosen over a manual toggle or a
  both-ways hybrid).
- **Scope:** full parity — every themeable app that runs on the Mac.
- **Code sharing:** extract a shared CLI core used by both platforms (chosen over
  a duplicated standalone macOS script), because the per-app theming logic is
  exactly what would drift if duplicated, and it is cleanly separable from the
  Linux-only orchestration.

## Coupling analysis (why extraction is feasible)

The current `home/desktop/hyprland/scripts/sh/theme-toggle.sh` splits into a
reusable per-app layer and a Linux-only orchestration layer — but the split is
**not** as clean as "every `update_*` is neutral." Three in-scope updaters carry
Linux coupling that must be handled (see below).

| Layer | Examples | Platform |
|-------|----------|----------|
| Per-app `update_*` (config-file) | kitty, starship, btop, lazydocker, process-compose, delta, yazi, lazygit | **Neutral** — rewrite a `$XDG_CONFIG_HOME` file via `sed`/`cat`, driven by palette env-vars |
| Per-app `update_*` (fish-only reload) | fish | **Neutral** — `fish -c __reload_theme`; theme files in `home/terminal/fish` |
| Per-app `update_*` (Linux-coupled) | `update_bat`, `update_fzf`, `update_tmux` | **Needs porting** — see finding below |
| Palette → env-var injection | `theme-toggle.nix` lines 64–139 + external theme fetches (lazygit, yazi) | **Neutral** — pure data |
| Orchestration / source-of-truth | `toggle_theme` (Noctalia IPC), `apply_theme_command` (Noctalia hook), `restore_theme` | **Linux-only** |
| Signaling | `signal_apps`, `restart_service` (systemctl), `notify-send` | **Linux-only** |
| Desktop updaters | GTK, Hyprland borders, KDE colorscheme, kvantum, noctalia, vicinae, foot, ghostty | **Linux-only** |

**There is no reusable `apply <dark|light>` seam.** The `apply` subcommand
(`theme-toggle.sh:1485`) calls `apply_theme_command` → `apply_theme_from_noctalia`
(`sh:1249`), which runs the *full* updater list (including all Linux-only desktop
updaters), then `_run_updates_parallel` unconditionally calls `signal_apps`
(`sh:1245`, systemctl restarts), then `write_state`, then `notify-send`. The
macOS driver therefore **cannot** call `apply`. The neutral seam that actually
exists is one layer lower: each `update_*` takes the target theme as an argument.

The shared lib must expose (a) the neutral `update_*` functions and (b) a
parallel runner *without* the `signal_apps`/notify tail. **Each platform wrapper
builds its own updater-list entry point** on top of that — Linux keeps its full
list + orchestration; macOS defines a macOS-only list (below).

### Linux-coupled updaters that need porting

- **`update_bat`** (`sh:943`) and **`update_fzf`** (`sh:1074`) write **no config
  file**. They set a fish universal var (`set -U BAT_THEME` / fzf colors) *plus*
  `systemctl --user set-environment` and `hyprctl keyword env`. On macOS the
  latter two no-op. Decision: **fish-universal propagation only** on macOS — bat
  and fzf retheme for fish-launched processes (the normal interactive path);
  already-running non-fish processes are not retroactively rethemed. Acceptable
  because both are invoked fresh per command from the interactive fish shell.
- **`update_tmux`** (`sh:702`) hard-codes the Linux socket
  `/run/user/$(id -u)/tmux-$(id -u)/default` as its non-`$TMUX` fallback. The
  macOS lazytmux server uses a `/tmp` socket and the launchd-fired watcher has no
  `$TMUX`. The shared function needs a platform-aware socket-discovery path (or
  the macOS list passes the correct socket).

## Changes to the current (Linux) solution

These make theming a first-class cross-platform concern instead of a Hyprland
appendage. Linux runtime behavior is unchanged — only file locations and the
lib/orchestration seam move.

1. **Promote theming to a cross-platform `home/theme/` module**, imported on both
   platforms, holding:
   - `palette.nix` (moved from `home/desktop/theme/palette.nix` — it is already
     imported unconditionally, so this makes its location honest)
   - `lib/theme-apply.sh` — the shared `update_*` functions plus helpers
     (`log_*`, `record_failure`, `collect_parallel_failures`) and a neutral
     parallel runner **without** the `signal_apps`/notify tail. The three
     Linux-coupled updaters (`update_bat`, `update_fzf`, `update_tmux`) are made
     platform-aware here so both wrappers can call them.
   - `palette-env.nix` — the palette → env-var export block and external theme
     fetches (catppuccin-lazygit, catppuccin-yazi)
   - the `programs.theme-toggle` option. Its `package` value must **not** carry a
     single cross-platform `default` that bakes Linux deps (hyprland, dconf,
     quickshell). Each platform wrapper assigns the option to *its own* derivation
     (Linux: full orchestration + Linux deps; macOS: core-deps-only driver), so
     the Mac closure never pulls Linux-only packages.
2. **Each platform owns its updater-list entry point** (no shared `apply`
   subcommand — see coupling analysis). The macOS driver defines a macOS-only
   list and a parallel runner with no orchestration tail.
3. **Split `runtimeInputs`** into a cross-platform core set (sed, grep, jq, kitty,
   fish, tmux, coreutils, findutils, gawk) consumed by both wrappers, vs a
   Linux-orchestration set (hyprland, dconf, quickshell, libnotify, kvantum,
   networkmanagerapplet) added only by the Linux wrapper.
4. **Audit per-app asset generation** so the Mac has light+dark assets for each
   in-scope app. Any generator currently under `home/desktop` for a surviving app
   must move to the shared module or `home/terminal`.

**Deliberately not changed (scope guard):** the ~60-var palette→env-var transport
is verbose but works and is pure data. It gets factored out (change #1) but is
**not** redesigned into a generated JSON/file the lib reads.

## Target architecture

```
home/theme/                         (NEW, cross-platform, imported on both)
├── default.nix                     module entry; defines programs.theme-toggle option
├── palette.nix                     (MOVED from home/desktop/theme/)
├── palette-env.nix                 palette → env-var block + external fetches
└── lib/
    └── theme-apply.sh              shared update_* functions + helpers

home/desktop/hyprland/scripts/      (Linux orchestration, consumes home/theme)
└── theme-toggle.nix                Linux wrapper: core deps + Linux deps,
    sh/theme-toggle.sh              sources theme-apply.sh; keeps Noctalia/
                                    systemctl/notify + desktop updaters

home/darwin/theme/                  (NEW, macOS driver)
└── default.nix                     theme-apply-macos script + launchd watch
                                    agent + HM-clobber clean/apply activation
```

### macOS driver

- **`theme-apply-macos` script** (`pkgs.writeShellApplication`):
  - reads appearance: `defaults read -g AppleInterfaceStyle` → exit 0 with `Dark`
    means dark; non-zero/empty (the key is absent in Light mode) means light
  - injects the shared palette env-vars (via `palette-env.nix`), sources
    `lib/theme-apply.sh`, runs the **macOS updater list** in parallel via the
    no-tail runner:
    `update_kitty update_fish update_starship update_btop update_tmux`
    `update_lazydocker update_process_compose update_bat update_delta`
    `update_fzf update_yazi update_lazygit`
  - no `notify-send`, no `systemctl`, no desktop updaters
  - core `runtimeInputs` only (must include `kitty` for `kitty @`, `fish`,
    `tmux`, `bat`/`fzf` are reached via fish)
- **`launchd.agents.theme-watch`** (Home Manager — `launchd.agents.<name>.config`
  maps directly to the plist, so `WatchPaths`/`RunAtLoad` are supported):
  - `WatchPaths = [ "~/Library/Preferences/.GlobalPreferences.plist" ]` — this
    plist is rewritten on appearance change, firing the agent
  - `RunAtLoad = true` — applies correct theme on login
  - the script is idempotent (re-reads current appearance and applies), so
    spurious `.GlobalPreferences` writes are harmless. `.GlobalPreferences`
    changes for many unrelated reasons, so the script must early-exit cheaply
    when the resolved theme already matches the last-applied state (a small
    state file), to avoid redundant work on every global-pref write.

### macOS HM-clobber handling (required)

The neutral updaters `rm -f` and replace Home-Manager symlinks they edit (kitty
`sh:455`, yazi `sh:1138`, lazygit `sh:573`, starship in place). On Linux,
`home/desktop/theme/catppuccin.nix` runs a `cleanThemeFiles` activation that
deletes these mutated files *before* HM's `checkLinkTargets`, otherwise the next
rebuild fails with "file would be clobbered." That activation is Linux-gated. The
macOS module **must provide its own equivalent**: a `home.activation` step that
removes the theme-mutated files before link-checking, plus an apply-on-activation
(`theme-apply-macos`) so a fresh `nh darwin switch` lands themed. Without this the
second `darwin switch` after any theme flip will fail.

### Data flow

```
macOS appearance flip
  → ~/Library/Preferences/.GlobalPreferences.plist rewritten
  → launchd fires theme-apply-macos
  → reads AppleInterfaceStyle → dark|light
  → sources shared lib, runs update_* in parallel
  → each updater rewrites its app config + live-reloads running instances
```

## Apps in scope

kitty, fish, starship, btop, lazydocker, process-compose, tmux, bat, delta, fzf,
yazi, lazygit.

Each updater edits a config another module generated. Per-app asset audit
(confirm on the Mac that light+dark assets exist and the edited config is
writable):

| App | Asset source | Reload mechanism | Mac status to verify |
|-----|--------------|------------------|----------------------|
| kitty | `home/terminal/kitty` (cross-platform) | `kitty @ --to unix:$sock` over `/tmp/kitty-*` glob | themes dir generated ✅; **verify socket glob matches macOS kitty** (`listen_on = unix:/tmp/kitty`, `kitty/default.nix:113`) |
| fish | `home/terminal/fish` (`__reload_theme`) | `fish -c __reload_theme` + `set -U` event | function present ✅ (verify) |
| starship | starship.toml `palette =` line | new prompt picks up edited file | confirm config exists + writable on Mac |
| btop | `home/terminal/btop.nix` | config rewrite (restart-on-next-launch) | confirm light+dark themes present |
| tmux | lazytmux (cross-platform) | `tmux set` over socket | **macOS socket path** (not `/run/user/...`) |
| lazydocker | `home/terminal/lazydocker.nix` | config rewrite | confirm config present + writable |
| process-compose | `home/terminal/process_compose` | config rewrite | confirm config present |
| bat | none — `set -U BAT_THEME` | **fish-universal only on macOS** (no config file) | confirm fish var path works; non-fish processes not retroactive |
| delta | `~/.config/git/theme-override` include (`git/default.nix:40`) | git re-reads include file | confirm include path active on Mac |
| fzf | none — fish-universal colors | **fish-universal only on macOS** (no config file) | confirm fish var path works |
| yazi | env store path (fetchFromGitHub) | config rewrite (HM-symlink replace) | cross-platform fetch ✅; clobber-clean needed |
| lazygit | `home/git/lazygit.nix` + env store path | config rewrite (HM-symlink replace) | confirm config writable; clobber-clean needed |

Apps generated only under `home/desktop` for a surviving app must be relocated to
the shared module or `home/terminal` during the audit.

**k9s** is intentionally excluded: it lives in `home/kubernetes` (work-profile
only) and is not present on the personal Mac, so its Linux `update_k9s` updater
has no macOS counterpart.

## Out of scope (no macOS equivalent)

GTK, Hyprland borders, KDE colorscheme, kvantum, noctalia, vicinae, foot. The
Linux orchestration that drives these stays untouched under `home/desktop`.

**Remove the `AppleInterfaceStyle = "Dark"` pin** from
`hosts/mbp-m4-pro/default.nix:281`. It is under `system.defaults.NSGlobalDomain`,
which nix-darwin **reasserts on every `darwin switch`** — so leaving it would
silently reset appearance to Dark after any rebuild, directly contradicting "the
OS is the single source of truth." Removing it lets macOS persist the user's
runtime choice (manual flip or System Settings → Auto/sunset). The watcher then
follows whatever the OS reports. (If a default-dark on a brand-new machine is
desired, set it once out-of-band rather than pinning it in Nix.)

## Implementation waves

1. **Shared-core refactor (Linux behavior unchanged).** Create `home/theme/`,
   move `palette.nix`, extract `lib/theme-apply.sh` (incl. the neutral no-tail
   parallel runner) + `palette-env.nix`, make `update_bat`/`update_fzf`/
   `update_tmux` platform-aware, split `runtimeInputs`, give the
   `programs.theme-toggle` option a per-platform package (no Linux-deps default),
   rewire the Linux wrapper to source the shared lib. Verify: `nh home switch` on
   Linux + one manual toggle behaves identically (all previously-working apps
   still switch and live-reload).
2. **macOS driver + core terminal apps.** Create `home/darwin/theme/`:
   `theme-apply-macos` script, launchd `theme-watch` agent, the HM-clobber clean
   + apply-on-activation step, and remove the `AppleInterfaceStyle` pin. Wire
   kitty/fish/starship/btop/tmux assets cross-platform; **verify the kitty socket
   glob matches on macOS** and the tmux socket path resolves. Verify: flip macOS
   appearance, confirm these apps follow; run `nh darwin switch` twice across a
   flip to confirm no clobber failure.
3. **Remaining apps.** lazydocker, process-compose, bat (fish-universal),
   delta, fzf (fish-universal), yazi, lazygit asset audit + wiring. Verify each
   follows the OS flip.

## Risks / validation

- **`.GlobalPreferences.plist` WatchPaths firing** is a community-established
  technique but must be validated on this macOS version; fallback is a low-rate
  polling launchd agent (`StartInterval`) if WatchPaths proves unreliable.
- **Refactor regression on Linux** — mitigated by wave 1 being mechanical
  (move functions into a sourced file) and re-tested with a live toggle.
- **Per-app asset gaps on Mac** — surfaced by the audit table; each is verified
  before claiming that app done.

## Testing

- Linux: `nh home switch`, then toggle dark↔light; every previously-working app
  still switches and live-reloads.
- macOS: `nh darwin switch`, then flip System Settings → Appearance Light↔Dark;
  each in-scope app's running instances and new instances pick up the new theme.
  Also verify `RunAtLoad` applies the correct theme on a fresh login.

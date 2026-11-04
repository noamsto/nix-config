# Noctalia 5 migration

Issue: [#215](https://github.com/noamsto/nix-config/issues/215)
Branch: `feat/215-noctalia-v5`
Date: 2026-09-06

## Problem

Noctalia v5.0.1 went stable 2026-09-03. `flake.nix` pins the last v4 rev
(`5311e14`) with a note to unpin once migrated. v5 is a rewrite, not a schema
bump: the upstream repo moved from `noctalia-dev/noctalia-shell` to
`noctalia-dev/noctalia` (v4 parked on the `legacy-v4` branch), the shell core is
now C++ rather than quickshell/QML, and both the config format and the CLI
changed shape.

The migration is not confined to `home/desktop/noctalia/default.nix`. Five other
files reference the old binary, and three integration points break *silently* —
they keep building and keep running, but do the wrong thing.

## Upstream facts

Established by reading the v5.0.1 tag directly (`nix/home-module.nix`,
`src/cli/schema_*.h`, `src/config/config_migrations.{h,cpp}`, `nix/package.nix`,
and `docs/user/**`), not from release-note prose.

### Renames

| Area | v4 | v5 |
|---|---|---|
| HM option | `programs.noctalia-shell` | `programs.noctalia` |
| Config file | `~/.config/noctalia/settings.json` | `~/.config/noctalia/config.toml` |
| Key style | camelCase | snake_case |
| Binary / `mainProgram` | `noctalia-shell` | `noctalia` |
| IPC | `noctalia-shell ipc call X` | `noctalia msg X` |
| Liveness probe | `noctalia-shell list` | **removed** |
| Plugin id | `<6-hex-sha256(sourceUrl)>:<manifest-id>` | `<author>/<plugin>` |
| Plugin sources | `noctalia-plugins` | `official-plugins` + `community-plugins`, both built in |
| Bar table | `bar` | `bar.default` (bars are named) |
| Theme table | `colorSchemes` | `theme` |
| Widget key | `id = "Clock"` | `type = "..."` |

v5 root CLI subcommands are exactly: `completions`, `config`, `dmenu`,
`firefox-theme`, `msg`, `plugins`, `theme`. There is no `ipc` and no `list`.

### Two-layer config model

This is the central change and it resolves the long-standing Nix-vs-GUI fight.

1. Built-in defaults
2. **Yours** — every `*.toml` in `~/.config/noctalia/` (merged alphabetically;
   `[include]` controls order and pulls in subdirectories)
3. **Noctalia's** — `~/.local/state/noctalia/settings.toml`, written by the GUI
   and IPC, wins over layer 2

Upstream states the split exists so "the GUI [can] save changes when your config
directory is read-only, for example on NixOS". Consequences for us:

- `xdg.configFile."noctalia/settings.json".force = true` is deleted. Nothing
  fights over the file any more.
- **Gotcha:** because layer 3 wins, a value tweaked once in the GUI keeps
  overriding the Nix value forever. Changing the Nix value later appears to do
  nothing. The fix is to delete the key (or the file) from
  `~/.local/state/noctalia/settings.toml`. Worth a note in `CLAUDE.md`.

### Build-time validation, and its limit

`programs.noctalia.checkConfig` (default `true`) runs `noctalia config validate`
on the generated TOML inside the nix build.

It reports two severities, and the distinction decides our verification strategy:

- **Errors** (exit 1, fails the build): TOML syntax, unparseable values, invalid
  enum/color, out-of-range cross-field combinations.
- **Warnings** (exit 0, build passes): **unknown or obsolete settings**, values
  with a canonical replacement, clamped ranges.

A mistranslated key is a *warning*. The build goes green and the setting
silently vanishes. So warnings — not build success — are the signal we grade
against.

### No v4 importer exists

`config_migrations.cpp` operates on `toml::table&` and is stamped with
`config_version`; it migrates v5 TOML shapes forward (e.g. negative radii →
`concave_edge_corners`, workspaces display → `label_source`/`show_labels`). It
does **not** read v4 JSON. The `config` subcommands are `validate`, `export`,
`settings-count`, `replay-report` — none imports v4.

Therefore the v4 → v5 settings translation is entirely ours to do.

### Hooks

Key names changed and, more dangerously, **payloads moved from positional `$1`
to environment variables**:

| v4 | v5 | Payload |
|---|---|---|
| `wallpaperChange` | `wallpaper_changed` | `$NOCTALIA_WALLPAPER_PATH`, `$NOCTALIA_WALLPAPER_CONNECTOR` |
| `darkModeChange` | `theme_mode_changed` | `$NOCTALIA_THEME_MODE` (`dark`/`light`), `$NOCTALIA_THEME_MODE_PREVIOUS`, `$NOCTALIA_THEME_MODE_CONFIGURED` |
| — | `colors_changed` | fires after palette resolves and templates are written |

### Native calendar

v5 speaks CalDAV, iCloud, Google (browser OAuth; refresh token in Secret
Service), ICS, and local vdir directly from C++ (`src/calendar/*.cpp`).
`nix/package.nix` carries no evolution-data-server wrapping. Accounts are
declared as `[calendar.account.<id>]`, and CalDAV passwords can come from a
`password_file` — agenix-compatible, though Google does not need one.

### Cache

Upstream: `inputs.nixpkgs.follows` changes the derivation hash and **disables**
`noctalia.cachix.org`. Our input sets `follows`, so the cachix entry in
`flake.nix` is currently dead weight and every host compiles locally. The
`cachix` branch is upstream's pointer to the latest already-built commit.

## Decisions

| Decision | Choice | Why |
|---|---|---|
| Settings derivation | Export from a live sandboxed v5 run | Key names are observed from the app, not guessed. Unknown keys only warn, so guessing loses settings invisibly. |
| Rollout | One atomic PR, prep on this branch | A half-migrated tree does not run — binary name, config schema and hooks must land together. |
| Calendar wrapper | Delete, use native | ~25 lines of `symlinkJoin` + typelib plumbing become redundant. Costs one browser re-auth. |
| aegis-lock colors | v5 template writes `colors.json` | Templates are v5's intended cross-app colour mechanism; keeps aegis-lock unchanged. |
| Flake input | Drop `follows`, pin `cachix` branch | Restores cache hits, which now matter because the core is C++. Costs a second nixpkgs in the lock. |
| Crash monitor | Evaluate in Phase 0, expect to delete | Its cited blocker (upstream #1323) has been closed since 2026-02-15, predating our current pin; v5's state split removes the mechanism entirely. |
| Test host | `thinkpad-p14s-g5` | Exercises the `spacious` bar-density conditional; already past the psd migration (g6 still has pending on-disk cleanup that would tangle in). |

## Plan

### Phase 0 — sandbox spike (non-destructive)

Bump the flake input, build v5, and run it against a scratch profile:

```fish
env NOCTALIA_CONFIG_HOME=/tmp/n5 NOCTALIA_STATE_HOME=/tmp/n5-state noctalia
```

These Noctalia-specific vars have the same "home root" shape as the XDG ones and
do not leak into apps launched from the shell, so the live v4
`~/.config/noctalia` is never touched and aborting costs nothing.

Answer three questions here:

1. **Does a systemd restart preserve GUI settings?** The crash-monitor's comment
   cites "upstream open issue #1323" as the reason we relaunch via
   `hyprctl dispatch` instead of a systemd unit — but #1323 was **closed as
   completed on 2026-02-15**, before the rev we are currently pinned to. The
   justification is already stale on v4, and v5 additionally moved GUI settings
   out of the config file into `state/settings.toml`, which is the mechanism
   that broke. So the expected outcome is that
   `programs.noctalia.systemd.enable = true` replaces the 160-line monitor
   outright; verify by restarting the unit and confirming settings survive.
   Note the monitor also caps restarts (5 per 60s) against crash-looping —
   systemd covers that natively with `Restart=on-failure` plus
   `StartLimitBurst`/`StartLimitIntervalSec`, so that capability is not lost.
   Upstream also recommends enabling `launch_apps_as_systemd_services` when
   running under the unit, so apps launched from the shell survive a restart.
2. **What are the theme-mode `noctalia msg` commands?** Needed for
   `theme-toggle.sh`. Read from `docs/user/ipc/shell-and-ui.mdx` and confirm
   against `noctalia msg --help`.
3. **Full v5 key list** — `noctalia config export full` dumps every built-in
   default, giving the authoritative schema to grade our translation against.

### Phase 1 — derive settings

Reproduce the current setup in the sandbox GUI (bar layout, widgets, control
centre cards and shortcuts, theme, wallpaper, night light, session menu), then:

```fish
env NOCTALIA_CONFIG_HOME=/tmp/n5 NOCTALIA_STATE_HOME=/tmp/n5-state noctalia config export merged > cfg.toml
```

Convert `cfg.toml` into the Nix attrset. The existing v4 attrset is the
**checklist** — every one of its settings must be accounted for as
translated, deliberately dropped, or newly defaulted — but never the source of
key names.

### Phase 2 — module rewrite

`home/desktop/noctalia/default.nix`:

- `programs.noctalia-shell` → `programs.noctalia`; `settings` as a TOML attrset;
  leave `checkConfig` at its default `true`.
- Delete `upstreamNoctalia`/`noctaliaPackage` `symlinkJoin`,
  `calendarTypelibPath`, `calendarBinPath`; point `package` straight at
  `inputs.noctalia.packages.${system}.default`.
- Drop `pkgs.gnome-calendar` and `pkgs.gnome-control-center` from
  `home.packages`; re-check `evolution-data-server` in
  `nixos/hyprland/gnome-services.nix` (its comment cites Noctalia as the reason).
- Plugins → `[plugins] enabled = ["<author>/<plugin>"]` plus `[[plugins.source]]`.
  The `pluginSource` custom source is likely unnecessary now that `official` and
  `community` ship built in. `pluginSettings.tailscale` moves to v5's plugin
  settings shape.
- `noctalia-ipc` wrapper → `noctalia msg`.
- Delete `xdg.configFile."noctalia/settings.json".force`.
- Delete the composite-key gotcha from `CLAUDE.md` (v5 ids are plain
  `<author>/<plugin>`); add the layer-3-override gotcha in its place.

### Phase 3 — hooks and theme pipeline

Highest-risk phase; both current hooks fail silently under v5.

- `wallpaperChange` → `wallpaper_changed`, using `$NOCTALIA_WALLPAPER_PATH`.
- `darkModeChange` → `theme_mode_changed`, using `$NOCTALIA_THEME_MODE`
  (already `dark`/`light`, so the `$1 = "true"` ternary disappears entirely).
- `theme-toggle.sh:361 update_noctalia()` currently edits
  `$XDG_CONFIG_HOME/noctalia/settings.json` by hand. Under v5 that writes to the
  *config* layer, which the app never rewrites and the GUI layer would override
  anyway. Replace with the `noctalia msg` theme command found in Phase 0.
- `theme-toggle.sh:630` `pgrep -f "quickshell.*noctalia-shell"` →
  `pgrep -f '/bin/noctalia$'`; the `noctalia-ipc --pid` call becomes plain
  `noctalia msg`, since v5 has a single socket at `$XDG_RUNTIME_DIR` rather than
  per-instance quickshell directories.

### Phase 4 — aegis-lock

`colors.json` no longer exists in v5; only *input* palettes live at
`~/.config/noctalia/palettes/`. Read aegis-lock's `colors.json` schema, then
write a v5 template rendering it from `{{ colors.<role>.<mode>.<format> }}`
tokens with `output_path` pointing at aegis-lock's config path. Replace the
`mkOutOfStoreSymlink`. Confirm the template's token coverage actually spans
aegis-lock's schema before committing to this; if a field has no token, fall
back to changing aegis-lock (it is our own flake, `noamsto/aegis-lock`).

### Phase 5 — peripherals

| File | Change |
|---|---|
| `nixos/laptop/suspend-handling.nix:50` | `pgrep -f 'quickshell.*noctalia-shell'` → `pgrep -f '/bin/noctalia$'` |
| `nixos/hyprland/default.nix:67` | PAM service `noctalia-shell` → `noctalia`; verify v5's PAM service name, and whether it is still needed given aegis-lock owns locking |
| `home/desktop/hyprland/settings/default.nix:199` | `hl.exec_cmd("noctalia-shell")` → `noctalia` |
| `hyprdynamicmonitors/default.nix` + `workspace-manager.sh:58,290` | `noctalia-shell list \| awk` → `pgrep -f '/bin/noctalia$'`; drop the now-unneeded `pkgs.gawk` if nothing else uses it |
| `home/desktop/noctalia/default.nix` crash monitor | Per Phase 0 outcome: either `systemd.enable = true`, or port `get_noctalia_pid`/`relaunch_noctalia` to the new binary |

The v4 watchdog comment explains `list` was needed because quickshell's argv was
just `quickshell`, indistinguishable from hypridle. v5's native binary makes
a `pgrep` probe viable again — but NOT `pgrep -x noctalia`. The package is
`wrapProgram`-wrapped: `bin/noctalia` is a bash wrapper that runs
`exec -a "$0" .../.noctalia-wrapped`, which sets `argv[0]` but not
`/proc/PID/comm` (the kernel derives `comm` from the wrapped ELF's basename,
truncated to 15 chars — `.noctalia-wrapp`). Since `pgrep -x` matches `comm`,
it never matches. Use `pgrep -f '/bin/noctalia$'`, which matches `argv[0]`;
the `$` anchor excludes `noctalia-ipc` and `noctalia msg ...` invocations.

## Verification

Ordered; each gate must pass before the next.

1. `nix flake check` / `nh home build` — `checkConfig` runs `noctalia config validate`.
2. `noctalia config validate` by hand, reading **warnings**. Every
   "unknown setting" warning is a mistranslated key. Target: zero.
3. Diff the v4 checklist against `noctalia config export merged` — confirm every
   v4 setting is translated, deliberately dropped, or newly defaulted.
4. `nh os switch` on g5, then confirm by hand:
   - bar renders; every widget present and in the right slot
   - theme toggle in **both** directions, via keybind and via GUI, and confirm
     the `theme_mode_changed` hook reaches `theme-toggle`
   - wallpaper change writes a non-empty `last-wallpaper`;
     `noctalia-restore-wallpaper` works
   - lockscreen shows correct colours after a theme change
   - calendar shows Google events after re-auth
   - each plugin loads: catwalk, weekly-calendar, mini-docker, screen-recorder,
     tailscale, privacy-indicator, keep-awake-plus
   - `hyprdynamicmonitors` workspace-manager still finds the shell
   - suspend/resume: `suspend-handling.nix` detects the shell
5. `shellcheck` on every edited shell script.

## Rollback

Revert the flake input to `5311e14` and rebuild. Nothing outside this branch
changes, and v4's `~/.config/noctalia/settings.json` is untouched throughout
(Phase 0/1 work in `/tmp` via `NOCTALIA_CONFIG_HOME`). The v5 state directory
`~/.local/state/noctalia/` can be deleted independently to clear GUI overrides.

## Out of scope

- Adopting new v5 features (named multi-bars, dock, desktop widgets, window
  switcher MRU, Hebrew locale). Migrate to parity first; add features later.
- Migrating other hosts. g6 and p14s follow after g5 validates, and g6 still has
  pending psd + EasyEffects on-disk cleanup that should not tangle in.
- Changing aegis-lock itself, unless Phase 4 finds the template cannot express
  its schema.

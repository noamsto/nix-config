# keep-awake-plus — Noctalia plugin design

**Status:** draft · **Owner:** Noam · **Date:** 2026-04-19

Replace the current bar-mounted awake controls (custom `system-awake` button plus
Noctalia's built-in `KeepAwake`) with a single Noctalia plugin that provides a bar
widget, a popup panel, and a settings pane. The shell script that performs the
actual `systemd-inhibit` plumbing is kept as the backend — the plugin is the UX
layer over it.

## Goals

1. One widget controls both "keep system awake, let monitor sleep" and
   "keep everything awake" — no two overlapping controls.
2. Hover-time and at-a-glance feedback: remaining time visible next to the icon,
   verbose status in the tooltip.
3. Menu-driven selection of duration and scope, with last choice persisted
   across reboots and hosts.
4. Defaults (scope, durations) are configurable from the plugin's Settings UI
   and declaratively from Nix via `pluginSettings`.
5. Survive a fresh host install: pulling the plugin from its `sourceUrl`
   must be enough to restore behavior.
6. Preserve existing thermal-guard behavior (temperature watchdog that forces
   suspend on overheat) without change.

## Non-goals

- Replacing Noctalia's **built-in** `KeepAwake` widget in upstream Noctalia.
  (It is currently not wired into our bar — only referenced in a comment. This
  spec just stops needing it.)
- Making the plugin cross-shell (e.g., work outside Noctalia). It is
  Noctalia/Quickshell-specific.
- Translating the UI (i18n). English only for v1.
- Managing `hypridle` directly. Full-scope idle inhibit is held via the Wayland
  `idle-inhibit` protocol; `hypridle` honors that automatically.

## High-level architecture

```
┌─────────────────── Noctalia bar ────────────────────┐
│                                                     │
│   [ ☕ 1h23m ]  ← plugin BarWidget.qml               │
│        │                                            │
│        │ click → Panel.qml (popup)                  │
│        │                                            │
│   ┌────▼─────────────────── plugin Main.qml ─┐      │
│   │  - polls `system-awake status --json`    │      │
│   │  - holds Wayland idle-inhibit (full)     │      │
│   │  - persists last {duration,scope} choice │      │
│   └──────────────────┬───────────────────────┘      │
└──────────────────────┼──────────────────────────────┘
                       │ Quickshell.execDetached / Process
                       ▼
          ┌────────────────────────────────┐
          │  system-awake  (shell script)  │
          │  · writes state.json           │
          │  · runs systemd-inhibit        │
          │  · start/stop thermal guard    │
          └───────────┬────────────────────┘
                      │ systemctl --user
                      ▼
          system-awake-thermal-guard.service
          (unchanged)
```

Two processes of concern:

- **QML plugin (Main / BarWidget / Panel / Settings)** — lives in a
  standalone Git repo (`noamsto/noctalia-plugin-keep-awake`), auto-installed
  by Noctalia from its `sourceUrl`. Owns: UI, Wayland idle-inhibit for `full`
  scope, last-choice persistence at `$XDG_STATE_HOME/keep-awake-plus/last.json`.
- **`system-awake` shell script** — lives in this nix-config repo under
  `home/desktop/hyprland/scripts/system-awake.nix`. Owns: `systemd-inhibit`,
  thermal-guard service start/stop, the primary state file at
  `$XDG_RUNTIME_DIR/system-awake.state.json`.

The plugin is stateless about the inhibitor process; if the plugin crashes or
Noctalia restarts, the script's state file is the single source of truth
and the plugin rehydrates from it on next poll.

## Modes / scope

Two orthogonal dimensions:

| Dimension | Values | Meaning |
|-----------|--------|---------|
| Duration  | 30m, 1h, 2h, 4h, 8h, ∞ (unlimited), off | how long the inhibit lasts |
| Scope     | `partial`, `full` | what the inhibit actually blocks |

**Scope semantics:**

| Scope | Blocks suspend | Blocks lid-switch handler | Blocks idle (monitor DPMS, lock) | Mechanism |
|-------|----------------|---------------------------|----------------------------------|-----------|
| `partial` | yes | yes | **no** (monitor can go dark) | `systemd-inhibit --what=sleep:handle-lid-switch` |
| `full`    | yes | yes | **yes**                      | `systemd-inhibit` (same) **plus** Wayland `idle-inhibit` held by the plugin |

`partial` matches the current `system-awake` behavior. `full` matches what
Noctalia's built-in `KeepAwake` does today.

## Bar widget

**Layout:** icon + optional remaining-time text.

- Icon, by state:
  - off: `coffee-outline` (Material) in `mOnSurface`
  - `partial`: `coffee` in `mOnSurface`
  - `full`: `coffee` in `mPrimary` (accent)
- Text (next to icon), when active, compact format:
  - `< 60m` → `Nm` (e.g., `23m`)
  - `≥ 60m` → `HhMMm` (e.g., `1h23m`)
  - `unlimited` → `∞`
  - off → empty (widget collapses)
- Tooltip (dynamic, updates with state):
  - off: `Keep Awake · off`
  - active: `Keep Awake · {scope} · {remaining} left · thermal guard: {active|off}`

**Interactions:**

| Gesture       | Action                                                              |
|---------------|---------------------------------------------------------------------|
| Left click    | Open panel (default). Configurable.                                 |
| Right click   | Immediate `off`.                                                    |
| Middle click  | Re-activate last `{duration, scope}` combo from persisted state.    |
| Scroll up/down | Optional (v2): step to next/prev duration in the configured list.   |

## Panel

Dimensions: `320 × 420` logical px (scaled by `Style.uiScaleRatio`).

```
┌─────────────────────────────┐
│ ☕ Keep Awake                │  header row: icon, title
│ partial · 1h23m remaining   │  subtitle: live state
├─────────────────────────────┤
│ Scope                       │
│ ( Partial | Full )          │  segmented NSwitch-style control
├─────────────────────────────┤
│ Duration                    │
│  [30m] [1h]  [2h]  [4h]     │
│  [8h]  [∞]                  │
├─────────────────────────────┤
│ [+30m extend]   [Disable]   │  secondary actions
└─────────────────────────────┘
```

- Duration buttons: clicking starts/restarts the inhibit at the chosen
  duration with the currently-selected scope.
- Active duration button is highlighted (primary color border).
- `+Xm extend` button is only visible when active; extends by
  `quickExtendMinutes` without changing scope.
- `Disable` button is only visible when active; ends the inhibit.

## Settings UI (`Settings.qml`)

Rendered inside Noctalia's plugin-settings dialog. Fields:

| Field                 | Type              | Default                 | Notes                                              |
|-----------------------|-------------------|-------------------------|----------------------------------------------------|
| `defaultScope`        | enum partial/full | `partial`               | Scope pre-selected in panel when no active state.  |
| `durations`           | list<int minutes> | `[30, 60, 120, 240, 480]` plus `∞` | Drives the panel duration buttons.       |
| `showRemainingText`   | bool              | `true`                  | Hide the text next to the icon if false.           |
| `activateOnLeftClick` | bool              | `false`                 | `true` swaps left-click (re-activate) and right-click (open panel). |
| `quickExtendMinutes`  | int               | `30`                    | Amount added by the `+Xm` panel button.            |

Values are also overridable declaratively in
`home/desktop/noctalia/default.nix` via `pluginSettings.keep-awake-plus = { … };`.

## Backend script changes (`system-awake`)

The current cycle-toggle syntax (`toggle`, `off`, `status`, `label`) is
supplanted by a richer contract. Backward-compat is not a goal — the
Hyprland bind and the Noctalia widget are updated together.

### New command surface

| Subcommand                                     | Effect                                                                                   |
|------------------------------------------------|------------------------------------------------------------------------------------------|
| `system-awake start <duration> --scope=<partial\|full>` | Start/restart inhibit for `<duration>` (seconds, or the literal `unlimited`). |
| `system-awake extend <duration>`               | Extend the active session by `<duration>` seconds. No-op if not active.                   |
| `system-awake off`                             | Stop inhibit, stop thermal guard, clear state.                                            |
| `system-awake status [--json]`                 | Print compact status. `--json` returns the state object.                                  |
| `system-awake label`                           | Compact bar text (unchanged).                                                             |
| `system-awake toggle-last`                     | Re-activate last persisted `{duration, scope}` from `$XDG_STATE_HOME/keep-awake-plus/last.json`; off if already active. |

### State file

`$XDG_RUNTIME_DIR/system-awake.state.json`:

```json
{
  "active": true,
  "scope": "partial",
  "duration_label": "2h",
  "end_epoch": 1713800000,
  "pid": 12345,
  "started_epoch": 1713792800
}
```

`end_epoch` is omitted (or `null`) when scope is unlimited.

### Thermal guard

Unchanged. Started on `start`, stopped on `off`. Fires on any active scope.

### Wayland idle-inhibit (full scope)

The **plugin** holds the Wayland `idle-inhibit` request, not the script —
Quickshell/Noctalia already has a Wayland connection; shelling out to a CLI
helper would be redundant. The script only handles the systemd-side
inhibit.

When the plugin observes state transition to `scope == "full"`, it acquires
an idle-inhibit handle and releases it on transition away from `full` (or on
plugin shutdown).

## Hosting and distribution

- Plugin source repo: **`noamsto/noctalia-plugin-keep-awake`** (new, public,
  MIT — same license as Noctalia plugins).
- Added to `pluginSettings.plugins.sources` in
  `home/desktop/noctalia/default.nix` alongside the official source. A new
  `let`-binding mirrors the existing `pluginSource` one:

  ```nix
  pluginSource    = "https://github.com/noctalia-dev/noctalia-plugins";
  ownPluginSource = "https://github.com/noamsto/noctalia-plugin-keep-awake";
  # …
  sources = [
    { enabled = true; name = "Official Noctalia Plugins"; url = pluginSource; }
    { enabled = true; name = "Noam's Plugins";            url = ownPluginSource; }
  ];
  ```

- Enabled via the same `enabledPlugins` list pattern the repo already uses.
- Auto-update on startup remains enabled (matches current config).
- Plugin layout mirrors the other plugins we already have installed:
  `manifest.json`, `Main.qml`, `BarWidget.qml`, `Panel.qml`, `Settings.qml`,
  `README.md`, `preview.png` (optional), `i18n/` (stub, English only for v1).

On a fresh host install, Noctalia pulls the plugin from `sourceUrl` the same
way it already does for the other 7 plugins — nothing custom needs to happen.

## Migration

In `home/desktop/noctalia/default.nix`:

- Remove the `CustomButton` block at lines ~313–329 (`id = "CustomButton"; …
  leftClickExec = "system-awake toggle"; …`).
- Add `{ id = "plugin:keep-awake-plus"; }` in the same position.
- Add `keep-awake-plus` to the `enabledPlugins` list.
- Add the new source entry.
- Add `pluginSettings.keep-awake-plus` with any non-default values.

In `home/desktop/hyprland/settings/bindings.nix`:

- Change the `SUPER+ALT+K` bind from `system-awake toggle` to
  `system-awake toggle-last` so the shortcut matches the new "re-activate
  last combo" semantic.

In `home/desktop/hyprland/services/hyprdynamicmonitors/scripts/workspace-manager.sh`:

- Leave the `pgrep -f 'systemd-inhibit.*noams-system-awake'` check
  as-is — still correct for both `partial` and `full` scope, since both hold
  a systemd-inhibit.

## Error handling and edge cases

- **Plugin loaded, script missing from PATH** — bar widget shows `?` icon,
  panel is disabled with a one-line error. Tooltip explains.
- **State file present but PID dead** — script's own self-heal on `status`
  (already implemented) wipes state; plugin reflects `off` on next poll.
- **Noctalia restart mid-session** — plugin rehydrates from state file on
  next poll cycle and re-acquires Wayland idle-inhibit if scope is `full`.
- **Host reboot with persisted `last.json`** — on next middle-click or
  `toggle-last`, the stored combo is used even across reboots.
- **Two concurrent scope changes** — impossible by design: changing scope
  always means restart (full `off` → `start`), with a visible state
  transition.

## Testing strategy

This is a UI plugin with shell-script backing, so the test surface is
integration-heavy and mostly manual.

- **Script**: unit-ish `bats` or plain bash tests for the state machine
  (`start`/`extend`/`off`/`status --json` round-trip, including the
  natural-timeout self-heal path). Run via `just test-awake` (new).
- **Plugin**: smoke test per scope and duration — start from panel, verify
  bar text updates, verify `systemctl --user status system-awake-thermal-guard`,
  close lid test (with `has_external_monitors` path verified both ways), and
  idle-inhibit verification via `loginctl show-session $XDG_SESSION_ID | grep Idle`.
- **Cross-host**: after merging, `nh home switch` on both thinkpad-p14s-g5
  and thinkpad-p14s-g6 and confirm the plugin auto-installs on first boot.

## Risks and open questions

- **Quickshell Wayland idle-inhibit API** — not yet verified that a plugin
  (as opposed to the shell core) can acquire an `idle-inhibit` request.
  If it can't, fallback is to bundle a tiny Nix-packaged helper (e.g.
  `wayland-idle-inhibit-simple`) and have the script invoke it for `full`
  scope. This affects backend-split only, not the UX.
- **`minNoctaliaVersion`** — pinned to match the running Noctalia (≥ 3.6.0
  per the privacy-indicator manifest). Needs confirmation against our
  current pinned version in the flake.
- **Plugin auto-update** — currently enabled. If upstream Noctalia ships a
  breaking plugin-API change, our plugin pulls a compatible release via
  `minNoctaliaVersion` gating, but we still need to bump our plugin's
  manifest when the API changes. Accept this as ongoing maintenance cost.

## Rollout

1. Land the refactor of `system-awake` (new command surface + JSON state file) as
   a no-UI-change commit. Hyprland bind temporarily keeps `toggle` working
   via a wrapper alias (`start 30m --scope=partial` on a dead state,
   `extend 30m` on an active state, etc.) so nothing breaks mid-refactor.
2. Scaffold `noamsto/noctalia-plugin-keep-awake` with manifest + stubs.
3. Implement `BarWidget.qml`, `Panel.qml`, `Settings.qml`, `Main.qml`.
4. Verify on one Hyprland host.
5. Flip Noctalia bar config from `CustomButton` to `plugin:keep-awake-plus`,
   flip Hyprland bind to `toggle-last`, remove the wrapper alias.
6. Roll out to the remaining Hyprland hosts (currently `thinkpad-p14s-g5` and
   `thinkpad-p14s-g6`; verify each via `nh home switch`).

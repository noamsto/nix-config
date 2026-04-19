# keep-awake-plus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Noctalia plugin (`keep-awake-plus`) that replaces the current `CustomButton`-based `system-awake` control, backed by a refactored `system-awake` shell script with a rich command surface and JSON state.

**Architecture:** Two layers. (1) A QML/Quickshell plugin (`noamsto/noctalia-plugin-keep-awake`, new GitHub repo) provides the bar widget, popup panel, and settings. (2) An existing shell script `system-awake` is refactored to expose `start` / `extend` / `off` / `status --json` / `toggle-last` with a JSON state file at `$XDG_RUNTIME_DIR/system-awake.state.json` and a last-choice file at `$XDG_STATE_HOME/system-awake/last.json`. Plugin polls script state; plugin additionally calls `IdleInhibitorService.addInhibitor()` on `full` scope.

**Tech Stack:**
- **Shell:** bash (existing script, refactored); jq for JSON; `systemd-inhibit` for suspend/lid blocking; `systemctl --user` for thermal-guard start/stop.
- **Plugin UI:** Quickshell QML (Noctalia plugin API, matching `~/.config/noctalia/plugins/privacy-indicator` as reference). Noctalia singletons used: `qs.Services.Power.IdleInhibitorService`, `qs.Commons.Style`, `qs.Widgets.{NBox,NText,NIcon,NIconButton,NScrollView}`.
- **Nix:** flake-parts Home Manager modules; existing `pluginSettings` / `sources` pattern in `home/desktop/noctalia/default.nix`.
- **Testing:** shell integration smoke tests (no `bats`), manual QML smoke test against live Noctalia.

**Spec:** `docs/superpowers/specs/2026-04-19-keep-awake-plus-design.md`

**Current host for dev:** `thinkpad-p14s-g5`. Secondary Hyprland host for rollout: `thinkpad-p14s-g6`. `thinkpad-p14s` does not run Hyprland.

**One-off deviation from spec:** `last.json` is written by the **script**, not the plugin (spec §10 "persist last choice" said plugin). Single writer is simpler; plugin never needs a `FileView` for it. Path: `$XDG_STATE_HOME/system-awake/last.json`.

---

## Phase 0: Dev-loop setup

### Task 0: Create the plugin repo and symlink it for live editing

The plugin lives in an external Git repo. We develop locally via a symlink into `~/.config/noctalia/plugins/` so Noctalia picks up QML changes without reinstalls.

**Files:**
- Create (remote): empty GitHub repo `noamsto/noctalia-plugin-keep-awake`
- Create (local): `~/Data/git/noctalia-plugin-keep-awake/` (initial clone)
- Create (symlink): `~/.config/noctalia/plugins/keep-awake-plus` → local clone

- [ ] **Step 1: Create the remote GitHub repo**

Run:
```bash
gh repo create noamsto/noctalia-plugin-keep-awake --public --description "Noctalia plugin: duration+scope Keep Awake with persistent last-choice" --license MIT
```
Expected: `https://github.com/noamsto/noctalia-plugin-keep-awake.git` now exists.

- [ ] **Step 2: Clone it into the usual path**

Run:
```bash
mkdir -p ~/Data/git
git clone https://github.com/noamsto/noctalia-plugin-keep-awake.git ~/Data/git/noctalia-plugin-keep-awake
```
Expected: clone succeeds (repo is empty but has a default `main` and `LICENSE` from `--license MIT`).

- [ ] **Step 3: Symlink the local clone into Noctalia's plugin dir**

Noctalia's plugin manager will see the directory and load it as `keep-awake-plus`. Because it's a symlink, saves + Noctalia restart pick up changes instantly.

Run:
```bash
ln -s ~/Data/git/noctalia-plugin-keep-awake ~/.config/noctalia/plugins/keep-awake-plus
ls -la ~/.config/noctalia/plugins/keep-awake-plus
```
Expected: `ls` shows the symlink pointing to the clone.

- [ ] **Step 4: Confirm Noctalia's plugin manager sees it**

Run:
```bash
systemctl --user restart noctalia-shell.service
journalctl --user -u noctalia-shell.service -n 50 --no-pager | grep -i 'keep-awake-plus\|plugin'
```
Expected: no errors about `keep-awake-plus` (it's empty at this point, so Noctalia may log "missing manifest.json" — that's fine, we'll add it next).

No commits in this task (all the commits happen inside phases that edit files).

---

## Phase 1: Refactor `system-awake` script

Goal: ship a working, backwards-compatible `system-awake` with the new command surface, JSON state file, and `last.json` persistence. The existing `toggle` subcommand stays as a thin back-compat wrapper for this phase — the Hyprland bind keeps working while the plugin is being built.

### Task 1: Replace `system-awake.nix` with the refactored script

**Files:**
- Modify: `/home/noams/nix-config/home/desktop/hyprland/scripts/system-awake.nix` — complete rewrite
- Create: `/home/noams/nix-config/home/desktop/hyprland/scripts/system-awake.test.sh` — manual smoke-test runner

This is a big single-file rewrite, so it's one task with one commit. Reviewing it diff-style against the old version is easier than staging partial commits.

- [ ] **Step 1: Draft the new script**

Replace the entire contents of `home/desktop/hyprland/scripts/system-awake.nix` with:

```nix
{pkgs, ...}: let
  # Keep-awake backend. Cycles of states:
  #   off | {partial,full} × {30m, 1h, 2h, 4h, 8h, unlimited}
  #
  # Subcommands:
  #   start <seconds|unlimited> --scope=<partial|full>
  #   extend <seconds>
  #   off
  #   status [--json]
  #   label
  #   toggle-last     (activate last {duration,scope} combo, or off if already on)
  #   toggle          (legacy: cycle 30m→2h→8h→∞→off in partial scope; kept during plugin rollout)
  #
  # State lives in two files:
  #   $XDG_RUNTIME_DIR/system-awake.state.json  (active session, cleared on reboot)
  #   $XDG_STATE_HOME/system-awake/last.json    (last {duration_seconds,scope}, persists across reboots)
  system-awake = pkgs.writeShellScriptBin "system-awake" ''
    #!/usr/bin/env bash
    set -euo pipefail

    STATE_DIR="''${XDG_RUNTIME_DIR:-/tmp}"
    STATE_FILE="$STATE_DIR/system-awake.state.json"
    PERSIST_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/system-awake"
    LAST_FILE="$PERSIST_DIR/last.json"
    TAG="noams-system-awake"
    SCHEMA_VERSION=1

    mkdir -p "$PERSIST_DIR"

    notify() {
      ${pkgs.libnotify}/bin/notify-send -i "$1" "Keep Awake" "$2" -t 2500 || true
    }

    guard_start() {
      ${pkgs.systemd}/bin/systemctl --user start system-awake-thermal-guard.service 2>/dev/null || true
    }
    guard_stop() {
      ${pkgs.systemd}/bin/systemctl --user stop system-awake-thermal-guard.service 2>/dev/null || true
    }

    # Write the state JSON atomically.
    write_state() {
      local scope="$1" duration_label="$2" end_epoch="$3" pid="$4" started="$5"
      local tmp
      tmp=$(mktemp "$STATE_FILE.XXXXXX")
      ${pkgs.jq}/bin/jq -n \
        --arg schema "$SCHEMA_VERSION" \
        --arg scope "$scope" \
        --arg duration_label "$duration_label" \
        --argjson end_epoch "$end_epoch" \
        --argjson pid "$pid" \
        --argjson started "$started" \
        '{active:true, schema:($schema|tonumber), scope:$scope, duration_label:$duration_label, end_epoch:$end_epoch, pid:$pid, started_epoch:$started}' \
        > "$tmp"
      mv "$tmp" "$STATE_FILE"
    }

    write_last() {
      local duration_seconds="$1" scope="$2" duration_label="$3"
      local tmp
      tmp=$(mktemp "$LAST_FILE.XXXXXX")
      ${pkgs.jq}/bin/jq -n \
        --argjson duration_seconds "$duration_seconds" \
        --arg scope "$scope" \
        --arg duration_label "$duration_label" \
        '{duration_seconds:$duration_seconds, scope:$scope, duration_label:$duration_label}' \
        > "$tmp"
      mv "$tmp" "$LAST_FILE"
    }

    # Format seconds as a compact duration label.
    format_label() {
      local seconds="$1"
      if [[ "$seconds" == "unlimited" ]]; then
        echo "∞"
      elif (( seconds >= 3600 )); then
        local h=$(( seconds / 3600 )) m=$(( (seconds % 3600) / 60 ))
        if (( m == 0 )); then
          printf '%dh\n' "$h"
        else
          printf '%dh%02dm\n' "$h" "$m"
        fi
      else
        printf '%dm\n' $(( seconds / 60 ))
      fi
    }

    # Returns 0 if a tagged inhibitor process is alive, 1 otherwise.
    # Uses pgrep on the unique tag instead of trusting a captured PID,
    # because `setsid -f` detaches the grandchild and $! is the dying parent.
    inhibitor_pid() {
      pgrep -f "systemd-inhibit.*$TAG" 2>/dev/null | head -1
    }

    is_active() {
      [[ -f "$STATE_FILE" ]] || return 1
      [[ -n "$(inhibitor_pid)" ]]
    }

    cleanup_inactive() {
      rm -f "$STATE_FILE"
      pkill -f "systemd-inhibit.*$TAG" 2>/dev/null || true
      guard_stop
    }

    # Start a new inhibit session. Stops any existing session first.
    cmd_start() {
      local duration="$1" scope="$2"
      local label_duration start_epoch end_epoch pid

      if [[ "$scope" != "partial" && "$scope" != "full" ]]; then
        echo "error: --scope must be partial or full" >&2
        exit 2
      fi

      # Silent cleanup of any previous session (no "Disabled" notification).
      cleanup_inactive

      start_epoch=$(date +%s)
      if [[ "$duration" == "unlimited" ]]; then
        label_duration="unlimited"
        end_epoch="null"
        setsid -f ${pkgs.systemd}/bin/systemd-inhibit \
          --what=sleep:handle-lid-switch \
          --who=hyprland \
          --why="$TAG ($scope unlimited)" \
          --mode=block \
          sleep infinity >/dev/null 2>&1 &
        write_last -1 "$scope" "∞"
      else
        if ! [[ "$duration" =~ ^[0-9]+$ ]]; then
          echo "error: duration must be a positive integer (seconds) or 'unlimited'" >&2
          exit 2
        fi
        label_duration=$(format_label "$duration")
        end_epoch=$(( start_epoch + duration ))
        setsid -f ${pkgs.coreutils}/bin/timeout "''${duration}s" \
          ${pkgs.systemd}/bin/systemd-inhibit \
          --what=sleep:handle-lid-switch \
          --who=hyprland \
          --why="$TAG ($scope $label_duration)" \
          --mode=block \
          sleep infinity >/dev/null 2>&1 &
        write_last "$duration" "$scope" "$label_duration"
      fi

      # Wait briefly for setsid's grandchild to register, then capture the real PID.
      sleep 0.1
      pid=$(inhibitor_pid)
      if [[ -z "$pid" ]]; then
        echo "warning: failed to detect inhibitor PID; aborting" >&2
        cleanup_inactive
        exit 1
      fi

      write_state "$scope" "$label_duration" "$end_epoch" "$pid" "$start_epoch"
      guard_start
      notify "weather-clear" "Enabled: $scope · $label_duration"
    }

    # Extend the active session by N seconds. Does NOT update last.json
    # (user's original picked duration is preserved for toggle-last).
    cmd_extend() {
      local delta="$1"
      if ! is_active; then
        echo "error: no active session to extend" >&2
        exit 1
      fi
      if ! [[ "$delta" =~ ^[0-9]+$ ]]; then
        echo "error: extend expects a positive integer (seconds)" >&2
        exit 2
      fi

      local end_epoch scope started_epoch
      end_epoch=$(${pkgs.jq}/bin/jq -r '.end_epoch' "$STATE_FILE")
      scope=$(${pkgs.jq}/bin/jq -r '.scope' "$STATE_FILE")
      started_epoch=$(${pkgs.jq}/bin/jq -r '.started_epoch' "$STATE_FILE")

      if [[ "$end_epoch" == "null" ]]; then
        notify "weather-clear" "Already unlimited"
        return 0
      fi

      local now new_end new_duration new_label pid
      now=$(date +%s)
      new_end=$(( end_epoch + delta ))
      new_duration=$(( new_end - now ))
      if (( new_duration <= 0 )); then
        cmd_off
        return 0
      fi
      new_label=$(format_label "$(( new_end - started_epoch ))")

      # Terminate old inhibitor process without touching last.json/notification.
      pkill -f "systemd-inhibit.*$TAG" 2>/dev/null || true
      sleep 0.1

      setsid -f ${pkgs.coreutils}/bin/timeout "''${new_duration}s" \
        ${pkgs.systemd}/bin/systemd-inhibit \
        --what=sleep:handle-lid-switch \
        --who=hyprland \
        --why="$TAG ($scope $new_label extended)" \
        --mode=block \
        sleep infinity >/dev/null 2>&1 &

      sleep 0.1
      pid=$(inhibitor_pid)
      if [[ -z "$pid" ]]; then
        echo "warning: failed to detect inhibitor PID after extend" >&2
        cleanup_inactive
        exit 1
      fi

      write_state "$scope" "$new_label" "$new_end" "$pid" "$started_epoch"
      notify "weather-clear" "Extended to $new_label"
    }

    cmd_off() {
      if [[ -f "$STATE_FILE" ]]; then
        notify "weather-clear-night" "Disabled"
      fi
      cleanup_inactive
    }

    cmd_status() {
      local json=0
      if [[ "''${1:-}" == "--json" ]]; then json=1; fi

      # Self-heal: if state file says active but PID is gone, wipe it.
      if [[ -f "$STATE_FILE" ]] && ! is_active; then
        cleanup_inactive
      fi

      if [[ ! -f "$STATE_FILE" ]]; then
        if (( json )); then
          echo '{"active":false}'
        else
          echo "off"
        fi
        return 0
      fi

      # Self-heal: timeout ticked past end_epoch but process is still alive
      # (shouldn't happen with `timeout Ns`, but guard anyway).
      local now end_epoch
      now=$(date +%s)
      end_epoch=$(${pkgs.jq}/bin/jq -r '.end_epoch' "$STATE_FILE")
      if [[ "$end_epoch" != "null" ]] && (( now >= end_epoch )); then
        cleanup_inactive
        if (( json )); then
          echo '{"active":false}'
        else
          echo "off"
        fi
        return 0
      fi

      if (( json )); then
        cat "$STATE_FILE"
      else
        local scope duration_label
        scope=$(${pkgs.jq}/bin/jq -r '.scope' "$STATE_FILE")
        duration_label=$(${pkgs.jq}/bin/jq -r '.duration_label' "$STATE_FILE")
        if [[ "$end_epoch" == "null" ]]; then
          printf '%s unlimited\n' "$scope"
        else
          local remaining=$(( end_epoch - now )) mins=$(( (end_epoch - now) / 60 ))
          printf '%s %s (%dm left)\n' "$scope" "$duration_label" "$mins"
        fi
      fi
    }

    cmd_label() {
      if [[ ! -f "$STATE_FILE" ]] || ! is_active; then
        cleanup_inactive
        return 0
      fi
      local end_epoch now remaining mins
      end_epoch=$(${pkgs.jq}/bin/jq -r '.end_epoch' "$STATE_FILE")
      if [[ "$end_epoch" == "null" ]]; then
        echo "∞"
        return 0
      fi
      now=$(date +%s)
      remaining=$(( end_epoch - now ))
      if (( remaining <= 0 )); then
        cleanup_inactive
        return 0
      fi
      mins=$(( remaining / 60 ))
      if (( mins >= 60 )); then
        printf '%dh%02dm\n' $(( mins / 60 )) $(( mins % 60 ))
      else
        printf '%dm\n' "$mins"
      fi
    }

    cmd_toggle_last() {
      if is_active; then
        cmd_off
        return 0
      fi
      if [[ ! -f "$LAST_FILE" ]]; then
        # No history — sensible first-time default.
        cmd_start 1800 partial
        return 0
      fi
      local seconds scope
      seconds=$(${pkgs.jq}/bin/jq -r '.duration_seconds' "$LAST_FILE")
      scope=$(${pkgs.jq}/bin/jq -r '.scope' "$LAST_FILE")
      if [[ "$seconds" == "-1" ]]; then
        cmd_start unlimited "$scope"
      else
        cmd_start "$seconds" "$scope"
      fi
    }

    # Back-compat for the Hyprland bind during plugin rollout. Remove in phase 5.
    cmd_toggle_legacy() {
      if is_active; then
        local label
        label=$(${pkgs.jq}/bin/jq -r '.duration_label' "$STATE_FILE")
        case "$label" in
          "30m") cmd_start  7200 partial ;;  # → 2h
          "2h")  cmd_start 28800 partial ;;  # → 8h
          "8h")  cmd_start unlimited partial ;;
          "∞")   cmd_off ;;
          *)     cmd_off ;;
        esac
      else
        cmd_start 1800 partial              # off → 30m
      fi
    }

    # --- Dispatch ----------------------------------------------------------

    if (( $# == 0 )); then
      set -- toggle
    fi

    cmd="$1"; shift || true

    case "$cmd" in
      start)
        local_duration=""; local_scope=""
        for arg in "$@"; do
          case "$arg" in
            --scope=*) local_scope="''${arg#--scope=}" ;;
            *)         local_duration="$arg" ;;
          esac
        done
        if [[ -z "$local_duration" || -z "$local_scope" ]]; then
          echo "usage: system-awake start <seconds|unlimited> --scope=<partial|full>" >&2
          exit 2
        fi
        cmd_start "$local_duration" "$local_scope"
        ;;
      extend)
        [[ $# -ge 1 ]] || { echo "usage: system-awake extend <seconds>" >&2; exit 2; }
        cmd_extend "$1"
        ;;
      off)            cmd_off ;;
      status)         cmd_status "''${1:-}" ;;
      label)          cmd_label ;;
      toggle-last)    cmd_toggle_last ;;
      toggle)         cmd_toggle_legacy ;;
      *)
        echo "usage: system-awake [start|extend|off|status|label|toggle-last|toggle] [args]" >&2
        exit 2
        ;;
    esac
  '';
in {
  home.packages = [system-awake];
}
```

Note: the Nix `let ... in` block wraps the script, and Nix-escaped `''${...}` survives the outer string interpolation so bash sees `${...}` at runtime. The `local` declarations inside `case` are intentional in bash even though it's at function scope (this runs inside the script body; the scoping is fine).

Actually — bash's `local` only works inside functions. Lift those to top-level vars:

Replace the `start)` case body with:
```bash
      start)
        __duration=""; __scope=""
        for arg in "$@"; do
          case "$arg" in
            --scope=*) __scope="''${arg#--scope=}" ;;
            *)         __duration="$arg" ;;
          esac
        done
        if [[ -z "$__duration" || -z "$__scope" ]]; then
          echo "usage: system-awake start <seconds|unlimited> --scope=<partial|full>" >&2
          exit 2
        fi
        cmd_start "$__duration" "$__scope"
        ;;
```

- [ ] **Step 2: Run `shellcheck` on the generated script body**

The easiest way: write out a standalone copy of just the bash portion and run shellcheck. Extract the script body (everything between the `''` markers) to `/tmp/system-awake.sh`, then:

```bash
shellcheck -s bash /tmp/system-awake.sh
```

Expected: no errors. Fix any warnings in place (most commonly: SC2155 quote-inside-assignment, SC2086 unquoted vars). When unquoting is intentional (e.g. the `--argjson end_epoch "$end_epoch"` where `null` must be passed literally), disable that line with `# shellcheck disable=SC2086`.

- [ ] **Step 3: `nh home switch` to install the new `system-awake`**

Run:
```bash
just hm
```
(The repo's justfile recipe wraps `nh home switch`.)

Expected: rebuild succeeds. The new `system-awake` is on PATH.

- [ ] **Step 4: Smoke test each subcommand manually**

Run:
```bash
system-awake off
system-awake status
# Expected: off

system-awake start 60 --scope=partial
system-awake status
# Expected: partial 1m (1m left)

system-awake status --json | jq .
# Expected JSON with: active=true, scope="partial", duration_label="1m", end_epoch≈now+60, pid=...

system-awake label
# Expected: 1m

pgrep -af 'systemd-inhibit.*noams-system-awake'
# Expected: one match

systemctl --user status system-awake-thermal-guard.service --no-pager | head
# Expected: active (running)

system-awake extend 60
system-awake status
# Expected: partial 1m or 2m (approx now+120s)

system-awake off
system-awake status
# Expected: off

pgrep -af 'systemd-inhibit.*noams-system-awake'
# Expected: no matches

systemctl --user status system-awake-thermal-guard.service --no-pager | head
# Expected: inactive (dead)

# Test last.json persistence
system-awake start 1800 --scope=full
cat ~/.local/state/system-awake/last.json | jq .
# Expected: {"duration_seconds":1800,"scope":"full","duration_label":"30m"}
system-awake off

system-awake toggle-last
system-awake status --json | jq '.scope, .duration_label'
# Expected: "full", "30m"
system-awake off

# Legacy back-compat
system-awake toggle
system-awake status
# Expected: partial 30m
system-awake toggle
system-awake status
# Expected: partial 2h
system-awake off
```

If any command behaves wrong, stop and fix the `.nix` file, re-run `just hm`, and re-test.

- [ ] **Step 5: Commit**

```bash
git add home/desktop/hyprland/scripts/system-awake.nix
git commit -m "refactor(system-awake): JSON state, start/extend/off/status/toggle-last"
```

### Task 2: Verify Noctalia bar still works with the legacy `toggle`

The `CustomButton` in `home/desktop/noctalia/default.nix` still invokes `system-awake toggle`, `system-awake off`, and `system-awake label`. All three still work after the refactor (legacy `toggle` wrapper preserved). Confirm.

- [ ] **Step 1: Restart Noctalia and click the bar widget**

Run:
```bash
systemctl --user restart noctalia-shell.service
```

Then click the coffee-icon widget in the bar. Expected: icon shows `30m`, then `2h` on next click, etc. Right-click disables.

- [ ] **Step 2: No commit** — this is a live validation step.

---

## Phase 2: Plugin scaffold (empty repo → loadable skeleton)

### Task 3: Add manifest.json, LICENSE, README, .gitignore

**Files:**
- Create: `~/Data/git/noctalia-plugin-keep-awake/manifest.json`
- Create: `~/Data/git/noctalia-plugin-keep-awake/README.md`
- Create: `~/Data/git/noctalia-plugin-keep-awake/.gitignore`
- LICENSE already present from `gh repo create --license MIT`

- [ ] **Step 1: Write `manifest.json`**

```json
{
  "id": "keep-awake-plus",
  "name": "Keep Awake+",
  "version": "0.1.0",
  "minNoctaliaVersion": "3.6.0",
  "author": "Noam Stolero",
  "official": false,
  "license": "MIT",
  "repository": "https://github.com/noamsto/noctalia-plugin-keep-awake",
  "description": "Duration+scope Keep Awake with persistent last-choice and partial/full inhibit modes.",
  "tags": ["Bar", "Power", "KeepAwake"],
  "entryPoints": {
    "main": "Main.qml",
    "barWidget": "BarWidget.qml",
    "panel": "Panel.qml",
    "settings": "Settings.qml"
  },
  "dependencies": { "plugins": [] },
  "metadata": {
    "defaultSettings": {
      "defaultScope": "partial",
      "durations": [30, 60, 120, 240, 480],
      "includeUnlimited": true,
      "showRemainingText": true,
      "activateOnLeftClick": false,
      "quickExtendMinutes": 30
    }
  }
}
```

- [ ] **Step 2: Write `README.md`**

```markdown
# Keep Awake+

Noctalia plugin. Replaces the built-in `KeepAwake` widget with a richer control:

- Two scopes: **partial** (suspend + lid inhibit, monitor may sleep) and **full** (everything).
- Menu-driven duration picker with configurable defaults.
- Persistent last-choice: middle-click re-activates your last duration+scope.
- Dynamic tooltip showing remaining time and thermal-guard state.

Backed by a host-side `system-awake` script (see `https://github.com/noamsto/nix-config`).
```

- [ ] **Step 3: Write `.gitignore`**

```
*.swp
*.bak
.DS_Store
```

- [ ] **Step 4: Commit and push**

```bash
cd ~/Data/git/noctalia-plugin-keep-awake
git add manifest.json README.md .gitignore
git commit -m "chore: add manifest, readme, gitignore"
git push origin main
```

### Task 4: Stub the four QML entry points so Noctalia loads without errors

**Files:**
- Create: `~/Data/git/noctalia-plugin-keep-awake/Main.qml`
- Create: `~/Data/git/noctalia-plugin-keep-awake/BarWidget.qml`
- Create: `~/Data/git/noctalia-plugin-keep-awake/Panel.qml`
- Create: `~/Data/git/noctalia-plugin-keep-awake/Settings.qml`

- [ ] **Step 1: Write `Main.qml` (empty Item + state properties)**

```qml
import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property var pluginApi: null

  // Live state mirrored from `system-awake status --json`
  property bool active: false
  property string scope: "partial"
  property string durationLabel: ""
  property real endEpoch: 0
  property int remainingSeconds: 0

  // Defaults from manifest metadata, overridable via pluginApi.pluginSettings
  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})
  property string defaultScope: cfg.defaultScope ?? defaults.defaultScope ?? "partial"
  property var durations: cfg.durations ?? defaults.durations ?? [30, 60, 120, 240, 480]
  property bool includeUnlimited: cfg.includeUnlimited ?? defaults.includeUnlimited ?? true
  property bool showRemainingText: cfg.showRemainingText ?? defaults.showRemainingText ?? true
  property bool activateOnLeftClick: cfg.activateOnLeftClick ?? defaults.activateOnLeftClick ?? false
  property int quickExtendMinutes: cfg.quickExtendMinutes ?? defaults.quickExtendMinutes ?? 30
}
```

- [ ] **Step 2: Write `BarWidget.qml` (coffee icon, no logic yet)**

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Item {
  id: root
  property var pluginApi: null
  readonly property var mainInstance: pluginApi?.mainInstance

  implicitWidth: row.implicitWidth + Style.marginS * 2
  implicitHeight: Style.baseWidgetSize

  RowLayout {
    id: row
    anchors.centerIn: parent
    spacing: Style.marginXS

    NIcon {
      icon: "coffee-outline"
      color: Color.mOnSurface
      pointSize: Style.fontSizeM
    }
  }
}
```

- [ ] **Step 3: Write `Panel.qml` (empty 320×420 box)**

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Item {
  id: root
  property var pluginApi: null
  readonly property var geometryPlaceholder: panelContainer
  property real contentPreferredWidth: 320 * Style.uiScaleRatio
  property real contentPreferredHeight: 420 * Style.uiScaleRatio
  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property bool allowAttach: true

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    NText {
      anchors.centerIn: parent
      text: "Keep Awake+ (panel stub)"
      color: Color.mOnSurface
    }
  }
}
```

- [ ] **Step 4: Write `Settings.qml` (stub)**

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Item {
  id: root
  property var pluginApi: null
  implicitHeight: column.implicitHeight

  ColumnLayout {
    id: column
    anchors.fill: parent
    NText {
      text: "Keep Awake+ settings (stub)"
      color: Color.mOnSurface
    }
  }
}
```

- [ ] **Step 5: Restart Noctalia and confirm the plugin loads**

```bash
systemctl --user restart noctalia-shell.service
journalctl --user -u noctalia-shell.service -n 50 --no-pager | grep -iE 'keep-awake-plus|qml' | head
```
Expected: no QML errors referencing `keep-awake-plus`.

- [ ] **Step 6: Commit and push**

```bash
cd ~/Data/git/noctalia-plugin-keep-awake
git add Main.qml BarWidget.qml Panel.qml Settings.qml
git commit -m "feat: scaffold main/bar/panel/settings QML entry points"
git push origin main
```

---

## Phase 3: Wire the plugin source into Nix (stub visible in bar, CustomButton kept)

Goal: the plugin is declaratively known to Noctalia via `pluginSettings`, and on a fresh host `nh home switch` is enough to install it. We do **not** yet replace the `CustomButton` — that happens in Phase 5 after the plugin actually works.

### Task 5: Add the plugin source to `noctalia/default.nix`

**Files:**
- Modify: `/home/noams/nix-config/home/desktop/noctalia/default.nix`

- [ ] **Step 1: Add `ownPluginSource` let-binding**

Find the existing `pluginSource = "https://github.com/noctalia-dev/noctalia-plugins";` line (around line 42) and add directly after it:

```nix
  pluginSource = "https://github.com/noctalia-dev/noctalia-plugins";
  ownPluginSource = "https://github.com/noamsto/noctalia-plugin-keep-awake";
```

- [ ] **Step 2: Add the source entry**

Find the `sources = [ { enabled = true; name = "Official Noctalia Plugins"; url = pluginSource; } ];` block (around line 204). Replace with:

```nix
        sources = [
          {
            enabled = true;
            name = "Official Noctalia Plugins";
            url = pluginSource;
          }
          {
            enabled = true;
            name = "Keep Awake+ (noamsto)";
            url = ownPluginSource;
          }
        ];
```

- [ ] **Step 3: Add `keep-awake-plus` to `enabledPlugins`**

Find the `enabledPlugins = [ ... ];` list (search for `enabledPlugins`). Add `"keep-awake-plus"` to the list. Then update the `states = lib.genAttrs enabledPlugins ...` to point the new entry at `ownPluginSource`:

```nix
        states = lib.genAttrs enabledPlugins (name: {
          enabled = true;
          sourceUrl =
            if name == "keep-awake-plus"
            then ownPluginSource
            else pluginSource;
        });
```

- [ ] **Step 4: Remove the dev-loop symlink before rebuild**

Noctalia's plugin manager will complain if the target directory already exists as a symlink. Remove it so the manager can clone fresh:

```bash
gtrash put ~/.config/noctalia/plugins/keep-awake-plus
```

- [ ] **Step 5: `nh home switch`**

```bash
just hm
```
Expected: rebuild succeeds; Noctalia restarts; plugin manager fetches from `ownPluginSource`.

- [ ] **Step 6: Verify the plugin was cloned**

```bash
ls -la ~/.config/noctalia/plugins/keep-awake-plus
cat ~/.config/noctalia/plugins/keep-awake-plus/manifest.json | head
```
Expected: real directory (not symlink) with `manifest.json` from the repo.

- [ ] **Step 7: Re-add the dev-loop symlink for ongoing development**

The plugin manager doesn't update a plugin on every push. For dev iteration, we keep overriding with the symlink, and only remove it again right before doing cross-host testing.

```bash
gtrash put ~/.config/noctalia/plugins/keep-awake-plus
ln -s ~/Data/git/noctalia-plugin-keep-awake ~/.config/noctalia/plugins/keep-awake-plus
systemctl --user restart noctalia-shell.service
```

- [ ] **Step 8: Commit**

```bash
git add home/desktop/noctalia/default.nix
git commit -m "feat(noctalia): register keep-awake-plus plugin source"
```

---

## Phase 4: Plugin implementation

This is the meat. Iterate against the local symlinked clone, restart Noctalia after each change. Push to GitHub at the end of each task so `nh home switch` on a fresh host can pull a working version, but the *dev* host always reads the symlink.

### Task 6: Wire `Main.qml` to `system-awake status --json`

**Files:**
- Modify: `~/Data/git/noctalia-plugin-keep-awake/Main.qml`

- [ ] **Step 1: Add the status-polling `Process` and parser**

Replace the `Main.qml` contents with:

```qml
import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property var pluginApi: null

  // --- Live state mirrored from `system-awake status --json` ---
  property bool active: false
  property string scope: "partial"
  property string durationLabel: ""
  property var endEpoch: null  // null for unlimited, number otherwise
  property int remainingSeconds: 0
  property bool thermalGuardActive: false

  // --- Settings (from manifest metadata + pluginApi overrides) ---
  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})
  property string defaultScope: cfg.defaultScope ?? defaults.defaultScope ?? "partial"
  property var durations: cfg.durations ?? defaults.durations ?? [30, 60, 120, 240, 480]
  property bool includeUnlimited: cfg.includeUnlimited ?? defaults.includeUnlimited ?? true
  property bool showRemainingText: cfg.showRemainingText ?? defaults.showRemainingText ?? true
  property bool activateOnLeftClick: cfg.activateOnLeftClick ?? defaults.activateOnLeftClick ?? false
  property int quickExtendMinutes: cfg.quickExtendMinutes ?? defaults.quickExtendMinutes ?? 30

  // --- Poller ---
  Process {
    id: statusProc
    running: false
    command: ["system-awake", "status", "--json"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const s = JSON.parse(this.text.trim() || "{}");
          root._applyStatus(s);
        } catch (e) {
          console.warn("keep-awake-plus: failed to parse status:", e, "text:", this.text);
        }
      }
    }
  }

  Process {
    id: guardProc
    running: false
    command: ["systemctl", "--user", "is-active", "--quiet", "system-awake-thermal-guard.service"]
    onExited: function(exitCode) { root.thermalGuardActive = (exitCode === 0); }
  }

  Timer {
    id: poller
    interval: 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: { statusProc.running = true; guardProc.running = true; }
  }

  // Countdown decrement between polls, to avoid visible jitter.
  Timer {
    interval: 1000
    repeat: true
    running: root.active && root.endEpoch !== null
    onTriggered: {
      if (root.endEpoch === null) return;
      const now = Math.floor(Date.now() / 1000);
      root.remainingSeconds = Math.max(0, root.endEpoch - now);
    }
  }

  function _applyStatus(s) {
    if (!s.active) {
      root.active = false;
      root.scope = "";
      root.durationLabel = "";
      root.endEpoch = null;
      root.remainingSeconds = 0;
      return;
    }
    root.active = true;
    root.scope = s.scope;
    root.durationLabel = s.duration_label;
    if (s.end_epoch === null || s.end_epoch === undefined) {
      root.endEpoch = null;
      root.remainingSeconds = -1;  // signal "unlimited" to view layer
    } else {
      root.endEpoch = Number(s.end_epoch);
      const now = Math.floor(Date.now() / 1000);
      root.remainingSeconds = Math.max(0, root.endEpoch - now);
    }
  }

  // --- Actions (invoked by BarWidget / Panel) ---
  function start(durationSeconds, pickScope) {
    const durArg = (durationSeconds === -1) ? "unlimited" : String(durationSeconds);
    Quickshell.execDetached(["system-awake", "start", durArg, "--scope=" + pickScope]);
    Qt.callLater(() => { statusProc.running = true; });
  }

  function off() {
    Quickshell.execDetached(["system-awake", "off"]);
    Qt.callLater(() => { statusProc.running = true; });
  }

  function extend(seconds) {
    Quickshell.execDetached(["system-awake", "extend", String(seconds)]);
    Qt.callLater(() => { statusProc.running = true; });
  }

  function toggleLast() {
    Quickshell.execDetached(["system-awake", "toggle-last"]);
    Qt.callLater(() => { statusProc.running = true; });
  }

  function formatRemaining() {
    if (!active) return "";
    if (remainingSeconds === -1) return "∞";
    const m = Math.floor(remainingSeconds / 60);
    if (m >= 60) return Math.floor(m / 60) + "h" + String(m % 60).padStart(2, "0") + "m";
    return m + "m";
  }
}
```

- [ ] **Step 2: Restart Noctalia, tail the log, verify no QML errors**

```bash
systemctl --user restart noctalia-shell.service
journalctl --user -u noctalia-shell.service -n 80 --no-pager | grep -iE 'keep-awake|qml' | head
```
Expected: no errors.

- [ ] **Step 3: Poke live state and confirm the log shows polling**

```bash
system-awake start 60 --scope=partial
# Wait ~2 seconds
# Then:
journalctl --user -u noctalia-shell.service -n 20 --no-pager | tail
system-awake off
```
Expected: no new errors. (At this point the BarWidget doesn't visualize state yet, but Main is polling.)

- [ ] **Step 4: Commit and push**

```bash
cd ~/Data/git/noctalia-plugin-keep-awake
git add Main.qml
git commit -m "feat: poll system-awake status, expose actions"
git push origin main
```

### Task 7: Idle-inhibit for `full` scope

Noctalia exposes `IdleInhibitorService` as a singleton at `qs.Services.Power.IdleInhibitorService` (see `/nix/store/*/share/noctalia-shell/Services/Power/IdleInhibitorService.qml`). Calling `addInhibitor("keep-awake-plus")` / `removeInhibitor("keep-awake-plus")` is all we need for full-scope idle blocking.

**Files:**
- Modify: `~/Data/git/noctalia-plugin-keep-awake/Main.qml`

- [ ] **Step 1: Import the service and react to scope transitions**

Near the top of `Main.qml`, add the import:

```qml
import qs.Services.Power
```

Then add these to the `Item { id: root ... }`:

```qml
  property bool _idleHeld: false

  onActiveChanged: _syncIdle()
  onScopeChanged: _syncIdle()

  function _syncIdle() {
    const shouldHold = active && scope === "full";
    if (shouldHold && !_idleHeld) {
      IdleInhibitorService.addInhibitor("keep-awake-plus", "Keep Awake+ full scope");
      _idleHeld = true;
    } else if (!shouldHold && _idleHeld) {
      IdleInhibitorService.removeInhibitor("keep-awake-plus");
      _idleHeld = false;
    }
  }

  Component.onDestruction: {
    if (_idleHeld) IdleInhibitorService.removeInhibitor("keep-awake-plus");
  }
```

- [ ] **Step 2: Manual test**

```bash
system-awake start 60 --scope=full
sleep 2
journalctl --user -u noctalia-shell.service -n 40 --no-pager | grep -i 'idleinhibitor'
# Expected: "Added inhibitor: keep-awake-plus"

# Confirm the hypridle side honors it (monitor stays on if you go idle for 60s).
# Easier smoke: inspect the singleton state via logs, or via the existing Noctalia Control Center KeepAwake widget showing active.

system-awake off
journalctl --user -u noctalia-shell.service -n 10 --no-pager | grep -i 'idleinhibitor'
# Expected: "Removed inhibitor: keep-awake-plus"
```

- [ ] **Step 3: Commit and push**

```bash
cd ~/Data/git/noctalia-plugin-keep-awake
git add Main.qml
git commit -m "feat: hold IdleInhibitor for full scope"
git push origin main
```

### Task 8: Bar widget — icon, text, tooltip, clicks

**Files:**
- Modify: `~/Data/git/noctalia-plugin-keep-awake/BarWidget.qml`

- [ ] **Step 1: Replace `BarWidget.qml` with the real widget**

API conventions confirmed against `~/.config/noctalia/plugins/privacy-indicator/BarWidget.qml`:
- `pluginApi.openPanel(screen, anchor)` — opens the plugin's panel
- `TooltipService.show(anchor, text, direction)` / `TooltipService.hide()` — the standard tooltip (not QtQuick.Controls.ToolTip)
- `screen`, `widgetId`, `section`, `sectionWidgetIndex`, `sectionWidgetsCount` — auto-injected by the bar framework; expose as properties
- The bar wraps widgets in a capsule (`Style.capsuleColor`, `Style.capsuleHeight`); use it to match the rest of the bar visually

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
  id: root
  property var pluginApi: null

  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property string screenName: screen ? screen.name : ""
  readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
  readonly property bool isVertical: barPosition === "left" || barPosition === "right"

  readonly property var mainInstance: pluginApi?.mainInstance

  readonly property bool active: mainInstance ? mainInstance.active : false
  readonly property string scope: mainInstance ? mainInstance.scope : ""
  readonly property string remainingText: mainInstance ? mainInstance.formatRemaining() : ""
  readonly property bool showText: mainInstance ? mainInstance.showRemainingText : true
  readonly property bool activateOnLeftClick: mainInstance ? mainInstance.activateOnLeftClick : false

  readonly property real contentWidth: isVertical ? Style.capsuleHeight
    : Math.round(layout.implicitWidth + Style.marginM * 2)
  readonly property real contentHeight: isVertical ? Math.round(layout.implicitHeight + Style.marginM * 2)
    : Style.capsuleHeight

  implicitWidth: contentWidth
  implicitHeight: contentHeight
  Layout.alignment: Qt.AlignVCenter

  function buildTooltip() {
    if (!root.active) return "Keep Awake · off";
    const tg = (mainInstance && mainInstance.thermalGuardActive) ? "active" : "off";
    return "Keep Awake · " + root.scope + " · " + root.remainingText + " left · thermal guard: " + tg;
  }

  Rectangle {
    id: visualCapsule
    x: Style.pixelAlignCenter(parent.width, width)
    y: Style.pixelAlignCenter(parent.height, height)
    width: root.contentWidth
    height: root.contentHeight
    radius: Style.radiusM
    color: Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    RowLayout {
      id: layout
      anchors.centerIn: parent
      spacing: Style.marginXS

      NIcon {
        icon: root.active ? "coffee" : "coffee-outline"
        color: (root.active && root.scope === "full") ? Color.mPrimary : Color.mOnSurface
        pointSize: Style.fontSizeM
      }

      NText {
        visible: root.active && root.showText && root.remainingText.length > 0
        text: root.remainingText
        color: Color.mOnSurface
        pointSize: Style.fontSizeS
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) {
        if (mainInstance) mainInstance.off();
      } else if (mouse.button === Qt.MiddleButton) {
        if (mainInstance) mainInstance.toggleLast();
      } else if (mouse.button === Qt.LeftButton) {
        if (root.activateOnLeftClick) {
          if (mainInstance) mainInstance.toggleLast();
        } else {
          if (pluginApi) pluginApi.openPanel(root.screen, root);
        }
      }
    }

    onEntered: {
      const t = buildTooltip();
      if (t) TooltipService.show(root, t, BarService.getTooltipDirection());
    }
    onExited: TooltipService.hide()
  }
}
```

- [ ] **Step 2: Restart Noctalia and eyeball the widget**

```bash
systemctl --user restart noctalia-shell.service
```
Expected:
- No widget visible in bar at first (since `CustomButton` is still there using `system-awake` directly, AND the plugin's bar widget tries to render — they might both show up. That's fine during transition; we'll de-dup in Phase 5).
- Left-click our widget → logs show panel open attempted (panel is still a stub; may not show visibly)
- Right-click → state goes off
- Middle-click on active state → toggle-last

Run:
```bash
system-awake start 60 --scope=partial
# Hover over the plugin widget: expect tooltip "Keep Awake · partial · 1m left · thermal guard: active"
system-awake off
# Hover: expect "Keep Awake · off"
```

- [ ] **Step 3: Commit and push**

```bash
cd ~/Data/git/noctalia-plugin-keep-awake
git add BarWidget.qml
git commit -m "feat: bar widget with icon, text, tooltip, and click handlers"
git push origin main
```

### Task 9: Panel — header, scope switch, duration grid, actions

**Files:**
- Modify: `~/Data/git/noctalia-plugin-keep-awake/Panel.qml`

- [ ] **Step 1: Replace `Panel.qml` with the real layout**

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets

Item {
  id: root
  property var pluginApi: null
  readonly property var geometryPlaceholder: panelContainer
  property real contentPreferredWidth: 320 * Style.uiScaleRatio
  property real contentPreferredHeight: 420 * Style.uiScaleRatio
  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property bool allowAttach: true

  // Local selected scope. Mirrors live scope while active; falls back to default otherwise.
  property string selectedScope: mainInstance?.active
                                   ? mainInstance.scope
                                   : (mainInstance?.defaultScope ?? "partial")

  Connections {
    target: mainInstance
    function onActiveChanged() {
      if (mainInstance.active) root.selectedScope = mainInstance.scope;
    }
  }

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginM

      // --- Header ---
      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: headerCol.implicitHeight + Style.marginM * 2

        ColumnLayout {
          id: headerCol
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginXS

          RowLayout {
            spacing: Style.marginS
            NIcon {
              icon: mainInstance?.active ? "coffee" : "coffee-outline"
              color: (mainInstance?.active && mainInstance.scope === "full") ? Color.mPrimary : Color.mOnSurface
              pointSize: Style.fontSizeL
            }
            NText {
              Layout.fillWidth: true
              text: "Keep Awake"
              font.weight: Style.fontWeightBold
              pointSize: Style.fontSizeL
              color: Color.mOnSurface
            }
          }
          NText {
            text: mainInstance?.active
                    ? mainInstance.scope + " · " + mainInstance.formatRemaining() + " remaining"
                    : "off"
            color: Qt.alpha(Color.mOnSurface, 0.7)
            pointSize: Style.fontSizeS
          }
        }
      }

      // --- Scope segmented control ---
      NBox {
        Layout.fillWidth: true
        Layout.preferredHeight: scopeRow.implicitHeight + Style.marginM * 2

        RowLayout {
          id: scopeRow
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginS

          NText { text: "Scope:"; color: Color.mOnSurface }

          Button {
            text: "Partial"
            Layout.fillWidth: true
            checkable: true
            checked: root.selectedScope === "partial"
            onClicked: root.selectedScope = "partial"
          }
          Button {
            text: "Full"
            Layout.fillWidth: true
            checkable: true
            checked: root.selectedScope === "full"
            onClicked: root.selectedScope = "full"
          }
        }
      }

      // --- Duration grid ---
      NBox {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginS

          NText { text: "Duration"; color: Color.mOnSurface }

          GridLayout {
            id: grid
            columns: 3
            rowSpacing: Style.marginS
            columnSpacing: Style.marginS
            Layout.fillWidth: true

            Repeater {
              model: {
                const base = mainInstance ? mainInstance.durations.slice() : [30, 60, 120, 240, 480];
                const labels = base.map(m => {
                  return { minutes: m, label: m < 60 ? (m + "m") : (m % 60 === 0 ? (m/60 + "h") : (Math.floor(m/60) + "h" + (m%60) + "m")) };
                });
                if (mainInstance?.includeUnlimited) labels.push({ minutes: -1, label: "∞" });
                return labels;
              }
              delegate: Button {
                Layout.fillWidth: true
                text: modelData.label
                highlighted: mainInstance?.active && (
                  (modelData.minutes === -1 && mainInstance.endEpoch === null) ||
                  (modelData.minutes !== -1 && mainInstance.durationLabel === modelData.label)
                )
                onClicked: {
                  const seconds = (modelData.minutes === -1) ? -1 : modelData.minutes * 60;
                  mainInstance.start(seconds, root.selectedScope);
                }
              }
            }
          }
        }
      }

      // --- Secondary actions ---
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        Button {
          Layout.fillWidth: true
          text: "+" + (mainInstance?.quickExtendMinutes ?? 30) + "m extend"
          enabled: mainInstance?.active && mainInstance.endEpoch !== null
          onClicked: mainInstance.extend((mainInstance.quickExtendMinutes ?? 30) * 60)
        }
        Button {
          Layout.fillWidth: true
          text: "Disable"
          enabled: mainInstance?.active
          onClicked: mainInstance.off()
        }
      }
    }
  }
}
```

- [ ] **Step 2: Restart Noctalia, open the panel, exercise every button**

```bash
systemctl --user restart noctalia-shell.service
```
Left-click the bar widget. Panel should open. Click each duration in both scopes. Verify:
- State transitions match (check `system-awake status --json` in parallel).
- Active duration button is highlighted.
- "Extend" adds ~30m.
- "Disable" turns off.

- [ ] **Step 3: Commit and push**

```bash
cd ~/Data/git/noctalia-plugin-keep-awake
git add Panel.qml
git commit -m "feat: panel with scope switch, duration grid, extend/disable"
git push origin main
```

### Task 10: Settings — 5 fields bound to pluginApi

**Files:**
- Modify: `~/Data/git/noctalia-plugin-keep-awake/Settings.qml`

- [ ] **Step 1: Replace `Settings.qml` with real fields (pattern verified against `privacy-indicator/Settings.qml`)**

API conventions:
- Root component is a `ColumnLayout`, not `Item`
- Use Noctalia's `NToggle`, `NSpinBox` (if available — fall back to `QtQuick.Controls.SpinBox`), `NTextField` (fall back to `TextField`), and `NComboBox`/`NSelector` for enums
- Persist via:
  ```js
  pluginApi.pluginSettings.<key> = root.<internalProp>
  pluginApi.saveSettings()      // note: saveSettings(), NOT savePluginSettings()
  ```
- `saveSettings()` is called by Noctalia's settings framework when the dialog closes, via the `saveSettings()` function on the root component. So the implementation is: keep internal `root.*` state bound to UI controls, and mirror it to `pluginApi.pluginSettings` in the `saveSettings()` function.

If `NSpinBox`/`NTextField`/`NComboBox` don't exist in the version of Noctalia installed, fall back to `QtQuick.Controls` equivalents (`SpinBox`, `TextField`, `ComboBox`); the engineer should grep `/nix/store/*/share/noctalia-shell/` for `N{X}.qml` files to confirm what's available and adjust imports accordingly.

```qml
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root
  property var pluginApi: null

  readonly property var cfg: pluginApi?.pluginSettings || ({})
  readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  property string defaultScope: cfg.defaultScope ?? defaults.defaultScope ?? "partial"
  property bool showRemainingText: cfg.showRemainingText ?? defaults.showRemainingText ?? true
  property bool activateOnLeftClick: cfg.activateOnLeftClick ?? defaults.activateOnLeftClick ?? false
  property int quickExtendMinutes: cfg.quickExtendMinutes ?? defaults.quickExtendMinutes ?? 30
  property bool includeUnlimited: cfg.includeUnlimited ?? defaults.includeUnlimited ?? true
  property string durationsCsv: (cfg.durations ?? defaults.durations ?? []).join(", ")

  spacing: Style.marginL

  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    // Default scope
    RowLayout {
      Layout.fillWidth: true
      NText { text: "Default scope"; Layout.fillWidth: true; color: Color.mOnSurface }
      ComboBox {
        model: ["partial", "full"]
        currentIndex: root.defaultScope === "full" ? 1 : 0
        onActivated: root.defaultScope = model[currentIndex]
      }
    }

    NToggle {
      label: "Show remaining time beside icon"
      checked: root.showRemainingText
      onToggled: checked => root.showRemainingText = checked
    }

    NToggle {
      label: "Left click re-activates last combo (right click opens panel)"
      checked: root.activateOnLeftClick
      onToggled: checked => root.activateOnLeftClick = checked
    }

    RowLayout {
      Layout.fillWidth: true
      NText { text: "Quick-extend (minutes)"; Layout.fillWidth: true; color: Color.mOnSurface }
      SpinBox {
        from: 5; to: 240; stepSize: 5
        value: root.quickExtendMinutes
        onValueModified: root.quickExtendMinutes = value
      }
    }

    RowLayout {
      Layout.fillWidth: true
      NText { text: "Duration choices (min, comma-separated)"; Layout.fillWidth: true; color: Color.mOnSurface }
      TextField {
        Layout.preferredWidth: 200
        text: root.durationsCsv
        onEditingFinished: root.durationsCsv = text
      }
    }

    NToggle {
      label: "Show ∞ (unlimited) option"
      checked: root.includeUnlimited
      onToggled: checked => root.includeUnlimited = checked
    }
  }

  // Called by Noctalia's settings framework when the dialog closes.
  function saveSettings() {
    if (!pluginApi) {
      Logger.e("keep-awake-plus", "Cannot save settings: pluginApi is null");
      return;
    }

    pluginApi.pluginSettings.defaultScope = root.defaultScope;
    pluginApi.pluginSettings.showRemainingText = root.showRemainingText;
    pluginApi.pluginSettings.activateOnLeftClick = root.activateOnLeftClick;
    pluginApi.pluginSettings.quickExtendMinutes = root.quickExtendMinutes;
    pluginApi.pluginSettings.includeUnlimited = root.includeUnlimited;

    const arr = root.durationsCsv
      .split(/\s*,\s*/)
      .map(s => parseInt(s, 10))
      .filter(n => !isNaN(n) && n > 0);
    if (arr.length > 0) {
      pluginApi.pluginSettings.durations = arr;
    }

    pluginApi.saveSettings();
    Logger.i("keep-awake-plus", "Settings saved");
  }
}
```

- [ ] **Step 2: Open Noctalia settings → plugins → keep-awake-plus, exercise each field**

```bash
systemctl --user restart noctalia-shell.service
```
Open Noctalia's settings window, navigate to the plugin's settings pane. Toggle each field, close settings, confirm behavior reflects immediately (e.g., toggle "show remaining text" off → bar widget text disappears).

- [ ] **Step 3: Commit and push**

```bash
cd ~/Data/git/noctalia-plugin-keep-awake
git add Settings.qml
git commit -m "feat: settings pane with scope/durations/extend/display toggles"
git push origin main
```

---

## Phase 5: Switch the bar and bind over to the plugin

### Task 11: Remove `CustomButton` from the bar; bump Hyprland bind; drop legacy `toggle`

**Files:**
- Modify: `/home/noams/nix-config/home/desktop/noctalia/default.nix`
- Modify: `/home/noams/nix-config/home/desktop/hyprland/settings/bindings.nix`
- Modify: `/home/noams/nix-config/home/desktop/hyprland/scripts/system-awake.nix`

- [ ] **Step 1: Replace the `CustomButton` block with the plugin entry**

In `home/desktop/noctalia/default.nix`, find the block starting with `id = "CustomButton";` that contains `system-awake toggle` (around lines 313–329). Delete it entirely and replace with a one-liner:

```nix
              {id = "plugin:keep-awake-plus";}
```

(Place in the same position in the `right = [ ... ]` array so bar ordering is unchanged.)

- [ ] **Step 2: Update the Hyprland bind**

In `home/desktop/hyprland/settings/bindings.nix:42`, change:

```nix
      "$mainMod ALT, K, exec, system-awake toggle" # Cycle system-awake: 30m→2h→8h→∞→off (monitor may sleep)
```

to:

```nix
      "$mainMod ALT, K, exec, system-awake toggle-last" # Re-activate last {duration,scope} combo
```

- [ ] **Step 3: Remove the legacy `toggle` wrapper from `system-awake`**

In `home/desktop/hyprland/scripts/system-awake.nix`, delete the `cmd_toggle_legacy()` function and remove the `toggle)` case from the dispatch block. The usage line also loses `toggle`:

```bash
      *)
        echo "usage: system-awake [start|extend|off|status|label|toggle-last] [args]" >&2
        exit 2
        ;;
```

(Update the header comment at the top of the `system-awake` script to drop the `toggle` row too.)

- [ ] **Step 4: Remove the dev-loop symlink so the plugin manager owns the dir**

```bash
gtrash put ~/.config/noctalia/plugins/keep-awake-plus
```

- [ ] **Step 5: Rebuild**

```bash
just hm
```
Expected: rebuild succeeds. Noctalia restarts. Plugin manager clones fresh from the remote. Bar shows the plugin widget (only one widget now).

- [ ] **Step 6: Full smoke test of the end-to-end experience**

In the bar:
- Hover the widget with Keep Awake off → tooltip "Keep Awake · off".
- Left-click → panel opens, scope = partial (default), durations listed.
- Click `2h` → bar icon turns on, text shows `2h`, tooltip updates live.
- Hover → "Keep Awake · partial · 1h59m left · thermal guard: active".
- Switch scope to `Full` in the panel, click `30m` → icon goes accent-colored.
- Verify `IdleInhibitorService.activeInhibitors` includes `keep-awake-plus` via logs.
- Right-click the bar widget → immediate off.
- Middle-click → re-activates last combo (30m full).
- Right-click → off.
- Press `SUPER+ALT+K` → re-activates last combo.

Run all these. Record any regressions as new tasks or fix inline.

- [ ] **Step 7: Commit**

```bash
git add home/desktop/noctalia/default.nix \
        home/desktop/hyprland/settings/bindings.nix \
        home/desktop/hyprland/scripts/system-awake.nix
git commit -m "feat(noctalia): switch keep-awake to plugin, drop legacy toggle"
```

---

## Phase 6: Cross-host rollout

### Task 12: Deploy to `thinkpad-p14s-g6`

**Files:** no new edits — this is `git push` + remote rebuild.

- [ ] **Step 1: Push the nix-config branch**

Check what branch we're on and push:
```bash
git status
git log --oneline -10
git push origin main
```

- [ ] **Step 2: On the other host (`thinkpad-p14s-g6`), pull and rebuild**

From that host (user-driven, since it's a different machine):
```bash
cd ~/nix-config
git pull --ff-only
just hm
```
Expected: rebuild pulls the new `system-awake` script and the new Noctalia config; the plugin manager fetches `noctalia-plugin-keep-awake` from GitHub on first start; bar widget appears.

- [ ] **Step 3: Smoke test on `g6`**

Same checklist as Phase 5 Step 6.

- [ ] **Step 4: If all good, mark the spec as implemented**

In `docs/superpowers/specs/2026-04-19-keep-awake-plus-design.md`, change the header from:
```
**Status:** draft · **Owner:** Noam · **Date:** 2026-04-19
```
to:
```
**Status:** implemented · **Owner:** Noam · **Date:** 2026-04-19
```

Commit:
```bash
git add docs/superpowers/specs/2026-04-19-keep-awake-plus-design.md
git commit -m "docs(keep-awake-plus): mark spec as implemented"
git push origin main
```

---

## Reference: Files Touched

### New files
- `~/Data/git/noctalia-plugin-keep-awake/` (entire plugin repo, lives outside nix-config)
  - `manifest.json`
  - `Main.qml`
  - `BarWidget.qml`
  - `Panel.qml`
  - `Settings.qml`
  - `README.md`
  - `.gitignore`
  - `LICENSE` (from `gh repo create --license MIT`)

### Modified
- `home/desktop/hyprland/scripts/system-awake.nix` — complete rewrite (Task 1), then legacy wrapper removed (Task 11).
- `home/desktop/hyprland/settings/bindings.nix` — bind target changed `toggle` → `toggle-last` (Task 11).
- `home/desktop/noctalia/default.nix` — add `ownPluginSource` and plugin entries (Task 5), swap `CustomButton` → `plugin:keep-awake-plus` (Task 11).
- `docs/superpowers/specs/2026-04-19-keep-awake-plus-design.md` — header status bumped (Task 12).

### Untouched (explicitly)
- `home/desktop/hyprland/scripts/system-awake-thermal-guard.nix` — thermal guard is unchanged.
- `home/desktop/hyprland/services/hyprdynamicmonitors/scripts/workspace-manager.sh` — `pgrep -f 'systemd-inhibit.*noams-system-awake'` still works for both scopes since both hold a systemd-inhibit with the `noams-system-awake` tag.

---

## Self-Review Notes

- **Spec coverage:** Every spec section has a corresponding task. Goals 1–6 all map: (1) single widget → Task 11; (2) tooltip + text → Task 8; (3) menu + persistence → Task 9 + Task 1 `last.json`; (4) configurable defaults → Task 10; (5) fresh-host reinstall → Task 5 `sourceUrl`; (6) thermal guard preservation → Task 1 leaves the guard alone.
- **One spec deviation** documented in the plan header: `last.json` owned by script, not plugin.
- **Scope for unlimited (duration=-1 sentinel)** is used consistently across Main.qml, Panel.qml, and the shell script.
- **Method-name consistency check:** `start(durationSeconds, pickScope)`, `off()`, `extend(seconds)`, `toggleLast()`, `formatRemaining()`, `_syncIdle()` — all used consistently across tasks 6–10.
- **Plugin API verified** against `~/.config/noctalia/plugins/privacy-indicator/BarWidget.qml`:
  - `pluginApi.openPanel(screen, anchor)` — open this plugin's panel
  - `TooltipService.show(anchor, text, direction)` / `TooltipService.hide()` — standard tooltip
  - `BarService.getTooltipDirection()` — correct direction for current bar orientation
  - `screen`, `widgetId`, `section`, etc. are auto-injected properties
  - Widgets wrap content in a `Rectangle` using `Style.capsuleColor` + `Style.capsuleBorderColor` for visual consistency.

# Hyprland Lua Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close out the hyprlang→Lua migration by fixing the monitor-resolution regression it introduced, then optionally move two shell scripts in-process now that Lua can host them.

**Architecture:** HDM's profile templates gain a machine-readable header line naming each tagged output; `workspace-manager.sh` reads that header instead of parsing monitor geometry out of a file that no longer exists. Phase 2 replaces two `hyprctl`-shelling scripts with Lua bind handlers and a `hl.timer`.

**Tech Stack:** Nix (home-manager, flake-parts), Hyprland 0.56.2 Lua config API, Go text/template (HDM), bash.

## Global Constraints

- Repo is `nix-config`; work happens in the worktree at `~/Data/git/.worktrees/noams/nix-config/fix-hyprland-lua-polish` on branch `fix/hyprland-lua-polish`, branched from `main` after the Lua migration landed as `affc3a21` (squash-merge of PR #186).
- **The regression in Task 1 is live on `main`.** It is not confined to a feature branch.
- **Flakes only see git-tracked files** — `git add` before every build, or evaluation fails with "path does not exist".
- Rebuild with `nh home switch .` (Linux HM-only path). Build-only check: `nh home build .`.
- Pre-commit hooks (alejandra, deadnix, statix, prettier) reformat on the first commit attempt; re-`git add` and re-run the **same** commit. This is expected, not an error.
- `shellcheck` must pass on any edited `.sh` file. Baseline is currently clean.
- Use `gtrash put`, never `rm`.
- Hyprland's Lua main chunk **aborts at the first nil call** — a wrong `hl.*` name silently kills the whole config. Validate names against `src/config/lua/bindings/LuaBindingsConfigRules.cpp:1392` and `LuaBindingsToplevel.cpp:536-551`.
- Verify runtime state with `hyprctl` using the **live** instance signature; a long-lived tmux pane may hold a stale `HYPRLAND_INSTANCE_SIGNATURE`. Get the current one from `ls -t $XDG_RUNTIME_DIR/hypr/ | head -1`.

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `home/desktop/hyprland/services/hyprdynamicmonitors/profiles/docked-home.lua.in` | Home dock profile | Modify — move template vars to top, add `-- hdm:` header |
| `…/profiles/docked-office.lua.in` | Office dock profile | Modify — same |
| `…/profiles/undocked.lua.in` | Laptop-only profile | Modify — same (laptop tag only) |
| `…/profiles/undocked-lid-closed.lua.in` | Laptop-only, lid shut | Modify — same (laptop tag only) |
| `…/scripts/workspace-manager.sh` | Relocates live workspaces after a profile switch | Modify — replace `resolve_monitor_from_conf`, fix stale comments |
| `home/desktop/hyprland/scripts/toggle-floating.nix` | Smart float toggle | Delete (Phase 2) |
| `home/desktop/hyprland/settings/bindings.nix` | Keybinds → Lua | Modify (Phase 2) |
| `home/desktop/hyprland/scripts/accessibility-tools.nix` | zoom-step + STT tools | Modify (Phase 2) — drop `zoom-step` |

---

## Task 1: Fix monitor resolution (regression)

`resolve_monitor_from_conf` parses `~/.config/hypr/monitors.conf`, which the migration replaced with `monitors.lua`. It currently falls through to a Hyprland query that runs **before** `hyprctl reload` applies the new layout, so it can resolve against the old monitor arrangement. Symptom: workspaces land on the wrong monitor after dock/undock, intermittently.

The fix also removes the x-coordinate guessing: the template knows the tag→output mapping as ground truth, so it states it.

**Files:**
- Modify: `home/desktop/hyprland/services/hyprdynamicmonitors/profiles/docked-home.lua.in`
- Modify: `home/desktop/hyprland/services/hyprdynamicmonitors/profiles/docked-office.lua.in`
- Modify: `home/desktop/hyprland/services/hyprdynamicmonitors/profiles/undocked.lua.in`
- Modify: `home/desktop/hyprland/services/hyprdynamicmonitors/profiles/undocked-lid-closed.lua.in`
- Modify: `home/desktop/hyprland/services/hyprdynamicmonitors/scripts/workspace-manager.sh:86-128`

**Interfaces:**
- Produces: `resolve_monitor_from_profile <tag>` → prints an output name (e.g. `DP-8`) on stdout, empty on total failure. Accepted tags: `left`, `right`, `laptop`, `eDP`. A `tag` already containing `-` is echoed back unchanged (it is already a real output name). Falls back to the existing `resolve_monitor` on missing file or missing tag.
- Consumes: nothing from other tasks.

- [ ] **Step 1: Write the failing parser test**

Create the fixture and test in the scratchpad (this repo has no test framework and adding one is out of scope; this is a throwaway red/green harness):

```bash
mkdir -p /tmp/hypr-polish-test && cd /tmp/hypr-polish-test

# Fixture: what the docked template MUST render
cat > monitors.lua <<'EOF'
-- hdm: left=DP-8 right=DP-7 laptop=eDP-1
-- Docked at home - Samsung monitors with dynamic lid handling
hl.monitor({ output = "DP-8", mode = "2560x1440@60", position = "0x0", scale = 1.0 })
hl.monitor({ output = "DP-7", mode = "2560x1440@60", position = "2560x0", scale = 1.0 })
EOF

# Fixture: undocked (laptop tag only)
cat > monitors-undocked.lua <<'EOF'
-- hdm: laptop=eDP-1
-- Undocked - laptop only with dynamic lid handling
hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 2.0 })
EOF

cat > test-resolve.sh <<'EOF'
#!/usr/bin/env bash
# Red/green harness for resolve_monitor_from_profile.
set -uo pipefail
FAIL=0
check() { # check <desc> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "  ok   $1"; else echo "  FAIL $1: expected '$2' got '$3'"; FAIL=1; fi
}

log() { :; }                       # silence the script's logger
resolve_monitor() { echo "FALLBACK"; }   # stand in for the Hyprland query

# shellcheck source=/dev/null
source ./resolve.sh

HOME_ORIG="$HOME"
export HOME=/tmp/hypr-polish-test/fake-home
mkdir -p "$HOME/.config/hypr"

cp /tmp/hypr-polish-test/monitors.lua "$HOME/.config/hypr/monitors.lua"
check "left  -> DP-8"  "DP-8"  "$(resolve_monitor_from_profile left)"
check "right -> DP-7"  "DP-7"  "$(resolve_monitor_from_profile right)"
check "laptop-> eDP-1" "eDP-1" "$(resolve_monitor_from_profile eDP-1)"
check "eDP   -> eDP-1" "eDP-1" "$(resolve_monitor_from_profile eDP)"
check "passthrough"    "DP-99" "$(resolve_monitor_from_profile DP-99)"

cp /tmp/hypr-polish-test/monitors-undocked.lua "$HOME/.config/hypr/monitors.lua"
check "undocked laptop" "eDP-1"    "$(resolve_monitor_from_profile laptop)"
check "missing tag"     "FALLBACK" "$(resolve_monitor_from_profile left)"

rm -f "$HOME/.config/hypr/monitors.lua"
check "missing file"    "FALLBACK" "$(resolve_monitor_from_profile left)"

export HOME="$HOME_ORIG"
exit $FAIL
EOF
chmod +x test-resolve.sh
: > resolve.sh   # empty — function does not exist yet
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd /tmp/hypr-polish-test && ./test-resolve.sh`
Expected: FAIL — `resolve_monitor_from_profile: command not found` for every case.

- [ ] **Step 3: Write the resolver into the harness**

```bash
cat > /tmp/hypr-polish-test/resolve.sh <<'EOF'
# Resolve a tagged monitor from the HDM-rendered profile.
# HDM writes monitors.lua before running post_apply_exec, so its header is
# authoritative even before `hyprctl reload` applies the layout to Hyprland —
# querying Hyprland here would return the OLD arrangement.
# Header format (first line): -- hdm: left=DP-8 right=DP-7 laptop=eDP-1
resolve_monitor_from_profile() {
  local identifier="$1"
  local profile="$HOME/.config/hypr/monitors.lua"

  # Already a concrete output name (e.g. DP-8, eDP-1).
  if [[ $identifier == *-* ]]; then
    echo "$identifier"
    return 0
  fi

  [ "$identifier" = "eDP" ] && identifier="laptop"

  if [ ! -f "$profile" ]; then
    log "WARNING: monitors.lua not found, falling back to Hyprland query"
    resolve_monitor "$identifier"
    return
  fi

  local name
  name=$(sed -n "s/^-- hdm:.*\\b${identifier}=\\([^ ]*\\).*/\\1/p" "$profile" | head -1)

  if [ -z "$name" ]; then
    log "WARNING: tag '$identifier' absent from monitors.lua header, falling back to Hyprland query"
    resolve_monitor "$identifier"
    return
  fi

  echo "$name"
}
EOF
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd /tmp/hypr-polish-test && ./test-resolve.sh`
Expected: all 8 lines `ok`, exit 0.

- [ ] **Step 5: Add the header to the two docked templates**

Move the template variable assignments above the comment block so the `-- hdm:` line is the first rendered output. This also fixes the merged-comment cosmetic: today the trailing `-}}` trims the newline after the last comment, running it into the next line.

For `docked-home.lua.in`, replace lines 1-8 (through the three `{{- … -}}` assignments) with:

```
{{- $left := index .MonitorsByTag "left" -}}
{{- $right := index .MonitorsByTag "right" -}}
{{- $laptop := index .MonitorsByTag "laptop" -}}
-- hdm: left={{$left.Name}} right={{$right.Name}} laptop={{$laptop.Name}}
-- Docked at home - Samsung monitors with dynamic lid handling
-- Template automatically enables/disables laptop screen based on lid state
-- Uses .MonitorsByTag for gen5/gen6 compatibility
-- Rendered by hyprdynamicmonitors; required from startup.lua (Hyprland has no hl.source()).
-- The `-- hdm:` header above is parsed by workspace-manager.sh — keep it first.
```

For `docked-office.lua.in`, the identical block but with the office description line:

```
{{- $left := index .MonitorsByTag "left" -}}
{{- $right := index .MonitorsByTag "right" -}}
{{- $laptop := index .MonitorsByTag "laptop" -}}
-- hdm: left={{$left.Name}} right={{$right.Name}} laptop={{$laptop.Name}}
-- Docked at office - Dell monitors with dynamic lid handling
-- Template automatically enables/disables laptop screen based on lid state
-- Uses .MonitorsByTag for gen5/gen6 compatibility
-- Rendered by hyprdynamicmonitors; required from startup.lua (Hyprland has no hl.source()).
-- The `-- hdm:` header above is parsed by workspace-manager.sh — keep it first.
```

- [ ] **Step 6: Add the header to the two undocked templates**

For `undocked.lua.in`, replace the comment block and the single assignment with:

```
{{- $laptop := index .MonitorsByTag "laptop" -}}
-- hdm: laptop={{$laptop.Name}}
-- Undocked - laptop only with dynamic lid handling
-- Template handles both lid open (normal use) and lid closed (triggers suspend via script)
-- Uses .MonitorsByTag for gen5/gen6 compatibility
-- Rendered by hyprdynamicmonitors; required from startup.lua (Hyprland has no hl.source()).
-- The `-- hdm:` header above is parsed by workspace-manager.sh — keep it first.
```

For `undocked-lid-closed.lua.in`:

```
{{- $laptop := index .MonitorsByTag "laptop" -}}
-- hdm: laptop={{$laptop.Name}}
-- Undocked with lid closed - laptop only, triggers suspend via workspace-manager.
-- Must stay in sync with undocked.lua.in — HDM skips post_apply_exec when the
-- rendered monitors.lua is byte-identical to the previous profile's output,
-- so this file MUST render differently from undocked.lua (hence this comment).
-- Uses .MonitorsByTag for gen5/gen6 compatibility
-- Rendered by hyprdynamicmonitors; required from startup.lua (Hyprland has no hl.source()).
-- The `-- hdm:` header above is parsed by workspace-manager.sh — keep it first.
```

Leave the rest of each file (the `hl.monitor` / `hl.workspace_rule` body) untouched.

- [ ] **Step 7: Replace the resolver in workspace-manager.sh**

Delete lines 86-128 of `home/desktop/hyprland/services/hyprdynamicmonitors/scripts/workspace-manager.sh` — the `# Resolve left/right monitor from the newly-written monitors.conf.` comment block through the closing `}` of `resolve_monitor_from_conf` — and put in its place the exact function body from Step 3 (the `resolve_monitor_from_profile` definition, comment included).

- [ ] **Step 8: Update the two call sites**

At `configure_docked` (was lines 146-147), replace:

```bash
  left=$(resolve_monitor_from_conf "$left_identifier")
  right=$(resolve_monitor_from_conf "$right_identifier")
```

with:

```bash
  left=$(resolve_monitor_from_profile "$left_identifier")
  right=$(resolve_monitor_from_profile "$right_identifier")
```

Then confirm no callers remain:

Run: `grep -n resolve_monitor_from_conf home/desktop/hyprland/services/hyprdynamicmonitors/scripts/workspace-manager.sh`
Expected: no output.

- [ ] **Step 9: Fix the stale comments**

In the same file, in `configure_docked` (was lines 136-137), replace:

```bash
  # Resolve from monitors.conf, NOT from Hyprland's current state.
  # workspace-manager runs immediately after HDM writes monitors.conf but
```

with:

```bash
  # Resolve from monitors.lua, NOT from Hyprland's current state.
  # workspace-manager runs immediately after HDM writes monitors.lua but
```

And in the WS 9 comment (was line 174), replace `docked-*.conf.in` with `docked-*.lua.in`.

Then confirm nothing stale is left:

Run: `grep -rn "monitors\.conf\|\.conf\.in" home/desktop/hyprland/`
Expected: no output.

- [ ] **Step 10: Shellcheck**

Run: `shellcheck home/desktop/hyprland/services/hyprdynamicmonitors/scripts/workspace-manager.sh`
Expected: no output, exit 0 (baseline was clean — keep it clean).

- [ ] **Step 11: Build**

```bash
git add -A
nh home build .
```
Expected: builds without error.

- [ ] **Step 12: Verify the rendered profile carries the header**

```bash
nh home switch .
head -1 ~/.config/hypr/monitors.lua
```
Expected: a line of the form `-- hdm: left=DP-8 right=DP-7 laptop=eDP-1` (names will match your current dock). If you are undocked, expect `-- hdm: laptop=eDP-1`.

Then confirm the config still loads clean:

```bash
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr/ | head -1)
hyprctl configerrors
```
Expected: empty output.

- [ ] **Step 13: Commit**

```bash
git add -A
git commit -m "fix(hyprland): resolve monitors from monitors.lua header

workspace-manager.sh still parsed monitors.conf, which the Lua migration
replaced with monitors.lua. It silently fell through to a Hyprland query
that runs before hyprctl reload applies the new layout, so it could
resolve against the previous monitor arrangement and put workspaces on
the wrong screen after a dock/undock.

HDM templates now emit a '-- hdm: <tag>=<output> ...' header as their
first line and the script reads that, replacing the awk that inferred
left/right from x-coordinates. The template knows the tag mapping as
ground truth, so this is more correct than the pre-migration behaviour.

Moving the template var assignments to the top also fixes the trailing
'-}}' trim that ran two comment lines together in the rendered output."
```

---

## Task 2: Cold-boot verification (gate)

`hl.on("hyprland.start", …)` fires only at compositor startup. Every session so far began on either the old hyprlang config or Hyprland's autogenerated stub, so the exec-once chain has never actually executed. **Phase 2 does not begin until this passes** — a cold-start failure could invalidate assumptions the rewrites build on.

**Files:** none (verification only).

**Interfaces:**
- Consumes: Task 1's committed state.
- Produces: a go/no-go for Phase 2.

- [ ] **Step 1: Log out and log back in**

A full logout/login, not a `hyprctl reload` — the provider and the start hook are both decided at compositor startup.

- [ ] **Step 2: Verify the config loaded as Lua and is clean**

```bash
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr/ | head -1)
grep -m1 "cfg. Using" $XDG_RUNTIME_DIR/hypr/*/hyprland.log
hyprctl configerrors
```
Expected: a line reading `[cfg] Using lua config found at /home/noams/.config/hypr/hyprland.lua`, and empty `configerrors`.

If instead you see `Lua config not found, using legacy config` or the file `~/.config/hypr/hyprland.conf` reappears containing `autogenerated = 1`, the Lua config failed to load — capture `hyprctl configerrors` and stop.

- [ ] **Step 3: Verify the exec-once chain ran**

```bash
pgrep -a noctalia-shell
pgrep -a kitty
hyprctl layers | grep -oE 'namespace: [a-z-]+' | sort -u
```
Expected: `noctalia-shell` running, a `kitty` process, and `noctalia-bar-content-` among the layer namespaces.

- [ ] **Step 4: Verify env propagation**

```bash
fish -c 'echo $HYPRLAND_INSTANCE_SIGNATURE; echo $WAYLAND_DISPLAY'
tmux show-environment -g HYPRLAND_INSTANCE_SIGNATURE
tmux show-environment -g XDG_RUNTIME_DIR
xrdb -query | head -3
```
Expected: the fish universal vars match the live instance signature and `wayland-1`; both tmux globals are set; `xrdb -query` returns the merged `.Xresources` entries (non-empty).

- [ ] **Step 5: Verify theme restore**

```bash
hyprctl getoption decoration:rounding
```
Expected: `int: 10`, `set: true` — confirms the config applied, and `theme-toggle restore` did not error out (check `hyprctl configerrors` again if the theme looks wrong).

- [ ] **Step 6: Exercise the Task 1 fix for real**

Dock (or undock, whichever is the opposite of your current state), then:

```bash
grep -iE "WARNING|ERROR" /tmp/workspace-manager.log | tail -20
hyprctl workspaces -j | jq -r '.[] | "\(.id) -> \(.monitor)"' | sort -n
```
Expected: **no** `WARNING: monitors.lua not found` and no `ERROR: Failed to resolve monitors` in the log. Workspaces 1-4 on the left output, 5-8 on the right, 9 per lid state.

Then undock (or re-dock) and re-check, to cover both transitions.

- [ ] **Step 7: Record the result**

If everything passed, note it on PR #186 and proceed. If anything failed, stop and diagnose — do not start Phase 2 on a broken cold-start path.

---

## Task 3: Port `toggle-floating` to a Lua bind handler (Phase 2)

Low-risk shakedown of the Lua-callback pattern before the timer work. Removes a `jq` invocation and two `hyprctl` round-trips from a latency-sensitive key.

**Files:**
- Delete: `home/desktop/hyprland/scripts/toggle-floating.nix`
- Modify: `home/desktop/hyprland/default.nix` (drop the import)
- Modify: `home/desktop/hyprland/settings/bindings.nix`

**Interfaces:**
- Consumes: the `extraLuaFiles."bindings"` block established by the migration.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Confirm the window property exists before writing code**

```bash
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr/ | head -1)
hyprctl activewindow -j | jq '.floating'
```
Expected: `true` or `false`. This is the property the Lua handler reads as `hl.get_window().floating`; it is exposed on the Lua window object (verified in `src/config/lua/objects/LuaWindow.cpp`).

- [ ] **Step 2: Replace the bind with a Lua handler**

In `home/desktop/hyprland/settings/bindings.nix`, replace:

```
    -- Smart toggle floating: tiled→float+resize+center, floating→just unfloat
    hl.bind(mainMod .. " + T", hl.dsp.exec_cmd("toggle-floating"))
```

with:

```
    -- Smart toggle floating: tiled -> float + resize 65% + center;
    -- floating -> just unfloat and let the tiling layout size it.
    hl.bind(mainMod .. " + T", function()
      local w = hl.get_window()
      if not w then return end
      local wasFloating = w.floating

      hl.dispatch(hl.dsp.window.float({ action = "toggle" }))

      -- Tiled -> floating: give it a sane size and position.
      -- Floating -> tiled needs nothing; the layout sizes it.
      if not wasFloating then
        hl.dispatch(hl.dsp.window.resize({ x = "65%", y = "65%" }))
        hl.dispatch(hl.dsp.window.center())
      end
    end)
```

- [ ] **Step 3: Remove the now-dead script**

```bash
gtrash put home/desktop/hyprland/scripts/toggle-floating.nix
```

Then remove its import line from `home/desktop/hyprland/default.nix`:

```
    ./scripts/toggle-floating.nix
```

- [ ] **Step 4: Build and switch**

```bash
git add -A
nh home switch .
```
Expected: builds and activates without error.

- [ ] **Step 5: Verify no config errors and the binary is gone**

```bash
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr/ | head -1)
hyprctl configerrors
command -v toggle-floating
```
Expected: `configerrors` empty; `command -v` finds nothing (exit 1).

- [ ] **Step 6: Verify behaviour by hand**

Focus a tiled window, press `SUPER+T`: it should float at roughly 65% and centre. Press `SUPER+T` again: it should return to tiling. Then confirm nothing broke:

```bash
hyprctl configerrors
```
Expected: still empty. If `hl.dsp.window.resize` rejects the `"65%"` string form, fall back to `hl.dispatch(hl.dsp.exec_cmd("hyprctl dispatch resizeactive exact 65% 65%"))` for that one line and note it in the commit.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(hyprland): toggle-floating as a Lua bind handler

Reads window.floating in-process instead of shelling out to
hyprctl activewindow + jq, removing a subprocess and two hyprctl
round-trips from a latency-sensitive keybind."
```

---

## Task 4: Port `zoom-step` to `hl.timer` (Phase 2)

`zoom-step` eases `cursor:zoom_factor` toward a target at ~60fps from a detached subshell: every frame spawns `hyprctl keyword cursor:zoom_factor` then `sleep 0.016`, coordinated through a `mkdir` lock and two files under `/tmp`. A `hl.timer` does the easing in-process — roughly 60 fewer process spawns per second while zooming, and no lock or state files.

**Risk:** timer callbacks run on the compositor event loop under a timeout budget. Keep the callback to arithmetic plus one config write, and disable the timer as soon as the target is reached.

Already checked: `cursor:zoom_factor` is declared with `refresh = Supplementary::REFRESH_CURSOR_ZOOMS` (`src/config/values/ConfigValues.cpp:602`), so writing it schedules only the cursor-zoom refresh, not a full config reload. It is the same code path `hyprctl keyword` takes, minus the process spawn and IPC round-trip — so the per-frame cost is strictly lower than the current implementation.

**Files:**
- Modify: `home/desktop/hyprland/scripts/accessibility-tools.nix:105-160` (remove the `zoom-step` derivation and its entry in the package list)
- Modify: `home/desktop/hyprland/settings/bindings.nix`

**Interfaces:**
- Consumes: the `extraLuaFiles."bindings"` block.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Verify the timer API and the runtime config write**

`hl.timer(fn, { timeout = <ms>, type = "repeat"|"oneshot" })` returns a timer object with `set_enabled`, `is_enabled`, and `set_timeout` (verified in `src/config/lua/objects/LuaTimer.cpp` and `LuaBindingsToplevel.cpp:460`). Confirm a runtime write to the zoom factor takes effect:

```bash
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr/ | head -1)
hyprctl keyword cursor:zoom_factor 1.5
hyprctl getoption cursor:zoom_factor
hyprctl keyword cursor:zoom_factor 1.0
```
Expected: the middle command reports `float: 1.50000`. This confirms the option is writable at runtime; the Lua equivalent is `hl.config({ cursor = { zoom_factor = v } })`.

- [ ] **Step 2: Add the zoom module as its own Lua file**

Create the file by adding this to `home/desktop/hyprland/settings/bindings.nix`, as a sibling of the existing `extraLuaFiles."bindings"` attribute:

```nix
  # KDE-style screen zoom with smooth easing, in-process.
  # Replaces the zoom-step script, which spawned an hyprctl per animation
  # frame (~60/s) plus a mkdir lock and two /tmp state files.
  wayland.windowManager.hyprland.extraLuaFiles."zoom".content = ''
    local MIN, MAX, STEP = 1.0, 5.0, 0.5
    local FRAME_MS = 16

    local current, target = MIN, MIN
    local timer = nil

    local function apply(v)
      hl.config({ cursor = { zoom_factor = v } })
    end

    local function tick()
      local diff = target - current
      -- Close enough: snap, stop the timer, and stand down.
      if math.abs(diff) < 0.001 then
        current = target
        apply(current)
        if timer then timer:set_enabled(false) end
        return
      end
      -- Ease ~33% of the remaining distance per frame.
      current = current + diff / 3
      apply(current)
    end

    local function zoom(action)
      if action == "in" then
        target = math.min(target + STEP, MAX)
      elseif action == "out" then
        target = math.max(target - STEP, MIN)
      else
        target = MIN
      end

      if not timer then
        timer = hl.timer(tick, { timeout = FRAME_MS, type = "repeat" })
      else
        timer:set_enabled(true)
      end
    end

    hl.bind("SUPER + CTRL + mouse_down", function() zoom("in") end)
    hl.bind("SUPER + CTRL + mouse_up", function() zoom("out") end)
    hl.bind("SUPER + CTRL + 0", function() zoom("reset") end)
  '';
```

- [ ] **Step 3: Remove the three old zoom binds**

In the `extraLuaFiles."bindings"` content in the same file, delete these three lines (they are now owned by `zoom.lua`):

```
    hl.bind(mainMod .. " + CTRL + 0", hl.dsp.exec_cmd("zoom-step reset"))
    hl.bind(mainMod .. " + CTRL + mouse_down", hl.dsp.exec_cmd("zoom-step in"))
    hl.bind(mainMod .. " + CTRL + mouse_up", hl.dsp.exec_cmd("zoom-step out"))
```

- [ ] **Step 4: Remove the zoom-step derivation**

In `home/desktop/hyprland/scripts/accessibility-tools.nix`, delete the `zoom-step = pkgs.writeShellScriptBin "zoom-step" '' … '';` binding (the block starting at the `# KDE-style screen zoom with smooth easing.` comment, around line 105, through its closing `'';` around line 160) and remove the bare `zoom-step` entry from the package list (around line 180).

- [ ] **Step 5: Build and switch**

```bash
git add -A
nh home switch .
```
Expected: builds and activates without error.

- [ ] **Step 6: Verify no config errors and no leftover state**

```bash
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr/ | head -1)
hyprctl configerrors
command -v zoom-step
ls /tmp/hypr-zoom-* 2>&1
```
Expected: `configerrors` empty; `command -v` finds nothing; the old `/tmp/hypr-zoom-target`, `/tmp/hypr-zoom-current`, and `/tmp/hypr-zoom-animator.lock` may still exist from the previous implementation — `gtrash put` them.

- [ ] **Step 7: Verify behaviour and that no subprocesses spawn**

In one pane, watch for stray processes while you zoom:

```bash
watch -n0.5 'pgrep -c hyprctl'
```

In the session, hold `SUPER+CTRL` and scroll up a few ticks, then down, then press `SUPER+CTRL+0`.

Expected: the zoom eases smoothly in and out and returns exactly to 1.0 on reset; the `hyprctl` count stays at 0 throughout (the old implementation would show a steady stream). Confirm the factor landed:

```bash
hyprctl getoption cursor:zoom_factor
```
Expected: `float: 1.00000` after reset.

Also confirm the compositor did not stutter — if it did, the timer callback is too heavy; reduce to `FRAME_MS = 33` and re-test.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(hyprland): zoom-step as an in-process hl.timer

The script eased cursor:zoom_factor at ~60fps from a detached subshell,
spawning an hyprctl per frame plus a mkdir lock and two /tmp state
files. hl.timer does the easing in-process and disables itself once the
target is reached."
```

---

## Not doing

Recorded so the next reader does not re-derive these:

- **`window-resize` → Lua.** Branches on the window's `pseudo` state. Lua exposes `pseudo` as a dispatcher (`hl.dsp.window.pseudo`) and a window-rule effect, but **not** as a readable property on the window object (verified against `src/config/lua/objects/LuaWindow.cpp`). `hyprctl activewindow -j` does expose it. Mirroring pseudo state into a window tag to work around this adds a correctness burden to save one subprocess per keypress — not worth it. Stays a script.
- **`monitor.added` event handling.** Lua can react to hotplug natively, but HDM already owns this and works, and additionally handles lid and AC state over DBus, which Lua cannot reach. Splitting ownership buys nothing visible.
- **`hl.notification`, bind handles (`:set_enabled`), wider query-API use.** No current need.

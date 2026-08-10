# macOS Appearance-Following Theme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** CLI/terminal apps on macOS (`mbp-m4-pro`) follow the system Light/Dark appearance automatically, at parity with the Linux theme-toggle for every themeable app that runs on the Mac.

**Architecture:** Extract the platform-neutral per-app theming logic from the Hyprland-coupled `theme-toggle.sh` into a cross-platform `home/theme/` module (shared shell lib + palette→env-var injection). Linux keeps its Noctalia/systemctl/notify orchestration. macOS gets a thin driver script that reads `defaults read -g AppleInterfaceStyle` and runs the shared updaters, fired by a nix-darwin `launchd.user.agents` agent watching `~/Library/Preferences/.GlobalPreferences.plist`.

**Tech Stack:** Nix (flake-parts, Home Manager, nix-darwin), Bash, launchd, Catppuccin Mocha/Latte palette.

**Spec:** `docs/superpowers/specs/2026-06-22-macos-theme-follow-design.md`

> **Testing note:** This is Nix/shell infra — there is no unit-test harness. Each task's "verification" is a build/eval check (`nix eval`/`nix flake check`) plus a behavioral check (flip appearance, observe). The Linux regression check in Task 3 is the safety net for the refactor. **The implementer must run the Linux verification (Task 3) on a Linux host (a ThinkPad) and the macOS verification (Tasks 6–8) on the Mac.** Cross-platform eval (`nix eval .#darwinConfigurations...`) can be done from either.

---

## File Structure

**New files:**
- `home/theme/default.nix` — cross-platform theme module entry; imports palette + declares the `programs.theme-toggle` option (no Linux-deps default).
- `home/theme/palette.nix` — **moved** from `home/desktop/theme/palette.nix` (verbatim).
- `home/theme/palette-env.nix` — exposes the palette→env-var export block + external theme fetches (catppuccin-lazygit, catppuccin-yazi) as a reusable string + runtimeInputs list.
- `home/theme/lib/theme-apply.sh` — shared `update_*` functions + helpers + a neutral no-tail parallel runner, extracted from `theme-toggle.sh`.
- `home/darwin/theme/default.nix` — macOS driver: `theme-apply-macos` script, sets `programs.theme-toggle.package`, HM-clobber clean + apply activation.

**Modified files:**
- `home/noams.nix` — import `./theme` instead of `./desktop/theme/palette.nix`.
- `home/desktop/theme/default.nix` — drop the now-relocated `./palette.nix` import.
- `home/desktop/hyprland/scripts/theme-toggle.nix` — consume `home/theme` (palette-env + shared lib); keep Linux orchestration deps.
- `home/desktop/hyprland/scripts/sh/theme-toggle.sh` — remove the extracted functions; source the shared lib; keep orchestration + Linux-only updaters.
- `home/darwin/default.nix` — import `./theme`.
- `hosts/mbp-m4-pro/default.nix` — add `launchd.user.agents.theme-watch`; remove the `AppleInterfaceStyle = "Dark"` pin.

---

## Task 1: Create the cross-platform `home/theme/` module (palette + option, no behavior change yet)

This task only *relocates* the palette and declares the option. No script changes yet — so both Linux and macOS still build identically.

**Files:**
- Create: `home/theme/default.nix`
- Create (move): `home/theme/palette.nix`
- Modify: `home/noams.nix:15`
- Modify: `home/desktop/theme/default.nix:3`
- Modify: `home/desktop/hyprland/scripts/theme-toggle.nix` (remove the duplicate option *declaration* — see Step 4b)

> **Correction (applied during execution):** `theme-toggle.nix` already declares
> `options.programs.theme-toggle.package` (`readOnly`, with a default). Declaring
> it again in `home/theme` collides, so the declaration must move here in the SAME
> task — Step 4b below. (Originally this edit was deferred to Task 3; it can't be.)

- [ ] **Step 1: Move palette.nix into the new module**

```bash
cd ~/nix-config-worktrees/feat-24-macos-theme-follow
mkdir -p home/theme/lib
git mv home/desktop/theme/palette.nix home/theme/palette.nix
```

- [ ] **Step 2: Create `home/theme/default.nix`**

```nix
{lib, ...}: {
  imports = [./palette.nix];

  # Cross-platform handle to the active theme switcher binary. Each platform
  # assigns its own derivation (Linux: full theme-toggle; macOS: theme-apply-macos)
  # so the Mac closure never pulls Linux-only deps. No default — setting it is
  # each platform wrapper's job.
  options.programs.theme-toggle.package = lib.mkOption {
    type = lib.types.package;
    description = "The platform's theme switcher package.";
  };
}
```

- [ ] **Step 3: Point `home/noams.nix` at the new module**

In `home/noams.nix`, replace the `./desktop/theme/palette.nix` import (line ~15) and its comment block with `./theme`:

```nix
      # Cross-platform theme module (palette color data + theme-toggle option).
      # Imported unconditionally so it's available on darwin too; the desktop
      # tree consumes the same palette for its GTK/catppuccin bits.
      ./theme
```

- [ ] **Step 4: Stop the desktop tree from re-importing the moved palette**

In `home/desktop/theme/default.nix`, remove the `./palette.nix` line from `imports` (the palette now comes from the always-imported `home/theme`). Result:

```nix
{...}: {
  imports = [
    ./catppuccin.nix
    ./gtk.nix
  ];
  # ... (keep the existing comment block below)
}
```

- [ ] **Step 4b: Move the option declaration out of `theme-toggle.nix`**

In `home/desktop/hyprland/scripts/theme-toggle.nix`, delete the `options.programs.theme-toggle = { package = lib.mkOption {...}; };` block (it now lives in `home/theme/default.nix`). Make the return set *only* config — install the package AND set the now-cross-platform option value so Linux consumers (`catppuccin.nix`) still resolve it:

```nix
in {
  config = {
    home.packages = [theme-toggle];
    programs.theme-toggle.package = theme-toggle;
  };
}
```

(`lib` stays in scope — it's still used elsewhere in the file.)

- [ ] **Step 5: Verify both configs evaluate**

Run:
```bash
nix eval .#darwinConfigurations.mbp-m4-pro.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.thinkpad-p14s-g6.config.system.build.toplevel.drvPath
```
Expected: **both** print a `/nix/store/...drv` path. With Step 4b applied, the option is declared once (in `home/theme`) and set once (in `theme-toggle.nix` for Linux), so neither a duplicate-declaration nor an unset-option error should occur.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(theme): move palette into cross-platform home/theme module (#24)"
```

---

## Task 2: Extract the shared shell lib and palette-env, make bat/fzf/tmux platform-aware

This is the mechanical core extraction. The shared lib holds every neutral `update_*` plus the three Linux-coupled ones (made platform-aware), the helpers, and a no-tail parallel runner.

**Files:**
- Create: `home/theme/lib/theme-apply.sh`
- Create: `home/theme/palette-env.nix`

- [ ] **Step 1: Create `home/theme/lib/theme-apply.sh` with the helpers + neutral runner**

Start the file with the logging/state/failure helpers and a platform-neutral parallel runner (note: **no `signal_apps` tail**). Copy the helper bodies **verbatim** from `home/desktop/hyprland/scripts/sh/theme-toggle.sh` lines 44–145 (`log_debug`, `log_error`, `log_warn`, `migrate_legacy_state`, `get_current_theme`, `get_failed_updates`, `write_state`, `failed_to_json`, `record_failure`, `collect_parallel_failures`) and the state-config block lines 27–42.

```bash
# theme-apply.sh — shared, platform-neutral theme application library.
# Sourced by the Linux theme-toggle wrapper and the macOS theme-apply-macos
# driver. Contains ONLY platform-neutral logic: per-app update_* functions,
# failure tracking, and a parallel runner with no signaling tail. Platform
# orchestration (Noctalia/systemctl/notify on Linux; launchd/defaults on macOS)
# lives in the respective wrappers.

# <-- paste lines 27-42 (STATE_DIR..LATTE_LAVENDER) here -->
# <-- paste lines 44-145 (logging, state, record_failure, collect_parallel_failures) here -->

# Run a list of update fns in parallel, collecting failures. No signaling tail.
# Args: theme + update fn names.
_run_updates_neutral() {
  local theme="$1"
  shift
  FAILED_UPDATES=()
  FAILED_DIR=$(mktemp -d -t theme-apply.XXXXXX) || {
    log_warn "mktemp failed; falling back to sequential"
    local fn
    for fn in "$@"; do "$fn" "$theme" || true; done
    return 0
  }
  export FAILED_DIR
  local fn
  for fn in "$@"; do "$fn" "$theme" & done
  wait
  collect_parallel_failures
}
```

- [ ] **Step 2: Append the neutral per-app updaters verbatim**

Append these functions, copied **verbatim** from `theme-toggle.sh`, into `theme-apply.sh`:
`update_kitty` (393–457), `update_fish` (460–482), `update_starship` (485–509), `update_lazygit` (565–626), `update_btop` (628–663), `update_lazydocker` (666–699), `update_process_compose` (847–874), `update_delta` (969–1019), `update_yazi` (1109–1186).

(Leave `update_k9s`, `update_gtk_*`, `update_hyprland_borders`, `update_kvantum`, `update_noctalia`, `update_vicinae`, `update_kde_colorscheme`, `update_foot`, `update_ghostty` in the Linux script — they are Linux-only and out of macOS scope.)

- [ ] **Step 3: Add platform-aware `update_bat`**

bat/fzf set fish-universal vars plus Linux `systemctl set-environment` + `hyprctl keyword env`. Guard the Linux-only calls so the shared function is safe on macOS (fish-universal propagation only there). Append:

```bash
# Update bat syntax highlighter theme.
# macOS: fish-universal only. Linux: also exports to systemd + hyprland env.
update_bat() {
  local theme="$1"
  local bat_theme
  log_debug "Updating bat to $theme"

  if [[ $theme == "light" ]]; then
    bat_theme="Catppuccin Latte"
  else
    bat_theme="Catppuccin Mocha"
  fi

  fish -c "set -U BAT_THEME '$bat_theme'; true" 2>/dev/null || true
  fish -c "set -gx BAT_THEME '$bat_theme'; true" 2>/dev/null || true

  if [[ ${THEME_APPLY_PLATFORM:-linux} == "linux" ]]; then
    systemctl --user set-environment BAT_THEME="$bat_theme" 2>/dev/null || true
    hyprctl keyword env BAT_THEME,"$bat_theme" >/dev/null 2>&1 || true
  fi
}
```

- [ ] **Step 4: Add platform-aware `update_fzf`**

```bash
# Update fzf fuzzy finder colors.
# macOS: fish-universal only. Linux: also exports to systemd + hyprland env.
update_fzf() {
  local theme="$1"
  local fzf_colors
  log_debug "Updating fzf to $theme"

  if [[ $theme == "light" ]]; then
    fzf_colors="bg+:$LIGHT_SURFACE0,bg:$LIGHT_BASE,spinner:$LIGHT_ROSEWATER,hl:$LIGHT_RED,fg:$LIGHT_TEXT,header:$LIGHT_RED,info:$LIGHT_MAUVE,pointer:$LIGHT_ROSEWATER,marker:$LIGHT_LAVENDER,fg+:$LIGHT_TEXT,prompt:$LIGHT_MAUVE,hl+:$LIGHT_RED,selected-bg:$LIGHT_SURFACE1,border:$LIGHT_OVERLAY0,label:$LIGHT_TEXT"
  else
    fzf_colors="bg+:$DARK_SURFACE0,bg:$DARK_BASE,spinner:$DARK_ROSEWATER,hl:$DARK_RED,fg:$DARK_TEXT,header:$DARK_RED,info:$DARK_MAUVE,pointer:$DARK_ROSEWATER,marker:$DARK_LAVENDER,fg+:$DARK_TEXT,prompt:$DARK_MAUVE,hl+:$DARK_RED,selected-bg:$DARK_SURFACE1,border:$DARK_OVERLAY0,label:$DARK_TEXT"
  fi

  fish -c "set -U fzf_theme_colors '--color=$fzf_colors'; true" 2>/dev/null || true
  fish -c "
    set -l base_opts (string replace -r -- '--color=[^ ]+\$' '' \$FZF_DEFAULT_OPTS; or true)
    set -U FZF_DEFAULT_OPTS \$base_opts '--color=$fzf_colors'
    true
  " 2>/dev/null || true

  if [[ ${THEME_APPLY_PLATFORM:-linux} == "linux" ]]; then
    systemctl --user set-environment FZF_DEFAULT_OPTS_THEME="--color=$fzf_colors" 2>/dev/null || true
    hyprctl keyword env FZF_DEFAULT_OPTS_THEME,"--color=$fzf_colors" >/dev/null 2>&1 || true
  fi
}
```

- [ ] **Step 5: Add platform-aware `update_tmux`**

The only change from the original (702–756) is the non-`$TMUX` socket fallback: on macOS the lazytmux server socket is under `$TMPDIR`/`/tmp`, not `/run/user/...`. Discover the socket via `tmux start-server`'s default by trying both, falling back to letting `tmux` use its own default. Append:

```bash
# Update tmux catppuccin flavor. Socket discovery is platform-aware:
# Linux uses /run/user/<uid>/tmux-<uid>/default; macOS uses tmux's default
# /tmp (or $TMUX when inside a session).
update_tmux() {
  local theme="$1"
  local tmux_flavor
  log_debug "Updating tmux to $theme"

  if [[ $theme == "light" ]]; then
    tmux_flavor="latte"
  else
    tmux_flavor="mocha"
  fi

  local tmux_cmd="tmux"
  if [[ -n ${TMUX:-} ]]; then
    tmux_cmd="tmux"
  elif [[ -S "/run/user/$(id -u)/tmux-$(id -u)/default" ]]; then
    tmux_cmd="tmux -S /run/user/$(id -u)/tmux-$(id -u)/default"
  fi
  # macOS: no /run/user socket; bare `tmux` uses its default socket dir
  # ($TMUX_TMPDIR or /tmp), which is where the lazytmux server listens.

  if ! $tmux_cmd list-sessions &>/dev/null 2>&1; then
    log_debug "tmux not running, skipping"
    return 0
  fi

  local var
  for var in $($tmux_cmd show-options -g 2>/dev/null | awk '$1 ~ /^@thm_/ {print $1}' | sort -u); do
    $tmux_cmd set -gu "$var" 2>/dev/null || true
  done

  $tmux_cmd set -g @catppuccin_flavor "$tmux_flavor" 2>/dev/null || {
    record_failure "tmux"
    return 1
  }

  $tmux_cmd source-file ~/.config/tmux/tmux.conf 2>/dev/null || true

  local thm_mauve thm_green thm_bg thm_overlay_1
  thm_mauve=$($tmux_cmd show-options -gv @thm_mauve 2>/dev/null | tr -d '"')
  thm_green=$($tmux_cmd show-options -gv @thm_green 2>/dev/null | tr -d '"')
  thm_bg=$($tmux_cmd show-options -gv @thm_bg 2>/dev/null | tr -d '"')
  thm_overlay_1=$($tmux_cmd show-options -gv @thm_overlay_1 2>/dev/null | tr -d '"')

  if [[ -n $thm_mauve && -n $thm_green && -n $thm_bg && -n $thm_overlay_1 ]]; then
    $tmux_cmd setw -g pane-border-format \
      "#{?#{&&:#{pane_active},#{&&:#{>:#{window_panes},1},#{==:#{window_zoomed_flag},0}}},#[fg=${thm_mauve}]━━ #[fg=${thm_green}]●#[fg=${thm_mauve}] ━━,#[bg=${thm_bg},fg=${thm_overlay_1}]━━━━━}"
  fi
}
```

- [ ] **Step 6: Create `home/theme/palette-env.nix`**

This exposes the palette→env-var export block (currently inlined in `theme-toggle.nix` lines 64–139) and the external theme fetches as reusable values. Move those fetches + the `export ...` text here verbatim.

```nix
# Reusable palette → shell-env-var injection, shared by the Linux theme-toggle
# wrapper and the macOS theme-apply-macos driver. Pure data — no platform deps.
{
  pkgs,
  config,
  lib,
}: let
  inherit (config.theme.palette) dark light;
  stripHash = color: lib.removePrefix "#" color;

  catppuccin-lazygit = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "lazygit";
    rev = "v2.0.0";
    sha256 = "sha256-gM0HplHhcpvtpmIVdlX/p59h0v+ihKEidS1imqPYlBg=";
  };
  catppuccin-yazi = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "yazi";
    rev = "fc69d6472d29b823c4980d23186c9c120a0ad32c";
    sha256 = "sha256-Og33IGS9pTim6LEH33CO102wpGnPomiperFbqfgrJjw=";
  };
in {
  # Core runtime tools every platform's updaters need.
  coreRuntimeInputs = with pkgs; [
    coreutils
    gnugrep
    gnused
    gawk
    findutils
    jq
    kitty
    tmux
    fish
  ];

  # Shell snippet exporting palette colors + theme paths. Prepend to the script
  # text before sourcing theme-apply.sh.
  exports = ''
    export LAZYGIT_THEMES_PATH="${catppuccin-lazygit}/themes"
    export YAZI_THEMES_PATH="${catppuccin-yazi}/themes"
    export XDG_CONFIG_HOME="${config.xdg.configHome}"
    export DARK_THEME_NAME="${dark.name}"
    export LIGHT_THEME_NAME="${light.name}"

    # Dark palette
    export DARK_BASE="${dark.base}"
    export DARK_MANTLE="${dark.mantle}"
    export DARK_CRUST="${dark.crust}"
    export DARK_TEXT="${dark.text}"
    export DARK_SUBTEXT0="${dark.subtext0}"
    export DARK_SUBTEXT1="${dark.subtext1}"
    export DARK_SURFACE0="${dark.surface0}"
    export DARK_SURFACE1="${dark.surface1}"
    export DARK_SURFACE2="${dark.surface2}"
    export DARK_OVERLAY0="${dark.overlay0}"
    export DARK_OVERLAY1="${dark.overlay1}"
    export DARK_OVERLAY2="${dark.overlay2}"
    export DARK_BLUE="${dark.blue}"
    export DARK_LAVENDER="${dark.lavender}"
    export DARK_SAPPHIRE="${dark.sapphire}"
    export DARK_SKY="${dark.sky}"
    export DARK_TEAL="${dark.teal}"
    export DARK_GREEN="${dark.green}"
    export DARK_YELLOW="${dark.yellow}"
    export DARK_PEACH="${dark.peach}"
    export DARK_MAROON="${dark.maroon}"
    export DARK_RED="${dark.red}"
    export DARK_MAUVE="${dark.mauve}"
    export DARK_PINK="${dark.pink}"
    export DARK_FLAMINGO="${dark.flamingo}"
    export DARK_ROSEWATER="${dark.rosewater}"

    # Light palette
    export LIGHT_BASE="${light.base}"
    export LIGHT_MANTLE="${light.mantle}"
    export LIGHT_CRUST="${light.crust}"
    export LIGHT_TEXT="${light.text}"
    export LIGHT_SUBTEXT0="${light.subtext0}"
    export LIGHT_SUBTEXT1="${light.subtext1}"
    export LIGHT_SURFACE0="${light.surface0}"
    export LIGHT_SURFACE1="${light.surface1}"
    export LIGHT_SURFACE2="${light.surface2}"
    export LIGHT_OVERLAY0="${light.overlay0}"
    export LIGHT_OVERLAY1="${light.overlay1}"
    export LIGHT_OVERLAY2="${light.overlay2}"
    export LIGHT_BLUE="${light.blue}"
    export LIGHT_LAVENDER="${light.lavender}"
    export LIGHT_SAPPHIRE="${light.sapphire}"
    export LIGHT_SKY="${light.sky}"
    export LIGHT_TEAL="${light.teal}"
    export LIGHT_GREEN="${light.green}"
    export LIGHT_YELLOW="${light.yellow}"
    export LIGHT_PEACH="${light.peach}"
    export LIGHT_MAROON="${light.maroon}"
    export LIGHT_RED="${light.red}"
    export LIGHT_MAUVE="${light.mauve}"
    export LIGHT_PINK="${light.pink}"
    export LIGHT_FLAMINGO="${light.flamingo}"
    export LIGHT_ROSEWATER="${light.rosewater}"

    # Without # prefix (rgba usage)
    export DARK_BLUE_RAW="${stripHash dark.blue}"
    export DARK_LAVENDER_RAW="${stripHash dark.lavender}"
    export LIGHT_BLUE_RAW="${stripHash light.blue}"
    export LIGHT_LAVENDER_RAW="${stripHash light.lavender}"
  '';

  libScript = ./lib/theme-apply.sh;
}
```

- [ ] **Step 7: Run shellcheck on the shared lib**

Run: `shellcheck -x home/theme/lib/theme-apply.sh`
Expected: no errors. (Use `# shellcheck shell=bash` at the top if shellcheck can't infer the shell, and `# shellcheck disable=...` only if a warning is a known false-positive from the sourced-context design — document why.)

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(theme): extract shared theme-apply lib + palette-env (#24)"
```

---

## Task 3: Rewire the Linux wrapper to consume the shared module (Linux behavior unchanged)

**Files:**
- Modify: `home/desktop/hyprland/scripts/theme-toggle.nix`
- Modify: `home/desktop/hyprland/scripts/sh/theme-toggle.sh`

- [ ] **Step 1: Remove the extracted functions from `theme-toggle.sh`**

Delete from `theme-toggle.sh` the functions and blocks now living in the shared lib (copied there in Task 2): the state-config block (27–42, incl. the `MOCHA_*`/`LATTE_*` border vars — they stay available via the sourced lib for the Linux-only `update_hyprland_borders`), the logging/state helpers (44–145), and the function bodies of `update_kitty`, `update_fish`, `update_starship`, `update_lazygit`, `update_btop`, `update_lazydocker`, `update_process_compose`, `update_delta`, `update_yazi`, `update_bat`, `update_fzf`, `update_tmux`. **Keep** the Linux-only updaters, `restart_service`, `signal_apps`, `_run_updates_parallel`, `apply_theme*`, `toggle_theme`, `restore_theme`, `sync_theme`, `show_status`, `query_theme`, and the `case` dispatch.

At the very top of `theme-toggle.sh` (after `set -euo pipefail`), source the shared lib (the wrapper injects `THEME_APPLY_LIB`):

```bash
set -euo pipefail
export THEME_APPLY_PLATFORM=linux
# shellcheck source=/dev/null
source "$THEME_APPLY_LIB"
```

`_run_updates_parallel` (which calls `signal_apps`) stays in the Linux script and keeps driving the full Linux updater list — unchanged.

- [ ] **Step 2: Rewire `theme-toggle.nix` to use palette-env + shared lib**

Replace the inlined palette exports and fetches (lines 7–41, 64–141) with an import of `palette-env.nix`. Keep the Linux-only `runtimeInputs` and notify-icon logic. Key changes:

```nix
{
  pkgs,
  config,
  lib,
  ...
}: let
  paletteEnv = import ../../../theme/palette-env.nix {inherit pkgs config lib;};

  notifyIconLight = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Light/48x48/status/weather-clear.svg";
  notifyIconDark = "${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark/48x48/status/weather-clear-night.svg";

  theme-toggle = pkgs.writeShellApplication {
    name = "theme-toggle";
    runtimeInputs =
      paletteEnv.coreRuntimeInputs
      ++ (with pkgs; [
        dconf
        libnotify
        hyprland
        procps
        networkmanagerapplet
        libsForQt5.qtstyleplugin-kvantum
        quickshell
      ]);
    text = ''
      ${paletteEnv.exports}
      export NOTIFY_ICON_LIGHT="${notifyIconLight}"
      export NOTIFY_ICON_DARK="${notifyIconDark}"
      export THEME_APPLY_LIB="${paletteEnv.libScript}"

      ${builtins.readFile ./sh/theme-toggle.sh}
    '';
  };
in {
  config.home.packages = [theme-toggle];
  config.programs.theme-toggle.package = theme-toggle;
}
```

Note: the `options.programs.theme-toggle` block was already **removed** from this file in Task 1 Step 4b (the option now lives in `home/theme/default.nix`); this file only *sets* the value. This task replaces the *inlined palette exports/fetches* with the `palette-env.nix` import and splits `runtimeInputs` — keep the `config.programs.theme-toggle.package = theme-toggle;` assignment from Task 1.

- [ ] **Step 3: Eval the Linux config**

Run:
```bash
nix eval .#nixosConfigurations.thinkpad-p14s-g6.config.system.build.toplevel.drvPath
```
Expected: a `.drv` path, no errors about missing functions/options.

- [ ] **Step 4: Build + switch on a Linux host (ThinkPad)**

Run (on a ThinkPad): `nh home switch`
Expected: builds and activates; `restoreTheme` activation runs `theme-toggle restore` without error.

- [ ] **Step 5: Behavioral regression check on Linux**

Run: toggle the theme (the normal keybind, or `theme-toggle apply light` then `theme-toggle apply dark`).
Expected: kitty, fish, starship, btop, tmux, lazygit, lazydocker, yazi, bat, fzf, delta, process-compose all switch exactly as before. Confirm GTK/Hyprland/noctalia still switch too (orchestration untouched). No `theme-toggle` errors in `journalctl --user -e` for the portal/vicinae restarts.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(theme): Linux wrapper sources shared lib (#24)"
```

---

## Task 4: macOS driver script + activation (`home/darwin/theme/`)

**Files:**
- Create: `home/darwin/theme/default.nix`
- Modify: `home/darwin/default.nix:6-10`

- [ ] **Step 1: Create `home/darwin/theme/default.nix`**

```nix
{
  pkgs,
  config,
  lib,
  ...
}: let
  paletteEnv = import ../../theme/palette-env.nix {inherit pkgs config lib;};

  theme-apply-macos = pkgs.writeShellApplication {
    name = "theme-apply-macos";
    runtimeInputs = paletteEnv.coreRuntimeInputs;
    text = ''
      ${paletteEnv.exports}
      export THEME_APPLY_PLATFORM=macos
      # shellcheck source=/dev/null
      source "${paletteEnv.libScript}"

      # Resolve macOS appearance. AppleInterfaceStyle is "Dark" in dark mode and
      # absent (read exits non-zero) in light mode.
      if defaults read -g AppleInterfaceStyle >/dev/null 2>&1; then
        theme=dark
      else
        theme=light
      fi

      # Debounce: skip if already applied (the watched plist changes for many
      # unrelated reasons).
      state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}"
      mkdir -p "$state_dir"
      last_file="$state_dir/theme-apply-macos.last"
      if [[ -f "$last_file" && "$(cat "$last_file")" == "$theme" ]]; then
        exit 0
      fi

      _run_updates_neutral "$theme" \
        update_kitty update_fish update_starship update_btop update_tmux \
        update_lazydocker update_process_compose update_bat update_delta \
        update_fzf update_yazi update_lazygit

      printf '%s' "$theme" > "$last_file"
    '';
  };
in
  lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    programs.theme-toggle.package = theme-apply-macos;
    home.packages = [theme-apply-macos];

    # The updaters rm -f and replace HM symlinks (kitty.conf, yazi/theme.toml,
    # lazygit/config.yml, starship.toml, btop.conf, lazydocker/config.yml). On
    # the next `darwin switch` HM's link check would fail with "file would be
    # clobbered" — so delete the mutated copies first (mirrors the Linux
    # cleanThemeFiles in home/desktop/theme/catppuccin.nix).
    home.activation.cleanThemeFilesMacos = lib.hm.dag.entryBefore ["checkLinkTargets"] ''
      for f in \
        "$HOME/.config/kitty/kitty.conf" \
        "$HOME/.config/btop/btop.conf" \
        "$HOME/.config/starship.toml" \
        "$HOME/.config/lazygit/config.yml" \
        "$HOME/.config/lazydocker/config.yml" \
        "$HOME/.config/yazi/theme.toml"
      do
        if [ -f "$f" ] && [ ! -L "$f" ]; then
          $VERBOSE_ECHO "Removing theme-managed file: $f"
          run rm -f "$f"
        fi
      done
    '';

    # Apply the correct theme after activation so a fresh switch lands themed.
    home.activation.applyThemeMacos = lib.hm.dag.entryAfter ["linkGeneration"] ''
      run ${theme-apply-macos}/bin/theme-apply-macos || true
    '';
  }
```

- [ ] **Step 2: Import the module from `home/darwin/default.nix`**

Add `./theme` to the `imports` list in `home/darwin/default.nix`:

```nix
  imports = [
    ./aerospace.nix
    ./karabiner.nix
    ./nh.nix
    ./theme
  ];
```

- [ ] **Step 3: Confirm the macOS driver derivation resolves**

Run:
```bash
nix eval --raw .#darwinConfigurations.mbp-m4-pro.config.home-manager.users.noams.programs.theme-toggle.package
```
Expected: a `/nix/store/...theme-apply-macos` path. `writeShellApplication` runs `shellcheck` on the script text at build time, so a syntax/quoting error in the `text` block fails the build here. (Full runtime check happens in Task 6.)

- [ ] **Step 4: Eval the Mac config**

Run:
```bash
nix eval .#darwinConfigurations.mbp-m4-pro.config.system.build.toplevel.drvPath
```
Expected: a `.drv` path, no `option ... does not exist` errors (confirms `programs.theme-toggle.package` is set on darwin and the activation blocks evaluate).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(theme): macOS theme-apply driver + activation (#24)"
```

---

## Task 5: launchd watch agent + remove the appearance pin

**Files:**
- Modify: `hosts/mbp-m4-pro/default.nix` (launchd block ~229; appearance pin line 281)

- [ ] **Step 1: Add the watch agent to `launchd.user.agents`**

The agent must reference the HM-built script. nix-darwin exposes the HM config at `config.home-manager.users.<user>`. Add inside the existing `launchd.user.agents = { ... }` block:

```nix
    # Follow macOS Light/Dark: the watched global-prefs plist is rewritten on
    # every appearance change, firing this agent. RunAtLoad themes apps at login.
    # The script self-debounces, so unrelated global-pref writes are cheap no-ops.
    theme-watch = {
      serviceConfig = {
        ProgramArguments = [
          "${config.home-manager.users.${config.system.primaryUser}.programs.theme-toggle.package}/bin/theme-apply-macos"
        ];
        WatchPaths = ["${config.users.users.${config.system.primaryUser}.home}/Library/Preferences/.GlobalPreferences.plist"];
        RunAtLoad = true;
        StandardErrorPath = "/tmp/theme-watch.err.log";
        StandardOutPath = "/tmp/theme-watch.out.log";
      };
    };
```

(If `config.system.primaryUser` is not in scope at this point, hardcode the username `noams` consistent with the rest of the host file — check how the host already references the user and match it.)

- [ ] **Step 2: Remove the `AppleInterfaceStyle` pin**

In `hosts/mbp-m4-pro/default.nix`, delete the line `AppleInterfaceStyle = "Dark";` (line ~281) from `system.defaults.NSGlobalDomain`. This stops every `darwin switch` from forcing Dark and lets macOS persist the user's choice.

- [ ] **Step 3: Eval the Mac config**

Run:
```bash
nix eval .#darwinConfigurations.mbp-m4-pro.config.launchd.user.agents.theme-watch.serviceConfig.ProgramArguments
```
Expected: a single-element list with the `theme-apply-macos` store path. No infinite-recursion or missing-attr errors.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(theme): launchd appearance watcher, drop Dark pin (#24)"
```

---

## Task 6: Build on the Mac + verify core terminal apps follow appearance

**Files:** none (verification only). Run on `mbp-m4-pro`.

- [ ] **Step 1: Build + switch**

Run: `nh darwin switch`
Expected: builds and activates. `applyThemeMacos` runs once at the end with no fatal error. The `theme-watch` LaunchAgent is loaded (`launchctl list | grep theme-watch` shows it).

- [ ] **Step 2: Confirm the watcher is registered**

Run: `launchctl list | grep theme-watch`
Expected: a line for the agent (PID may be `-`; it runs on demand).

- [ ] **Step 3: Verify kitty socket glob matches (the spec's flagged unknown)**

With a kitty window open, run: `ls /tmp/kitty-*`
Expected: at least one socket path. If empty, kitty's `listen_on = unix:/tmp/kitty` produced `/tmp/kitty` (no PID suffix) — in that case update `update_kitty`'s glob to also match the literal socket. Confirm `kitty @ --to unix:<sock> set-colors --help` succeeds against a found socket.

- [ ] **Step 4: Flip to Light and observe**

Run: `osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false'`
Expected within ~1s: kitty recolors live to Catppuccin Latte; a new fish prompt shows the Latte starship palette; `btop`, `tmux` status, lazygit reflect light on next launch/already-running where live. Check `/tmp/theme-watch.err.log` is empty of fatal errors.

- [ ] **Step 5: Flip back to Dark and observe**

Run: `osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'`
Expected: apps return to Mocha.

- [ ] **Step 6: Verify no clobber on a second switch**

Run: `nh darwin switch` again (after a flip).
Expected: succeeds — no "file would be clobbered" error (confirms `cleanThemeFilesMacos`).

- [ ] **Step 7: Verify login behavior**

Run: `launchctl kickstart -k gui/$(id -u)/<theme-watch-label>` (or log out/in).
Expected: theme re-applies to match current appearance (confirms `RunAtLoad`).

- [ ] **Step 8: Commit any kitty-glob fix from Step 3**

```bash
git add -A
git commit -m "fix(theme): match macOS kitty socket glob (#24)"
```

(Skip if Step 3 needed no change.)

---

## Task 7: Verify remaining apps + resolve the bat asset gap

**Files:** possibly `home/terminal/` (bat theme wiring) — TBD by audit.

- [ ] **Step 1: Verify the file-rewriting apps followed**

After a Light flip, inspect: `~/.config/lazydocker/config.yml`, `~/.config/process-compose/theme.yaml`, `~/.config/yazi/theme.toml`, `~/.config/lazygit/config.yml`, `~/.config/git/theme-override`.
Expected: each contains Latte values. Launch each app and confirm visually.

- [ ] **Step 2: Audit bat on macOS**

Run: `bat --list-themes | grep -i catppuccin`
Expected: ideally lists `Catppuccin Mocha` / `Catppuccin Latte`. **If absent**, bat has no Catppuccin themes on the Mac, so `set -U BAT_THEME "Catppuccin Mocha"` falls back to a default. Decide and record:
  - **(a)** wire Catppuccin `.tmTheme` files cross-platform into bat's themes dir + a `bat cache --build` activation, or
  - **(b)** drop bat from Mac scope (document it), or
  - **(c)** point `BAT_THEME` at a built-in bat light/dark theme (e.g. `ansi`/`GitHub` vs `TwoDark`) as a pragmatic substitute.
If wiring is chosen, implement it here and re-verify `bat --list-themes`.

- [ ] **Step 3: Verify fzf + bat propagate in a fresh fish shell**

Open a new terminal, run `echo $BAT_THEME` and `echo $fzf_theme_colors` in fish after a flip.
Expected: both reflect the current appearance (fish-universal propagation). Confirm `fzf` preview colors and `bat` output match.

- [ ] **Step 4: Commit any bat wiring**

```bash
git add -A
git commit -m "feat(theme): wire bat Catppuccin themes on macOS (#24)"
```

(Adjust message to match the chosen bat resolution; skip if dropped from scope with only a doc note.)

---

## Task 8: Final cross-platform regression + PR

- [ ] **Step 1: Re-verify Linux is untouched**

On a ThinkPad: `nh home switch` then toggle dark↔light once.
Expected: identical behavior to before this branch (all apps switch; GTK/Hyprland/noctalia included).

- [ ] **Step 2: Update the spec status**

In `docs/superpowers/specs/2026-06-22-macos-theme-follow-design.md`, change the Status line to `Implemented`. Note the bat resolution chosen in Task 7.

- [ ] **Step 3: Commit + open the PR**

```bash
git add -A
git commit -m "docs(theme): mark macOS theme-follow implemented (#24)"
git push -u origin feat/24-macos-theme-follow
gh pr create --assignee @me --title "feat: follow macOS appearance for light/dark theme (#24)" --body "Closes #24. Cross-platform theme module + macOS appearance watcher. See docs/superpowers/specs/2026-06-22-macos-theme-follow-design.md."
```

Expected: PR created. CI (if any) green.

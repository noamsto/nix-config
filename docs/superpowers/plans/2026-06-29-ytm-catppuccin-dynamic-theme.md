# YTM Catppuccin Dynamic Theme — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Theme `pear-desktop` (YouTube Music) with Catppuccin so it tracks the system dark/light toggle (Mocha↔Latte) with no restart, on Linux (Hyprland) and macOS.

**Architecture:** Build one auto-switching `catppuccin-auto.css` (upstream `mocha.css` wrapped in `@media (prefers-color-scheme: dark)`, `latte.css` in light) as an inline `pkgs.runCommand` derivation inside a new Home Manager module. A `home.activation` script `jq`-merges the CSS store path into YTM's `options.themes`. The existing dconf `color-scheme` write that `theme-toggle.sh` already performs flows through the XDG desktop portal to Electron's `prefers-color-scheme`, re-theming YTM live. macOS follows system appearance via the same `prefers-color-scheme` mechanism, independent of `theme-toggle`.

**Tech Stack:** Nix / Home Manager (flake-parts, hybrid HM), `pkgs.fetchFromGitHub` + `pkgs.runCommand`, `jq`, bash activation, the existing `theme-toggle.sh` / Noctalia / xdg-desktop-portal chain.

## Global Constraints

- **Upstream pin (verbatim):** `catppuccin/youtubemusic`, `rev = "dc35fc46232e389ff761adec8242f956af405880"`, `hash = "sha256-K5iwNBA/6/JDmmt/u9Dnsk0lvWY12YpY+BIScrRaDGw=";`. Pin to the commit SHA, never a branch — repo gotcha.
- **Accent:** mauve. Upstream already sets `--ctp-accent: var(--ctp-mauve);` in both `mocha.css` and `latte.css` — **no accent patch needed**.
- **Both flavor files have no `@charset`/`@import`** (verified), so wrapping each whole file in `@media` is valid.
- **Cross-platform:** must build on `x86_64-linux` and `aarch64-darwin`. Hence the derivation is inline in the module (the `packages/` outputs are Linux-only) — do not add it to `packages/default.nix`.
- **Install guard:** the module gates on `osConfig.desktop.mode != "none" || pkgs.stdenv.hostPlatform.isDarwin` — exactly where `pear-desktop` is installed (Linux `desktop-packages`; macOS `home/darwin`).
- **No `theme-toggle.sh` edit** on the primary (auto) path. Only Task 5 (fallback) touches it, and only if Task 1 fails.
- **YTM config paths:** Linux `~/.config/YouTube Music/config.json`; macOS `~/Library/Application Support/YouTube Music/config.json` (note the spaces — quote carefully).
- **Rebuild:** `nh home switch` on Linux. New/untracked `.nix` files are invisible to the flake until `git add`ed — `git add` before any `nix build`/`nh` (nix-rebuild skill gotcha).
- **Pre-commit:** first commit touching `.nix` will fail because alejandra/prettier reformat; re-`git add` the reformatted files and re-run the same commit. Use `gtrash put`, never `rm`, for deletions.

---

### Task 1: Verification gate — does Electron honor the portal color-scheme live?

Decision point. **No code committed.** Determines whether the auto path (Tasks 2–4) is viable on Linux or we use the fallback (Task 5). macOS is unaffected either way (it follows OS appearance natively).

**Files:**
- Temp only: `/tmp/claude-*/scratchpad/ytm-sentinel.css` (sentinel CSS; not committed)
- Touch (runtime, restored after): `~/.config/YouTube Music/config.json`

- [ ] **Step 1: Back up the live YTM config**

```bash
cp "$HOME/.config/YouTube Music/config.json" "$HOME/.config/YouTube Music/config.json.bak"
```

- [ ] **Step 2: Write a sentinel CSS with obvious per-scheme colors**

Write to `<scratchpad>/ytm-sentinel.css`:

```css
@media (prefers-color-scheme: dark)  { ytmusic-app, body { background: #ff0000 !important; } }
@media (prefers-color-scheme: light) { ytmusic-app, body { background: #00ff00 !important; } }
```

- [ ] **Step 3: Point YTM at the sentinel and restart the app**

```bash
tmp="$(mktemp)"
jq --arg p "<scratchpad>/ytm-sentinel.css" '.options.themes = [$p]' "$HOME/.config/YouTube Music/config.json" > "$tmp" && mv "$tmp" "$HOME/.config/YouTube Music/config.json"
pkill -f pear-desktop; sleep 1; pear-desktop &
```

- [ ] **Step 4: Force dark, confirm RED**

Run: `theme-toggle apply dark`
Expected: YTM background turns **red** (dark scheme block applied).

- [ ] **Step 5: Toggle to light WITHOUT restarting, observe**

Run: `theme-toggle toggle`  (or `theme-toggle apply light`)
Expected (PASS): YTM background flips to **green** live, no restart.
If it stays red / does not change without an app restart: **FAIL** → use Task 5 fallback instead of Tasks 2–4's runtime assumption (still build the theme in Tasks 2–3; Task 4 becomes the fallback driver).

- [ ] **Step 6: Restore the live config**

```bash
mv "$HOME/.config/YouTube Music/config.json.bak" "$HOME/.config/YouTube Music/config.json"
pkill -f pear-desktop || true
```

- [ ] **Step 7: Record the verdict in the PR/issue thread**

Note PASS (auto) or FAIL (fallback) on issue #50 so the executor of later tasks knows which runtime path is live.

---

### Task 2: Theme module with inline combined-CSS derivation

**Files:**
- Create: `home/desktop/youtube-music/default.nix`

**Interfaces:**
- Produces: a Home Manager module (function taking `{ pkgs, lib, config, osConfig, ... }`) that, when imported, defines `home.activation.youtubeMusicCatppuccin`. Consumed by Task 3's import in `home/noams.nix`.
- Internal: `ytmCatppuccinTheme` — a derivation whose store path **is** the `catppuccin-auto.css` file (referenced as `"${ytmCatppuccinTheme}"`).

- [ ] **Step 1: Write the module**

Create `home/desktop/youtube-music/default.nix`:

```nix
{
  pkgs,
  lib,
  config,
  osConfig,
  ...
}: let
  # Pin to a commit SHA, never a branch (repo gotcha). Both flavor files default
  # --ctp-accent to mauve, so no accent patch is needed.
  ytmSrc = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "youtubemusic";
    rev = "dc35fc46232e389ff761adec8242f956af405880";
    hash = "sha256-K5iwNBA/6/JDmmt/u9Dnsk0lvWY12YpY+BIScrRaDGw=";
  };

  # One file that auto-switches via prefers-color-scheme: Mocha when the system
  # (portal/OS) reports dark, Latte when light. Wrapping each whole flavor file
  # in @media is valid here — neither file has @charset/@import.
  ytmCatppuccinTheme = pkgs.runCommand "catppuccin-auto.css" {} ''
    {
      echo '@media (prefers-color-scheme: dark) {'
      cat ${ytmSrc}/src/mocha.css
      echo '}'
      echo '@media (prefers-color-scheme: light) {'
      cat ${ytmSrc}/src/latte.css
      echo '}'
    } > "$out"
  '';

  # YTM (Electron) stores user data under ~/Library/Application Support on macOS
  # and ~/.config on Linux. config.json holds options.themes = [ <css paths> ].
  configFile =
    if pkgs.stdenv.hostPlatform.isDarwin
    then "${config.home.homeDirectory}/Library/Application Support/YouTube Music/config.json"
    else "${config.home.homeDirectory}/.config/YouTube Music/config.json";

  # pear-desktop is installed on Linux desktops (desktop-packages) and on macOS
  # (home/darwin). Match that exactly so a headless Linux host gets nothing.
  ytmInstalled = osConfig.desktop.mode != "none" || pkgs.stdenv.hostPlatform.isDarwin;
in {
  # Idempotently register the theme path in YTM's config.json, preserving every
  # app-mutated key (window position, plugins, …). restartOnConfigChanges is
  # false upstream, so this never triggers a spurious restart.
  home.activation.youtubeMusicCatppuccin = lib.mkIf ytmInstalled (
    lib.hm.dag.entryAfter ["writeBoundary"] ''
      cfg=${lib.escapeShellArg configFile}
      themePath=${lib.escapeShellArg "${ytmCatppuccinTheme}"}
      $DRY_RUN_CMD mkdir -p "$(dirname "$cfg")"
      if [ -f "$cfg" ]; then
        tmp="$($DRY_RUN_CMD mktemp)"
        $DRY_RUN_CMD ${pkgs.jq}/bin/jq --arg p "$themePath" '.options.themes = [$p]' "$cfg" > "$tmp" \
          && $DRY_RUN_CMD mv "$tmp" "$cfg"
      else
        $DRY_RUN_CMD ${pkgs.jq}/bin/jq -n --arg p "$themePath" '{options: {themes: [$p]}}' > "$cfg"
      fi
    ''
  );
}
```

- [ ] **Step 2: Stage the new file so the flake can see it**

```bash
git -C ~/nix-config-worktrees/feat-50-ytm-catppuccin-theme add home/desktop/youtube-music/default.nix
```

- [ ] **Step 3: Syntax-check the module (full build happens in Task 3's `nh home switch`)**

Run from the worktree root:
```bash
nix-instantiate --parse home/desktop/youtube-music/default.nix > /dev/null && echo OK
```
Expected: `OK` (parses). The derivation itself (fetch + runCommand) is built and the pinned hash verified when Task 3 runs `nh home switch`; a hash mismatch there means the `hash =` value drifted — re-scaffold with `nurl https://github.com/catppuccin/youtubemusic dc35fc46232e389ff761adec8242f956af405880`.

- [ ] **Step 4: Commit**

```bash
git -C ~/nix-config-worktrees/feat-50-ytm-catppuccin-theme add home/desktop/youtube-music/default.nix
git -C ~/nix-config-worktrees/feat-50-ytm-catppuccin-theme commit -m "feat(youtube-music): Catppuccin auto-switching theme module (#50)"
```
If pre-commit reformats: re-`git add` the file and re-run the same commit.

---

### Task 3: Wire the import and apply on Linux

**Files:**
- Modify: `home/noams.nix` (the unconditional imports block, next to `./desktop/theme/palette.nix`)

**Interfaces:**
- Consumes: the module from Task 2 (`home/desktop/youtube-music`).

- [ ] **Step 1: Read the current import block**

Run: `sed -n '8,32p' home/noams.nix` — confirm `./desktop/theme/palette.nix` is imported unconditionally with the "available on darwin too" comment, and that `./desktop` is in the `desktop.mode != "none"` list.

- [ ] **Step 2: Add the import unconditionally (so macOS gets it too)**

In `home/noams.nix`, in the same unconditional list that contains `./desktop/theme/palette.nix`, add:

```nix
      ./desktop/youtube-music
```

(Place it right after the `./desktop/theme/palette.nix` line. Do NOT add it to the `desktop.mode != "none"` list — the module self-guards.)

- [ ] **Step 3: Stage and rebuild**

```bash
git -C ~/nix-config-worktrees/feat-50-ytm-catppuccin-theme add home/noams.nix home/desktop/youtube-music/default.nix
nh home switch
```
Expected: build succeeds; activation runs `youtubeMusicCatppuccin` with no error.

- [ ] **Step 4: Confirm the theme path landed in config.json**

```bash
jq '.options.themes' "$HOME/.config/YouTube Music/config.json"
```
Expected: a one-element array pointing at a `…-catppuccin-auto.css` store path. Confirm the file exists and begins with `@media (prefers-color-scheme: dark) {`:
```bash
head -1 "$(jq -r '.options.themes[0]' "$HOME/.config/YouTube Music/config.json")"
```

- [ ] **Step 5: Commit**

```bash
git -C ~/nix-config-worktrees/feat-50-ytm-catppuccin-theme commit -m "feat(youtube-music): import Catppuccin theme module unconditionally (#50)"
```
(Re-`git add` + re-commit if pre-commit reformats `home/noams.nix`.)

---

### Task 4: End-to-end live verification (auto path)

**Files:** none (runtime verification + screenshots).

- [ ] **Step 1: Restart YTM to pick up the new themes array**

```bash
pkill -f pear-desktop || true; sleep 1; pear-desktop &
```
(First launch after a `themes` change needs one restart; thereafter switching is live.)

- [ ] **Step 2: Set dark, confirm Mocha**

Run: `theme-toggle apply dark`
Expected: YTM renders in Catppuccin **Mocha** (dark base `#1e1e2e`, mauve accents).

- [ ] **Step 3: Toggle to light, confirm live switch to Latte (no restart)**

Run: `theme-toggle toggle`
Expected: YTM flips to Catppuccin **Latte** live, music uninterrupted. Toggle back to dark and confirm it returns to Mocha.

- [ ] **Step 4: Capture before/after screenshots for the PR**

Use `grim`/the usual screenshot path; attach to issue #50.

- [ ] **Step 5: If Task 1 was PASS, the feature is done — proceed to PR.**

If Task 1 was FAIL, skip Step 2–3's "live" expectation and implement Task 5, then re-verify that toggling re-themes YTM (with a restart).

---

### Task 5: FALLBACK — explicit swap+restart via theme-toggle.sh (only if Task 1 failed)

Only implement if Task 1 showed Electron does **not** honor the portal live on Linux. The theme derivation/module (Tasks 2–3) stays; this just drives it explicitly. macOS still works via Task 2–3 alone.

**Files:**
- Modify: `home/desktop/hyprland/scripts/sh/theme-toggle.sh` — add `update_youtube_music`, register it in both `apply_theme` and `apply_theme_from_noctalia` fan-out lists, and add a `youtube-music)` arm to the `sync_theme` retry `case`.

**Interfaces:**
- Consumes: the `ytmCatppuccinTheme` store path is already in `config.json` (Task 3). Since the auto-CSS contains both flavors gated by `@media`, the only lever left is restarting the app so Electron re-reads `prefers-color-scheme` at startup — Chromium reads the portal value on launch even when it ignores live `SettingChanged`.

- [ ] **Step 1: Add the update function**

After an existing `update_*` function (match the file's style — `local theme="$1"`, `log_debug`, `record_failure` on error), add:

```bash
# Restart YTM so Electron re-reads prefers-color-scheme at startup. The combined
# Catppuccin theme (installed via Home Manager) auto-selects Mocha/Latte from the
# system scheme; this Electron build does not pick up the portal change live, so a
# restart is the switch mechanism. No-op when YTM isn't running.
update_youtube_music() {
  local theme="$1"
  log_debug "Updating YouTube Music to $theme (restart)"
  pgrep -f pear-desktop >/dev/null 2>&1 || { log_debug "pear-desktop not running"; return 0; }
  pkill -f pear-desktop 2>/dev/null || true
  # Relaunch detached so it survives the toggle process exiting.
  setsid pear-desktop >/dev/null 2>&1 &
}
```

- [ ] **Step 2: Register in both fan-out lists**

In `apply_theme` and `apply_theme_from_noctalia`, append `update_youtube_music` to the `_run_updates_parallel "$theme" \` argument list (e.g. on the `update_process_compose update_vicinae update_kde_colorscheme` line).

- [ ] **Step 3: Add the retry arm**

In `sync_theme`'s `case "$component" in`, add:
```bash
    youtube-music) update_youtube_music "$current" ;;
```

- [ ] **Step 4: shellcheck the script (required for shell scripts)**

Run: `shellcheck home/desktop/hyprland/scripts/sh/theme-toggle.sh`
Expected: no new warnings/errors from the added function. Fix any before continuing.

- [ ] **Step 5: Stage, rebuild, verify toggle restarts + re-themes**

```bash
git -C ~/nix-config-worktrees/feat-50-ytm-catppuccin-theme add home/desktop/hyprland/scripts/sh/theme-toggle.sh
nh home switch
theme-toggle toggle
```
Expected: YTM restarts and comes back in the new flavor.

- [ ] **Step 6: Commit**

```bash
git -C ~/nix-config-worktrees/feat-50-ytm-catppuccin-theme commit -m "feat(youtube-music): drive theme switch via theme-toggle restart (#50)"
```

---

## Self-Review

- **Spec coverage:** combined CSS package (Task 2) ✓; mauve accent (upstream default, Task 2 constraint) ✓; module imported unconditionally for macOS (Task 3) ✓; jq activation preserving app keys (Task 2) ✓; no theme-toggle edit on auto path / fallback function defined (Task 5) ✓; verification gate first (Task 1) ✓; pinned commit SHA (Global Constraints) ✓; install guard matching pear-desktop presence (Task 2) ✓; Linux + macOS scope (Tasks 2–4) ✓.
- **Placeholders:** none — all code blocks concrete; the only `<scratchpad>` and `<worktree>`-style tokens are literal paths the executor substitutes from the environment.
- **Type/name consistency:** `ytmCatppuccinTheme`, `ytmSrc`, `configFile`, `ytmInstalled`, `home.activation.youtubeMusicCatppuccin`, `update_youtube_music` used consistently across Tasks 2/3/5.

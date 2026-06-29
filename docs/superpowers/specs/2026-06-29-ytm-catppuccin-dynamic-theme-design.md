# YTM (pear-desktop) Catppuccin dynamic theming — design

**Date:** 2026-06-29
**Status:** Approved design, pending spec review

## Goal

Theme the YouTube Music desktop app (`pear-desktop`, the `pear-devs/pear-desktop`
fork of `th-ch/youtube-music`) with Catppuccin so it tracks the system dark/light
toggle — Mocha when dark, Latte when light — to match the rest of the desktop the
`theme-toggle.sh` script drives. Accent: **mauve** (matches the global accent used
by yazi/fzf). Scope: **both Linux (Hyprland) and macOS (`mbp-m4-pro`)**.

## Key insight: the toggle already drives this for free

The switch needs **no `theme-toggle.sh` change and no app restart**. The chain:

1. `theme-toggle apply <dark|light>` → `update_gtk_theme` writes dconf
   `org.gnome.desktop.interface color-scheme = prefer-dark|prefer-light`.
2. `xdg-desktop-portal` exposes that as `org.freedesktop.appearance` `color-scheme`
   and emits a `SettingChanged` signal.
3. Chromium/Electron subscribes to the portal and flips the renderer's
   `prefers-color-scheme` live.
4. A single auto-switching CSS theme (`@media (prefers-color-scheme)`) re-paints YTM
   instantly — music keeps playing.

On macOS there is no `theme-toggle`; the same CSS follows the macOS system
appearance natively via the same `prefers-color-scheme` mechanism.

## Mechanism in the app

- YTM stores custom themes as a list of CSS file paths in
  `config.json` → `options.themes` (currently `[]`). The app injects each file's
  CSS into the renderer.
- `options.restartOnConfigChanges` is `false`, so registering a theme path will not
  fight the app or trigger spurious restarts.
- Config path is platform-specific:
  - Linux: `~/.config/YouTube Music/config.json`
  - macOS: `~/Library/Application Support/YouTube Music/config.json`

## Components

### 1. Combined theme CSS (Nix package)

A derivation under `packages/` (e.g. `ytm-catppuccin-theme`) that fetches
`catppuccin/youtubemusic` (MIT) **pinned to a full commit SHA** (per the repo's
"pin fetchers to a commit SHA, never a branch ref" gotcha — scaffold with `nurl`)
and emits one file, `catppuccin-auto.css`:

```css
@media (prefers-color-scheme: dark)  { /* contents of src/mocha.css verbatim */ }
@media (prefers-color-scheme: light) { /* contents of src/latte.css verbatim */ }
```

Wrapping each whole flavor file in a media query is the dumb-simple, guaranteed-
correct composition (CSS permits arbitrary rules inside `@media`); local-file bloat
is irrelevant. Set `--ctp-accent: var(--ctp-mauve)` in both flavor blocks.

### 2. Theme registration (Home Manager module)

A new module `home/desktop/youtube-music/default.nix`. **Import point matters:**
`home/desktop/default.nix` is gated on `desktop.mode != "none"`, and
`mbp-m4-pro` has `desktop.mode = "none"`, so importing from there would miss
macOS. Instead import it **unconditionally from `home/noams.nix`**, next to the
already-unconditional `./desktop/theme/palette.nix` (same rationale: "available on
darwin too"). The module gates its own platform-specific config path internally.
It does **only theming** — `pear-desktop` package installs stay where they are
(`home/packages.nix` for Linux, `home/darwin/default.nix` for macOS) to keep scope
tight.

The module runs a `home.activation` script that idempotently `jq`-merges the
CSS store path into the existing `config.json`:

- Resolve the platform config path (Linux vs macOS).
- If `config.json` exists: `jq` set `.options.themes = ["<store-path>"]`, writing
  atomically (temp file + move), preserving all app-mutated keys (window position,
  plugins, etc.). If it does not exist yet: create a minimal `{ "options": { "themes": [...] } }`.
- Idempotent: re-running (e.g. after a theme bump changes the store path) just
  overwrites `themes`.
- Guard: only act when `pear-desktop` is actually installed for the host (personal
  profile / package present), so it never creates a stray config on a host without
  the app.

Mirrors the existing patch-script + `home.activation` re-apply pattern already used
for vicinae.

### 3. Runtime

Nothing new runs on toggle. The existing dconf write propagates through the portal
to Electron automatically. After first install, one YTM restart is needed to pick up
the new `themes` array; thereafter dark/light switching is live.

## Primary risk + verification gate

The auto approach depends on this Electron build (Electron 41, Wayland) honoring the
XDG portal `color-scheme` **live**. **First step of implementation is to verify
this**, before building the package or module:

- With a theme installed (or a throwaway CSS using `prefers-color-scheme`), flip the
  toggle and confirm YTM's `prefers-color-scheme` changes — via DevTools
  `matchMedia('(prefers-color-scheme: dark)').matches` or a visible color change.

**Fallback if verification fails:** add an explicit `update_youtube_music` function
to the `theme-toggle.sh` fan-out (and the `sync`/retry `case`) that swaps the CSS
and restarts `pear-desktop`. Same CSS asset; driven explicitly instead of via the
portal. This interrupts playback on toggle, which is why it is the fallback, not the
default.

## Out of scope

- Theming YTM plugins' own UI beyond what the CSS reaches.
- A bespoke (non-Catppuccin) look.
- Consolidating `pear-desktop` package installs into the new module.

## Acceptance

- Toggling dark/light on a Hyprland host re-themes YTM Mocha↔Latte with no restart
  and no playback interruption.
- On `mbp-m4-pro`, YTM follows macOS system appearance with the same theme.
- Theme is installed declaratively (Nix package + activation); CSS source pinned to
  a commit SHA.
- Accent is mauve in both flavors.

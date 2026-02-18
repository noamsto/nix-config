# Standalone Tmux Flake Design

**Date:** 2026-02-18
**Goal:** Extract the tmux configuration into a standalone Nix flake that friends can use with `nix run github:noamsto/tmux-config`.

## Approach: Wrapped Tmux Binary

Use `makeWrapper` to create a tmux binary that always loads our config. No Home Manager required.

```
nix run github:noamsto/tmux-config    # Just works
nix profile install github:noamsto/tmux-config  # Permanent install
```

## Packages

1. **`tmux-wrapped`** (default) -- tmux with config, plugins, and helper scripts
2. **`wt`** -- git worktree tool with tmux integration (separate package)

## Scripts Included (8)

| Script | Purpose |
|---|---|
| `claude-status` | Status indicator for status bar and pickers |
| `claude-status-update` | CC hook integration (writes state to `/tmp/claude-status/`) |
| `tmux-reflow-windows` | Multi-line window layout with aligned columns |
| `tmux-session-picker` | `Prefix+s` session picker (wraps choose-tree) |
| `tmux-window-picker` | `Prefix+w` window picker (wraps choose-tree) |
| `tmux-branch-display` | Branch display in status bar |
| `tmux-dir-display` | Directory display in status bar |
| `tmux-set-pane-border` | Pane border theming |

**Not included:** tmux-sidebar, sesh-new, sesh-kill, sesh-list-grouped, sesh-icon, sesh-preview, sesh-extract-name.

## How the Wrapper Works

```nix
pkgs.symlinkJoin {
  name = "tmux-wrapped";
  paths = [ pkgs.tmux ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/tmux \
      --add-flags "-f ${tmuxConf}" \
      --prefix PATH : ${lib.makeBinPath scripts}
  '';
}
```

## Config Generation

The tmux.conf is generated from Nix, similar to how Home Manager does it but without the HM module system:

- Plugin loading: explicit `run-shell /nix/store/.../plugin.tmux` lines
- Theme variables, keybindings, hooks -- all embedded in the generated config
- No `osConfig` dependencies (current config has zero)

### Plugins

Same plugin set as current config:
- catppuccin/tmux (theme)
- tmux-nerd-font-window-name (icons)
- tmux-sensible (defaults)
- tmux-yank (clipboard)
- tmux-open (URL opening)
- vim-tmux-navigator (vim-style pane navigation)

## Claude Code Integration

The flake includes `claude-status` and `claude-status-update` scripts. For the status indicators to work, users must configure Claude Code hooks.

**Setup:** Documentation-only. README includes the JSON to paste into `~/.claude/settings.json`.

### Data Flow

```
CC hooks -> claude-status-update -> /tmp/claude-status/panes/<id>
tmux status bar -> claude-status (reads files) -> renders icons
```

## Repository Structure

```
github:noamsto/tmux-config/
  flake.nix             # flake-parts, packages + devShell
  config/
    tmux.conf.nix       # Generates tmux.conf from Nix
  scripts/
    claude-status.sh
    claude-status-update.sh
    tmux-reflow-windows.sh
    tmux-session-picker.sh
    tmux-window-picker.sh
    tmux-branch-display.sh
    tmux-dir-display.sh
    tmux-set-pane-border.sh
  wt/
    wt.sh               # Worktree tool
    default.nix          # wt package definition
  README.md             # Usage, CC hooks setup docs
```

## Design Decisions

- **Opinionated, no flags:** Take it or leave it. No `enable*` options.
- **CC integration default-on:** Scripts are in PATH; status bar references them. If CC isn't installed, `claude-status` outputs blank (graceful degradation).
- **wt separate:** Not everyone uses git worktrees. `nix run .#wt` for those who want it.
- **No sesh dependency:** Pickers use tmux's built-in `choose-tree`, not sesh.

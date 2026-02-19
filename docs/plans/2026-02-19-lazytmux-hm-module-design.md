# lazytmux Home Manager Module + nix-config Integration

**Date:** 2026-02-19

## Overview

Add a Home Manager module to the `lazytmux` flake (`github:noamsto/lazytmux`) and integrate it into `nix-config`, replacing the existing `home/terminal/tmux/` module entirely. Also improve the session picker and status bar layout.

## Part 1: Home Manager Module (lazytmux repo)

### Module API

```nix
programs.lazytmux = {
  enable = true;  # Adds tmux-wrapped + helper scripts to PATH

  wt.enable = true;  # Adds wt (git worktree manager) to PATH

  startupSession = {
    enable = false;  # Opt-in systemd user service
    name = "main";   # Session name
    directory = "~/projects";  # Starting directory

    terminal = {
      term = "xterm-kitty";
      colorterm = "truecolor";
      termProgram = "kitty";
      terminfoPath = null;  # e.g. "${pkgs.kitty}/share/terminfo"
    };
  };
};
```

### Module Implementation

File: `lazytmux/modules/home-manager.nix`

The module:
1. Adds `tmux-wrapped` package to `home.packages` when `enable = true`
2. Adds `wt` package to `home.packages` when `wt.enable = true`
3. Creates `systemd.user.services.tmux-startup` when `startupSession.enable = true`:
   - Type: forking
   - After/Wants: graphical-session.target
   - WantedBy: graphical-session.target
   - ExecStartPre: import DISPLAY, WAYLAND_DISPLAY, XDG env vars
   - ExecStart: `tmux new -s <name> -c <directory> -d`
   - RemainAfterExit: true
   - TimeoutStopSec: 5s
   - Environment: COLORTERM, TERM, TERM_PROGRAM, TERMINFO, TMUX_TMPDIR from terminal config

### Flake Changes

`lazytmux/flake.nix` adds:
- `flakeModules.homeManager` or `homeManagerModules.default` output
- No new inputs needed (Home Manager module is just a function, doesn't require HM as a flake input)

## Part 2: Status Bar Layout Changes (lazytmux repo)

### Line 0 Changes

**Before:**
- Left: `[session] name  [branch] branch  [dir] dir`
- Right: `[claude status]`

**After:**
- Left: `[session] name  [branch] branch  [dir] dir  [claude status]`
- Right: `[app icon] [process name]`

The right side uses `#{window_name}` (nerd font icon) + `#{pane_current_command}` (process name) to show what's running in the active pane.

### Files Changed

- `config/tmux.conf.nix`: Update `status-format[0]` left/right sections

## Part 3: Session Picker Improvements (lazytmux repo)

### Current Format

- Session rows: `session_name (Nw) [claude]`
- Window rows: `index: icon+name [branch]`

### New Format

- Session rows: `[session icon] session_name  [dir icon] session_path  [claude status]`
- Window rows: `index: [app icon] window_name  [branch icon] branch` (branch only when `@branch` is set)

### Session Path

The session picker needs the session's working directory. Options:
- Use `#{session_path}` (tmux built-in, returns the default-path of the session)
- Shorten with `~` replacement for home directory

### Files Changed

- `scripts/tmux-session-picker.sh`: Update `-F` format string
- `scripts/tmux-window-picker.sh`: Update `-F` format string to include branch icon

## Part 4: nix-config Integration

### Add Flake Input

```nix
# flake.nix
inputs.lazytmux = {
  url = "github:noamsto/lazytmux";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### Wire HM Module

Pass lazytmux HM module into Home Manager configuration and configure it.

### Remove Old Files

Delete entirely:
- `home/terminal/tmux/` (default.nix, named-session.nix, sesh-utils.nix, scripts/)
- `home/terminal/wt/`

### Keep in nix-config

- `home/terminal/fish/default.nix` — fish tmux wrapper function (unchanged)
- `home/terminal/kitty/default.nix` — kitty shell integration (unchanged)
- Sesh scripts and sidebar scripts — left for future sorting, not part of lazytmux

### Update Imports

- `home/terminal/default.nix` — remove `./tmux` and `./wt` imports, add lazytmux config block

## Scope Summary

| Change | Repo | Files |
|--------|------|-------|
| HM module | lazytmux | modules/home-manager.nix, flake.nix |
| Status bar right side | lazytmux | config/tmux.conf.nix |
| Claude status move to left | lazytmux | config/tmux.conf.nix |
| Session picker format | lazytmux | scripts/tmux-session-picker.sh |
| Window picker format | lazytmux | scripts/tmux-window-picker.sh |
| Add flake input | nix-config | flake.nix |
| Configure HM module | nix-config | home/terminal/default.nix |
| Delete old tmux module | nix-config | home/terminal/tmux/, home/terminal/wt/ |

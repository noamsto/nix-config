# Tmux Session Sidebar Design

## Overview

A toggleable right-side pane showing all tmux sessions with window counts and Claude status indicators.

## User Experience

### Visual Layout

```
┌─────────────────────────────────┬──────────────────┐
│                                 │  Sessions        │
│                                 │ ─────────────────│
│      Your main work area        │ ▸ main     [3] 󰪢│
│                                 │   nix-cfg  [2] 󰔟│
│                                 │   work     [1] ✓ │
│                                 │                  │
└─────────────────────────────────┴──────────────────┘
                                    ~20 chars wide
```

### Keybindings

- `Alt+b` - Toggle sidebar visibility
- `j`/`↓` - Move selection down
- `k`/`↑` - Move selection up
- `Enter` - Switch to selected session
- `q`/`Esc`/`Alt+b` - Close sidebar

### Display Format

```
▸ main       [3] 󰪢    # current session, 3 windows, Claude processing
  nix-config [2] 󰔟    # 2 windows, Claude waiting
  work       [1]       # 1 window, no Claude activity
```

- Current session: highlighted with `▸` marker
- Window count in brackets
- Claude status icons (same as status bar)

## Technical Implementation

### Components

1. **`tmux-sidebar-tui.sh`** - The sidebar display script
   - Loops: fetch sessions, render, handle input
   - Uses existing `claude-session-status` for status icons
   - Refreshes every 1 second via `read -t 1` timeout

2. **`tmux-sidebar.sh`** - Toggle script bound to `Alt+b`
   - Checks if sidebar pane exists (via environment marker)
   - If exists → kills it
   - If not → creates narrow pane on right, runs TUI script

### State Tracking

- Sidebar pane marked with environment variable `TMUX_SIDEBAR=1`
- Toggle script finds panes with this marker using `tmux list-panes`

### Data Flow

```bash
# Session data
tmux list-sessions -F "#{session_name}:#{session_windows}:#{?session_attached,1,0}"

# Claude status per session
claude-session-status <session> --format icon
```

### Edge Cases

- Single session: Still shows sidebar (useful to see Claude status)
- Many sessions: Scrollable if exceeds pane height
- Multiple windows: Only one sidebar globally (marker detection)

## Files Changed

- `home/terminal/tmux/scripts/tmux-sidebar.sh` - New toggle script
- `home/terminal/tmux/scripts/tmux-sidebar-tui.sh` - New TUI script
- `home/terminal/tmux/sesh-utils.nix` - Add new scripts to packages
- `home/terminal/tmux/default.nix` - Add `Alt+b` keybinding

# HyprQuickFrame Fork: Resizable Region Selection

## Problem

The current screenshot workflow (grimblast + slurp + satty) uses slurp for region
selection, which is fire-and-forget — you draw a rectangle once and can't adjust it.
KDE Spectacle allows resizing/moving the selection before capturing.

## Solution

Fork [HyprQuickFrame](https://github.com/Ronin-CK/HyprQuickFrame), a Quickshell-based
screenshot tool for Hyprland, and add a two-phase region selection with resize handles.

## Design

### Interaction Model

**Phase 1 — Draw:** Drag to create initial selection rectangle (unchanged from upstream).

**Phase 2 — Adjust:** On mouse release, instead of capturing immediately:
- 8 resize handles appear (4 corners + 4 edge midpoints)
- Drag a handle to resize from that edge/corner
- Drag inside the selection to move it
- Click outside to clear and restart
- Enter or double-click to confirm and capture
- Escape to cancel entirely
- Dimension label stays visible throughout

### Cursor Behavior

| Position | Cursor |
|---|---|
| Corner handle | Diagonal resize (nwse/nesw) |
| Edge handle | Horizontal/vertical resize |
| Inside selection | Move cursor |
| Outside selection | Crosshair (draw new) |

### Changes to `RegionSelector.qml`

Add a `state` property with values: `idle`, `drawing`, `adjusting`.

- `idle` → `drawing`: on mouse press
- `drawing` → `adjusting`: on mouse release (if selection > 5px)
- `adjusting` → confirmed: on Enter/double-click → emit `regionSelected`
- `adjusting` → `idle`: on click outside or Escape
- `drawing` → full screen: on release with < 5px selection (existing behavior)

Resize handles: 8 small `Rectangle` items positioned at corners and edge midpoints
of the selection. Each handle has a `MouseArea` that initiates resize on drag.

Move: a `MouseArea` covering the selection interior that moves it on drag.

### What Stays Unchanged from Upstream

- Screen freeze via Quickshell's `ScreencopyView`
- Shader-based dimming overlay (`dimming.frag`)
- `grim` for actual screen capture
- `satty` for post-capture annotation
- Window mode and full screen mode
- Floating control pill UI
- Theme system (`theme.toml`)
- Nix flake structure

### Integration with nix-config

1. Add fork as a flake input
2. Add package to `home/desktop/hyprland/default.nix`
3. Replace `grimblast-satty` keybind (Print key) with the new tool
4. Keep existing `screenshot-menu` and helper scripts as fallback

### Dependencies

Same as upstream HyprQuickFrame:
- Quickshell (0.2.1+)
- grim
- imagemagick
- wl-clipboard
- satty
- libnotify

All already present in the nix-config except imagemagick (which may need adding).

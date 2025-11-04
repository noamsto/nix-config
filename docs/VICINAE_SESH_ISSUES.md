# Vicinae Sesh Integration Issues

**Date:** 2025-11-04
**Status:** Known Issues - Low Priority

## Problem: Inconsistent Icon Display

### Observed Behavior
When using `sesh-launcher` (SUPER+A) with vicinae dmenu:
- **Some sessions show icons**: `󰒜  nix-config (tmux)`
- **Some sessions missing icons**: `devenv (zoxide)`
- Both are from `sesh list --icons` output

### Root Cause
**Vicinae dmenu has inconsistent ANSI code handling:**
- Doesn't render ANSI color codes (shows literal `\033[34m`)
- Strips ANSI codes in `sesh-list-grouped.sh`
- But sesh's icon placement is inconsistent between session types:
  - Tmux sessions: Always have icons
  - Zoxide directories: Icons may be missing depending on entry
  - Config sessions: Icons present

### Impact
**Medium severity:**
- ✅ Sessions still attach correctly (extraction logic handles both formats)
- ⚠️ Visual inconsistency makes it harder to distinguish session types
- ⚠️ Missing icons can cause wrong session selection (similar names without icons)

### Current Workaround
**Session name extraction in `sesh-launcher.sh` handles both:**
```bash
# Removes first field if it's an icon, otherwise uses whole string
# Works for: "󰒜 name" and "name" formats
```

**Tmux integration (Prefix+S) works perfectly:**
- fzf properly renders ANSI codes and icons
- Preview shows correct information
- All operations work as expected

### Why Low Priority
1. **Tmux workflow is primary** (Prefix+S) - works perfectly
2. **Vicinae launcher is secondary** (SUPER+A from desktop)
3. **Functional despite visual issues** - attaches correctly
4. **Root cause is vicinae's dmenu limitations** - not our code

## Potential Solutions (Future)

### Option A: Port to Vicinae Extension (Recommended Long-term)
- Use proper vicinae extension instead of dmenu
- Rich UI with consistent icon rendering
- See: `docs/VICINAE_SESH_PORTING_GUIDE.md`
- **Effort:** 10-15 hours
- **Wait for:** Vicinae extension API maturity

### Option B: Use gum Instead of vicinae dmenu
- Replace vicinae dmenu with gum for session selection
- gum has better rendering support
- **Pros:** Consistent display, better filtering
- **Cons:** Different UI style, may not match desktop aesthetic

### Option C: Add More Session Metadata
- Include more info in display to distinguish sessions
- Example: `󰒜  nix-config (tmux) - /home/noams/nix-config`
- **Pros:** Easier to identify correct session even without icons
- **Cons:** Longer strings, more visual clutter

### Option D: Live with it
- Primary workflow (tmux Prefix+S) works perfectly
- Desktop launcher is secondary use case
- Icons work most of the time
- **Current choice:** Good enough for now

## Testing Notes

### What Works ✅
- Tmux session picking with icons
- Session preview with windows, git status
- Ctrl-D to kill sessions
- Deduplication logic
- Session attachment from both vicinae and tmux

### What Doesn't Work ⚠️
- Vicinae dmenu inconsistent icon display
- Some zoxide entries missing icons
- Visual distinction not always clear

## Related Files
- `home/desktop/hyprland/scripts/sh/sesh-launcher.sh` - Vicinae dmenu launcher
- `home/terminal/tmux/scripts/sesh-list-grouped.sh` - Session list generator
- `home/terminal/tmux/scripts/sesh-preview.sh` - Preview generator
- `home/terminal/tmux/default.nix` - Tmux keybindings

## See Also
- `docs/VICINAE_SESH_PORTING_GUIDE.md` - Full Raycast extension porting guide
- Vicinae dmenu docs: https://docs.vicinae.com/cli/dmenu
- Vicinae extension API: https://docs.vicinae.com/extensions/introduction

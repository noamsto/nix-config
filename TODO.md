# TODO

## Bugs to Investigate

### Claude Code hanging on exit
- **Issue**: Claude Code almost hangs when closing
- **Investigation findings**:
  - ✅ No SessionEnd hooks installed
  - ✅ No fish exit handlers interfering
  - ✅ No tmux hooks causing issues
  - ✅ No wrapper scripts around claude binary
- **Likely causes**:
  - MCP servers not shutting down cleanly (context7, linear, tavily)
  - One of the MCP servers might have a blocking operation on exit
- **Debugging steps to try**:
  1. Disable MCP servers one by one to identify the culprit
  2. Check `~/.claude/logs/` for errors during shutdown
  3. Run `strace -p $(pgrep claude)` while closing to see what it's waiting on
  4. Try `timeout 5s claude` to force kill after 5 seconds

### Kitty window showing hyprbar when not toggled
- **Issue**: Kitty window sometimes shows top bar (hyprbar) even when not toggled (flaky)
- **Environment**: Hyprland
- **Expected**: Hyprbar should only appear when toggled
- **Investigation findings**:
  - Rule exists: `"hyprbars:no_bar 1, match:float false"` (line 257 in window_rule.nix)
  - Should hide hyprbars on all tiling windows
  - No conflicting Kitty-specific rules
  - **Reddit post found**: https://www.reddit.com/r/hyprland/comments/1prnwc8/need_help_using_plugin_hyprbars_hyprbarsno_bar/
    - Others experiencing the same issue with `hyprbars:no_bar` not working correctly
    - Confirms this is a known bug with the hyprbars plugin
- **Likely cause**:
  - Race condition: Hyprland evaluates rules before window is fully initialized
  - Hyprbars plugin might evaluate bar visibility before float state is set
  - Known bug in hyprbars plugin
- **Potential fixes**:
  1. Add explicit Kitty rule: `"hyprbars:no_bar 1, match:class ^(kitty)$"` (workaround)
  2. Move the `match:float false` rule later in the list
  3. Report/upvote bug to hyprbars plugin maintainer
  4. Wait for Hyprland/hyprbars update that fixes race condition

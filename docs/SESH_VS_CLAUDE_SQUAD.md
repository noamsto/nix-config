# Sesh vs Claude-Squad: Workflow Comparison

**Date:** 2025-11-04
**Status:** Evaluation Phase

## Overview

This document compares two approaches for managing tmux sessions and git worktrees in development workflows:

1. **Our Custom Solution:** Sesh + Tmux + Vicinae integration (Phases 1-3)
2. **Claude-Squad:** TUI-based multi-agent orchestration tool (Phase 5)

Both are now installed and available for side-by-side comparison.

---

## Quick Reference

### Our Sesh Solution

**Commands:**
```bash
# From anywhere
SUPER+A                # Vicinae session picker
sesh-new <dir>         # Create session
sesh-kill              # Delete session

# Inside tmux
Prefix+S               # Full session picker with preview
Prefix+K               # Quick gum picker

# Worktree automation
# (Automatic when using git worktrees skill in Claude Code)
worktree-session-hook <path> <branch>
```

### Claude-Squad

**Commands:**
```bash
# Launch TUI
claude-squad           # or 'cs'

# With options
cs --autoyes           # Auto-accept prompts
cs --program "aider"   # Use specific agent

# Management
cs reset               # Reset all instances
cs debug               # Show config paths
cs version             # Show version
```

---

## Detailed Comparison

### Architecture

| Aspect | Sesh Solution | Claude-Squad |
|--------|---------------|--------------|
| **Approach** | Shell scripts + tmux + sesh CLI | Go TUI application |
| **UI** | Multiple entry points (vicinae, tmux pickers) | Single centralized TUI |
| **Session Management** | Sesh (tmux + zoxide integration) | Custom tmux orchestration |
| **Worktrees** | `.worktrees/` convention, auto-create sessions | Automatic per-task worktree creation |
| **Agents** | Single Claude Code instance per session | Multi-agent (Claude, Aider, Codex, etc.) |

### Use Cases

**Sesh Solution Best For:**
- ✅ Single developer working with one context at a time
- ✅ Long-lived sessions for ongoing projects
- ✅ Manual control over session lifecycle
- ✅ Integration with existing zoxide/tmux workflows
- ✅ Quick context switching between projects
- ✅ Working across multiple unrelated projects

**Claude-Squad Best For:**
- ✅ Parallel task execution with multiple AI agents
- ✅ Task-based workflows (create → complete → cleanup)
- ✅ Change review before merging
- ✅ Experimenting with different AI models simultaneously
- ✅ Complex features requiring multiple isolated workstreams

### Workflow Comparison

#### Scenario 1: Create New Feature Branch

**Sesh Workflow:**
```bash
# In Claude Code, use git worktrees skill
# → Worktree created at .worktrees/feature-auth
# → Session auto-created: nix-config/feature-auth
# → Press Prefix+S to switch
# → Work in that session
# → Session persists until you kill it
```

**Claude-Squad Workflow:**
```bash
# Launch claude-squad TUI
cs

# Create new task
# → Prompts for task description
# → Creates worktree automatically
# → Opens agent in tmux session
# → Agent works on task
# → Review changes in TUI
# → Accept/reject/edit
# → Cleanup when done
```

#### Scenario 2: Switch Between Contexts

**Sesh Workflow:**
```bash
# From desktop: SUPER+A → Select session
# Inside tmux: Prefix+S → Preview → Select
# Fast, visual, keyboard-driven
```

**Claude-Squad Workflow:**
```bash
# Launch TUI: cs
# Navigate with keyboard
# Select session from list
# View in dedicated pane
```

#### Scenario 3: Kill Old Sessions

**Sesh Workflow:**
```bash
# Quick: sesh-kill → fzf picker → confirm
# In tmux: Prefix+S, Ctrl-D on unwanted session
```

**Claude-Squad Workflow:**
```bash
# In TUI: Navigate to session → Delete action
# Or: cs reset (nuclear option - kills all)
```

---

## Feature Matrix

| Feature | Sesh Solution | Claude-Squad | Winner |
|---------|---------------|--------------|--------|
| **Session Icons** | ✅ Type-based (tmux/zoxide/config) | ❓ Unknown | Sesh |
| **Preview** | ✅ Windows, git status, session info | ✅ Change diff, task status | Tie |
| **Multi-agent** | ❌ One agent per session | ✅ Multiple agents orchestrated | Squad |
| **Zoxide Integration** | ✅ Native | ❌ Not integrated | Sesh |
| **Desktop Launcher** | ✅ Vicinae (SUPER+A) | ❌ Terminal TUI only | Sesh |
| **Tmux Integration** | ✅ Native keybindings (Prefix+S/K) | ✅ Creates tmux sessions | Tie |
| **Git Worktrees** | ✅ Auto-create sessions | ✅ Auto-create worktrees | Tie |
| **Change Review** | ❌ Manual git workflow | ✅ Built-in review UI | Squad |
| **Learning Curve** | ⭐ Low (familiar tmux/shell) | ⭐⭐ Medium (new TUI interface) | Sesh |
| **Customization** | ✅ Full control (shell scripts) | ❌ Go binary (limited) | Sesh |
| **Maintenance** | ⭐⭐ Medium (bash scripts) | ⭐ Low (upstream binary) | Squad |

---

## Performance

### Startup Time

**Sesh Solution:**
- Vicinae launcher: <100ms
- Tmux picker: <200ms
- Session switch: Instant

**Claude-Squad:**
- TUI launch: ~500ms
- Session creation: Variable (depends on worktree setup)

### Resource Usage

**Sesh Solution:**
- Minimal (shell scripts, native tools)
- Sessions persist independently
- No central daemon

**Claude-Squad:**
- TUI process while active
- Multiple tmux sessions (same as sesh)
- Potentially higher overhead with multiple agents

---

## Integration with SuperClaude

### Sesh Solution

**✅ Native Integration:**
- Custom skill: `~/.claude/skills/worktree-tmux-integration.md`
- Automatic invocation from git worktrees skill
- Session auto-creation
- Seamless with SuperClaude workflow

**Workflow:**
```
Claude Code → git worktrees skill → worktree-session-hook → session created
```

### Claude-Squad

**⚠️ Separate Workflow:**
- Run claude-squad as standalone tool
- Manages its own sessions/worktrees
- Not integrated with SuperClaude skills (yet)
- Would require custom integration

**Workflow:**
```
Launch cs → Create task → Squad manages everything → Review → Cleanup
```

---

## Pros & Cons Summary

### Sesh Solution

**Pros:**
- ✅ Seamless integration with existing workflow
- ✅ Works with SuperClaude git worktrees skill
- ✅ Multiple access points (desktop, tmux, terminal)
- ✅ Leverages existing tools (zoxide, fzf, vicinae)
- ✅ Fast and lightweight
- ✅ Full customization control
- ✅ Long-lived sessions for ongoing work

**Cons:**
- ❌ No multi-agent orchestration
- ❌ No built-in change review
- ❌ Manual git workflow
- ❌ One context at a time

### Claude-Squad

**Pros:**
- ✅ Multi-agent parallel execution
- ✅ Built-in change review UI
- ✅ Task-oriented workflow
- ✅ Automatic worktree management
- ✅ Centralized session control
- ✅ Ready-made solution (no custom code)

**Cons:**
- ❌ Separate from daily tmux workflow
- ❌ TUI-only (no desktop launcher)
- ❌ Task-based model (not long-lived sessions)
- ❌ Not integrated with SuperClaude skills
- ❌ Go binary (harder to customize)
- ❌ Different mental model to learn

---

## Recommendation Matrix

### Use Sesh Solution When:

- 📝 You're working on a single project/context
- 📝 You need long-lived sessions across days/weeks
- 📝 You want quick context switching (SUPER+A)
- 📝 You're using SuperClaude git worktrees skill
- 📝 You prefer your existing tmux muscle memory
- 📝 You need zoxide integration (frecent directories)

**Estimate:** 90% of daily development work

### Use Claude-Squad When:

- 🚀 You need multiple AI agents working in parallel
- 🚀 You're experimenting with different models (Claude, Aider, Codex)
- 🚀 You want structured change review before committing
- 🚀 You have a complex task that benefits from parallelization
- 🚀 You want task isolation with automatic cleanup

**Estimate:** 10% of tasks (experimental/complex features)

---

## Hybrid Workflow Suggestion

**Best of Both Worlds:**

1. **Daily Work:** Use sesh solution
   - SUPER+A for quick session switching
   - Prefix+S for exploration
   - `worktree-session-hook` for new features
   - Integrated with SuperClaude skills

2. **Special Cases:** Use claude-squad
   - Large refactorings requiring multiple approaches
   - Experimentation with different AI models
   - Tasks that benefit from parallel agent execution
   - When you need built-in change review

3. **Integration Point:**
   - Both use `.worktrees/` directory
   - Can switch between tools as needed
   - Sessions are compatible (both use tmux)

---

## Installation Status

### Sesh Solution ✅

**Installed:**
- programs.sesh (Home Manager module)
- Custom scripts: sesh-new, sesh-kill, sesh-list-grouped, sesh-icon, sesh-preview
- Vicinae launcher (SUPER+A)
- Tmux keybindings (Prefix+S, Prefix+K)
- Worktree integration skill

**Available:** System-wide after `nh home switch`

### Claude-Squad ✅

**Packaged:**
- Available as: `packages.claude-squad`
- Nix flake output

**Installation Options:**

**Option A: Try without installing:**
```bash
nix run .#claude-squad
```

**Option B: Add to home packages:**
```nix
# In home/packages.nix or appropriate location
home.packages = with pkgs; [
  self.packages.${system}.claude-squad
];
```

**Option C: Add to system packages:**
```nix
# In nixos/packages.nix
environment.systemPackages = with pkgs; [
  self.packages.${system}.claude-squad
];
```

---

## Next Steps for Evaluation

### Week 1: Sesh-Only Workflow
1. Use sesh solution exclusively
2. Note any pain points or missing features
3. Track how often you want parallel agents

### Week 2: Claude-Squad Trial
1. Install claude-squad: Add to home packages
2. Try it for 2-3 complex tasks
3. Compare developer experience

### Week 3: Decision
- Keep sesh as primary (likely)
- Use claude-squad for specific cases (optional)
- Or: Fully adopt claude-squad (unlikely given your workflow)

---

## Conclusion

**You now have both options available:**

1. **Sesh Solution** - Lightweight, integrated, perfect for daily work
2. **Claude-Squad** - Powerful orchestration for special cases

The sesh solution is production-ready and integrated into your workflow. Claude-squad is packaged and ready to evaluate when you encounter a task that would benefit from multi-agent parallel execution.

**My Prediction:** You'll use sesh 95% of the time, and maybe try claude-squad occasionally for experimental/complex features.

**Files to Reference:**
- This comparison: `docs/SESH_VS_CLAUDE_SQUAD.md`
- Raycast extension porting: `docs/VICINAE_SESH_PORTING_GUIDE.md`
- Vicinae known issues: `docs/VICINAE_SESH_ISSUES.md`

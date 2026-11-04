# Design: stable-path Claude plugin indirection

**Date:** 2026-07-21
**Repo:** nix-config (implementation site); relates to aeye + lazytmux
**Status:** locked — pending implementation plan

## Problem

Hook-script fixes shipped in aeye (e.g. aeye #140, the Phase-2 over-capture fix)
do **not** reach an already-running Claude session after `nh home switch`, even
once the fix is built into the profile. The user must restart every agent
session to pick it up — a recurring papercut, and the reason a known-fixed
carousel bug can still reproduce (the fix is in `flake.lock` but not live in
long-running sessions).

Root cause: the `claude` wrapper bakes an immutable `/nix/store` path into
`--plugin-dir` (`home/ai/claude-code/default.nix:186`,
`--plugin-dir ${inputs.lazytmux.inputs.aeye}/adapters/claude-code/plugin`).
Claude sets `CLAUDE_PLUGIN_ROOT` to that exact string at process start and never
re-reads it, so a running session keeps executing the old plugin's hook scripts.

## Key mechanism (probe-verified 2026-07-21)

Launching `claude --plugin-dir <symlink>` and recording `CLAUDE_PLUGIN_ROOT` from
a SessionStart and a UserPromptSubmit hook: **Claude keeps the symlink path
verbatim, it does not canonicalize it** to the real directory.

```
[SessionStart]     CLAUDE_PLUGIN_ROOT=.../probe/link   (the symlink, not .../probe/real)
[UserPromptSubmit] CLAUDE_PLUGIN_ROOT=.../probe/link
```

`hooks.json` is read once at startup, but the commands it lists
(`"${CLAUDE_PLUGIN_ROOT}"/scripts/images.sh`) run fresh on each fire. So if
`--plugin-dir` is a **stable symlink** that a switch atomically repoints, a
running session resolves the symlink at each hook fire and executes the **new**
script — no restart. The OS guarantees the exec-time resolution; the probe
established the only Claude-specific unknown (symlink kept, not resolved).

The binary side already self-heals independently: the plugin scripts resolve
tools via `command -v "${AEYE_BIN:-aeye}"` / `${AEYE_RESVG:-resvg}` (PATH +
env override, no baked store paths), and PATH points at the rebuild-stable
profile. So a switch updates both the scripts (via the symlink) and the
binaries (via PATH).

## Design

The change is entirely nix-config wiring. **aeye and lazytmux need no code
change** — aeye's hooks already reference `${CLAUDE_PLUGIN_ROOT}` relatively,
which is precisely what makes this work.

1. **Expose each plugin dir at a rebuild-stable, HM-owned path.** Declare an
   `xdg.configFile` (directory symlink, non-recursive) per plugin, sourced from
   the flake-input plugin dir. HM repoints it to the new store path atomically
   on every activation.
2. **Point the wrapper at the stable paths.** In
   `home/ai/claude-code/default.nix`, replace the two `--plugin-dir <store>`
   arguments with the stable paths.

Mirrors the rebuild-stable-path principle lazytmux already applies to its Codex
**status** hooks (`modules/home-manager.nix:771`, chosen there for trust-hash
stability). Note the precedent is inconsistent: the Codex **resume** hook
(`:754`) still bakes a store path and has the same freeze problem — a latent
parallel issue, explicitly **out of scope** here.

### Stable path requirement

The path MUST be HM-owned and MUST NOT sit under a directory Claude manages
itself: not `~/.claude/plugins` (Claude's own marketplace cache) and not
`~/.config/claude`. Use a neutral namespace, e.g.
`${config.xdg.configHome}/nix-managed/claude-plugins/{aeye,lazytmux}`. Exact
name is a bikeshed for the plan; the constraint is neutral + HM-owned.

Do both plugins (aeye + lazytmux's `claude-plugin`) for consistency, though the
motivating case is aeye's capture hooks.

### Data flow after `nh home switch`

```
flake input bumped -> new plugin store path
HM activation       -> repoints ~/.config/nix-managed/claude-plugins/aeye
running session     -> CLAUDE_PLUGIN_ROOT (stable path) now resolves to new dir
next capture fires  -> runs new images.sh   [self-healed, no restart]
```

## Scope & limits (must document for the user)

- **Self-heals:** hook **script-body** changes and the aeye/resvg **binaries**.
  aeye #140 is a script-body change → covered.
- **Does NOT self-heal:** `hooks.json` **structure** changes (added/removed
  hooks, changed matchers) — read once at startup, still need a session restart.
- **One-time transition:** sessions currently running the old store-path wrapper
  keep the old `--plugin-dir` arg; they need **one** restart to adopt the
  stable-path arg, and self-heal across all switches thereafter.
- **Viewer:** already self-heals via PATH; untouched. (Unrelated: clear the
  debug bridge with `tmux set-environment -gu AEYE_BIN` / `-gu AEYE_DEBUG` once
  the PR #142 bleed trace is done, or it pins the viewer to the trace binary.)
- **Manifest format skew mid-session:** old + new hooks may write the same
  manifest with slightly different fields; the viewer's `parseManifest` tolerates
  unknown fields and dedupes by path+mtime, so this is benign. No action needed.

## Testing

- **Symlink:** after a switch, `readlink -f <stable>/aeye` resolves to the new
  aeye store plugin dir and contains `hooks/hooks.json`.
- **Self-heal (integration):** start a session; bump the aeye input + switch
  WITHOUT restarting; trigger a capture; confirm the new script ran (a Bash-only
  printed out-of-cwd path is not captured — the #140 behavior).
- **Regression:** a freshly launched session loads both plugins (skills present,
  SessionStart/PostToolUse hooks fire).
- **Transition:** confirm the first switch onto the stable-path wrapper needs one
  restart to adopt, and subsequent switches do not.

## Out of scope

- The Codex resume-hook store-path freeze (`home-manager.nix:754`).
- Any post-switch "restart stale sessions" nudge (rejected in favor of
  indirection).
- The PR #142 viewer owner-trace work (separate track).

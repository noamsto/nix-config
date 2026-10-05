# Claude Code Instructions

@~/.claude/AGENTS.shared.md
@~/.claude/CLAUDE.profile.md

## Settings

In `~/nix-config/home/ai/claude-code/`:

- `settings.json` → writable `~/.claude/settings.json`: plain JSON settings,
  common plugins, permissions, theme, sandbox, MCP servers, preferences.
  Third-party tools/UI edit this file; runtime keys such as
  `feedbackSurveyState` may add diff noise.
- `default.nix` → read-only `--settings` overlay (`nix-settings-json`): hooks,
  statusLine, anything referencing `/nix/store`, and profile-dependent settings
  gated with `lib.optionalAttrs`. Overlay plugins are profile-locked in the TUI.

Object-valued keys (`enabledPlugins`, `permissions`, `env`, `mcpServers`, `hooks`)
deep-merge; the overlay wins per key. Keep nested keys disjoint unless overriding
intentionally.

## Tools and skills

- Prefer simple Bash commands that match `Bash(cmd *)` permissions: direct
  arguments and separate calls. Use dedicated tools for reads/searches;
  compound syntax, substitutions, and pipes are acceptable when needed.
- Debugging: use `diagnosing-bugs` over `superpowers:systematic-debugging`;
  establish a tight loop capable of going red before forming hypotheses.
- Skills, AGENTS.md, CLAUDE.md: use `writing-for-agents` over
  `superpowers:writing-skills`.
- Files over ~300 lines: locate the relevant region with signatures (`ast-grep`),
  `context-efficient-tools:code-structure`, or symbol search before reading it.
  For whole-file audits, pass an explicit Read limit; the skeleton guard blocks
  unbounded reads of large files.
- Immediately before Edit/Write, read the target region. Re-read if a build,
  formatter, codegen, git, or other external step may have changed it. A successful
  Edit leaves the read current; no confirming read needed.
- Parallelize independent read-only calls. Run mutations and dependent steps
  sequentially; one failed parallel call can cancel siblings.
- Playwright screenshots: default to PNG for crisp text/borders; JPEG when image
  volume/token cost dominates. Vision accepts JPEG, PNG, GIF, WebP; not AVIF/HEIC.

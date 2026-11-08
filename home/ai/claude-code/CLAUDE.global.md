# Claude Code Instructions

@~/.claude/AGENTS.shared.md
@~/.claude/CLAUDE.profile.md

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
- Claude Code settings, hooks, and plugin changes in nix-config: the
  `claude-code-settings` skill there explains the two settings layers.
- When a task needs Claude in Chrome (a logged-in web console), start
  the browser yourself with Bash `run_in_background`: `chromium-claude` on a
  Linux desktop. Then wait
  for `list_connected_browsers` (or `tabs_context_mcp`) to answer. Never ask the
  user to open it. The user still types passwords and sign-ins. If the command is
  missing or the extension doesn't connect within about a minute, fall back to
  paste-ready steps and say what failed.

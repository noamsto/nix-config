---
description: Engine-neutral machine conventions shared by every coding agent
alwaysApply: true
---

# Shared Agent Conventions

Keep harness-specific rules in that harness's instructions. Preserve this
frontmatter: Cursor requires `alwaysApply: true`.

## Branches and tracking

Before planning or implementing new work, check the origin's org and isolate
the work with `wt switch -c <branch>`. Every repo needs its own worktree;
commit on a branch, never directly on the default branch. Other forms:
`wt switch <branch>`, `wt list`, `wt remove`, `wt merge`; flags go after the
subcommand, and never wrap `wt` in `cd` or command substitution.

- factify-inc: tracked in Linear. Use an existing ticket or get confirmation
  to create one (show full title, description, labels, priority first), and use
  Linear's branch name verbatim. Ticket writes need explicit approval; never put
  customer identifiers in commits or PR bodies.
- Any other org: open a GitHub issue (after confirmation) only for substantial
  work; branch names `type/id-desc`, or `type/desc` without an issue.
- Unrelated task switch: commit the previous task's uncommitted work first,
  briefly noting it. No confirmation needed unless the user says not to commit.

The `worktrunk` and `work-tracking` skills (where installed) hold the full wt
flags, branch types, `gh repo create` defaults (`gh-repo-defaults`), and
external contributor handling.

## Finishing work

Staging and committing are authorized without confirmation. Finish branches
with push + PR, assigned via `gh pr create --assignee @me`, without asking.
Ask only when the direction remains undecided (e.g. a spike). Never add
`Generated with Claude Code` lines or AI `Co-Authored-By` trailers to commits,
PRs or issues.

## Safety and validation

- Delete files with `gtrash put`. Before destructive git operations, trash
  affected uncommitted changes/untracked files; committed work is recoverable
  through reflog.
- Run `shellcheck` after creating/editing shell scripts; fix all findings.
- A nested Hyprland needs its own `XDG_RUNTIME_DIR` and an absolute parent
  `WAYLAND_DISPLAY`, otherwise it clobbers the live systemd user environment.
  Launch and repair steps: `~/nix-config/.agents/skills/nested-wayland/SKILL.md`.
- If a Nerd Font glyph fails to render, use a variable with its intended icon
  name in a comment (e.g. `# nerd: nf-md-folder`); the user supplies the glyph.

## Communication and design

- Provide shell commands in fish syntax.
- Use Markdown tables or bullets for comparisons, reviews, and analysis;
  no ToonFormat.
- Estimate with ranges, scope included/excluded work, flag human decisions,
  and mention where AI accelerates work; avoid precise times/calendar dates.
- Design it twice: sketch two approaches before choosing. Pull complexity
  downward so callers stay simple; design APIs that make errors impossible.

## Lean code

Match the surrounding naming, structure, error handling, and logging. Stay in
scope: no unrelated formatting, renames, or improvements.

- Comments explain only a non-obvious why (constraint, invariant, workaround),
  never restate code, name callers, or reference tasks/PRs/tickets.
- Avoid speculative guards, fallbacks, and catches on trusted paths.
- Fix checker findings at the source; no `as any`, `@ts-ignore`, or
  `# type: ignore` escape hatches.
- Flatten nesting with early returns. Remove replaced code and scaffolding
  (debug prints, leftover logging, placeholder TODOs); git history is the backup.
- Verify unfamiliar imports, methods, and options before using them.

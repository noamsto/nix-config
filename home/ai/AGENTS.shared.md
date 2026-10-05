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
commit on a branch, never directly on the default branch.

- **factify-inc:** use an existing Linear ticket or get confirmation to create
  one. Show the full title, description, labels, and priority before creation.
  Use Linear's generated branch name verbatim.
- **Personal repos (any other org):** get confirmation before creating a GitHub
  issue for substantial work (features, multi-session work, work worth tracking).
  Skip issues for trivial fix/chore/docs/lockfile edits. Branch names are
  `type/id-desc`, or `type/desc` without an issue; types: feat, fix, refactor,
  chore, docs. Use one slash.
- **Unrelated task switch:** commit the previous task's uncommitted work first,
  briefly noting it. No confirmation needed unless the user says not to commit.

After `gh repo create`, run `gh-repo-defaults <owner/repo>` to apply squash-only
merges, branch cleanup, auto-merge, and Actions PR permissions.
`gh-repo-defaults --check --all` reports drift; `--all` fixes it.

For Linear issues/comments/projects, show author, timestamp, status, and labels;
use blockquotes for nested comments.

## Worktrunk

Use these subcommands and flags; flags belong after the subcommand:

```text
wt switch -c <branch>   # New branch + worktree
wt switch <branch>      # Existing branch; creates worktree if needed
wt switch               # Interactive picker
wt list                 # Worktrees and status
wt remove               # Remove current worktree; delete branch if merged
wt merge                # Merge current branch into target
```

Flags: `-y`/`--yes` skips prompts; `-b`/`--base` sets creation base;
`-x`/`--execute` runs a command after switching. Branch shortcuts: `^` default,
`-` previous, `@` current, `pr:{N}`, `mr:{N}`. When unsure, use the plain forms
above rather than inventing flags or investigating `wt --help` mid-task.

The post-switch hook owns tmux navigation: one session per repo, one window per
worktree. `[switch] cd = false` leaves the parent shell in place. Run `wt`
directly; never wrap it in command substitution or `cd`.

## Finishing work

Staging and committing are authorized without confirmation. Finish branches
with push + PR, assigned via `gh pr create --assignee @me`, without asking.
Ask only when the direction remains undecided (e.g. a spike).

For external reports/contributions in personal repos:

- Verify the report and suggested fix against the code; then reply on the issue
  with findings, planned fix, and any flaw in the proposed fix.
- Credit `Reported by @handle in #N` in the PR and
  `Reported-by: <handle> <https://github.com/<handle>>` in the commit.
  Use `Co-authored-by:` only when their code lands.

In factify-inc repos, ticket writes require explicit approval; keep customer
identifiers out of commits and PR bodies.

## Safety and validation

- Delete files with `gtrash put`. Before destructive git operations, trash
  affected uncommitted changes/untracked files; committed work is recoverable
  through reflog.
- Run `shellcheck` after creating/editing shell scripts; fix all findings.
- Give nested Hyprland its own `XDG_RUNTIME_DIR` and an absolute parent
  `WAYLAND_DISPLAY` socket path. Otherwise it clobbers the live systemd user
  environment. Launch/repair details: `~/nix-config/CLAUDE.md`.
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

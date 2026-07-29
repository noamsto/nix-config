---
description: Engine-neutral machine conventions shared by every coding agent
alwaysApply: true
---

# Shared Agent Conventions

Engine-neutral rules: how work is tracked, branched, and committed on this
machine, and how Noam wants code written. True regardless of which agent is
running, so all three read this one file:

| Engine | Path |
|--------|------|
| Claude Code | `~/.claude/AGENTS.shared.md`, imported by `CLAUDE.global.md` |
| Codex | `~/.codex/AGENTS.md` — its global instructions path |
| Cursor | `~/.cursor/rules/shared-conventions.mdc` — a global rule, hence the frontmatter above |

The frontmatter is load-bearing for Cursor only: a file under `~/.cursor/rules`
is ignored unless it carries `alwaysApply: true`. Cursor does follow symlinks
there, so all three paths are symlinks to this file. Claude and Codex read the
frontmatter as a few lines of harmless preamble.

Keep harness-specific guidance out of this file. Rules about a single agent's
tools, settings, skills, or hooks belong in that agent's own instructions.

## Worktree Isolation (all repos)

**Before starting new work, isolate it in its own git worktree** — personal repos included, not just factify-inc. Run `wt switch -c <branch-name>` (worktrunk creates the branch + worktree and navigates there). Never begin new work with a plain in-place `git checkout`/`git switch` on the shared checkout, and never commit directly to the default branch — branch first, always.

**Why:** multiple agent sessions can run against one repo at the same time. A plain in-place checkout means they share a single HEAD and race on branch state — one session commits to `main` while another swaps the branch underneath it, producing stray-main commits and half-finished recoveries. A worktree per branch gives each session its own directory and HEAD, so they can't stomp each other.

## New Work Workflow (factify-inc repos only)

**REQUIRED** for repos under the `factify-inc` GitHub org. Does NOT apply to personal repos.

In addition to the worktree isolation above, before implementing or planning any new work:

1. **Create a Linear ticket** (if one doesn't exist):
   - Follow the "Linear Ticket Creation" guidelines below
   - Get user confirmation before creating

2. Use the branch name from Linear (`Cmd+Shift+.` to copy) as the `<branch-name>` when creating the worktree.

This ensures all work is tracked and isolated properly.

## New Work Workflow (personal GitHub repos)

Applies to every repo NOT under `factify-inc` — i.e. anything whose `origin` remote points at a personal org (`noamsto`, etc.). When unsure which kind a repo is, check the remote org: `factify-inc` → Linear flow above; anything else → this flow.

Before implementing or planning new work, in addition to the worktree isolation above:

1. **Open a GitHub issue only for substantial work** — a new feature, a multi-session effort, or anything you'd want to find/reference later. Use `gh issue create` and get user confirmation first (same as the Linear-ticket rule).
   - **Skip the issue for trivial changes** — single `fix`/`chore`/`docs`/lockfile edits. Branch directly with no id.
2. Name the branch per the **Branch Naming** convention below (`type/id-desc`; drop the id when there's no issue), and pass it to `wt switch -c <branch-name>`.

The CLI tooling here (`gh`, `git`, `wt`, tmux) is installed identically on Linux and macOS via Nix, so these steps are the same on both — don't reach for an OS-specific shortcut.

## Branch Naming

**Branch naming depends on where the repo tracks work** — pick the rule by that axis, not by personal taste:

- **Repo uses Linear** (factify-inc): use the branch name Linear generates (`Cmd+Shift+.` to copy), verbatim. **Do NOT apply the convention below** — Linear's name is authoritative; never "improve" it into the `type/id-desc` shape.
- **Repo uses GitHub Issues only** (personal repos, no Linear/Jira): name branches `type/id-desc`, where `id` is the GitHub issue number and `type` reuses the commit-prefix vocabulary (`feat`, `fix`, `refactor`, `chore`, `docs`).
  - Example: `feat/213-id-seed-avatars`, `fix/208-widget-warm-deeplink`, `chore/220-bump-expo-54`.
  - One slash only — `type/` groups branches by kind; `id-desc` stays one unit so `gh` autolink and tab-completion find the number.
  - No issue (the rare doc/lockfile branch): drop the id — `chore/bump-flake-lock`.

## Task Context Switching

When a new task is **unrelated** to current in-progress work and there are uncommitted changes:

1. Briefly note: "Uncommitted changes from [previous task] — committing first."
2. Commit the previous work with an appropriate message
3. Proceed with the new task

No confirmation needed — this is the default. User can say "don't commit" to override.

## Linear

- Display issues/comments/projects with author, timestamp, status, labels visible. Use markdown blockquotes for nested comments.
- Before creating a ticket: always show the full content (title, description, labels, priority) as markdown and wait for confirmation.

## Safe File Deletion

- **Always use `gtrash put` instead of `rm`** when deleting files. This sends files to the trash instead of permanently deleting them.
- **Before running destructive git commands** (`git checkout -- <file>`, `git restore`, `git reset --hard`, `git clean -f`, `git stash drop`, etc.):
  1. Committed work is recoverable via reflog — no extra steps needed
  2. **Uncommitted changes and untracked files** are NOT recoverable — run `gtrash put` on them before proceeding

## Response Formatting

Use markdown tables or bullet lists for comparisons, reviews, and analysis. Do not use ToonFormat in chat responses.

## Git Worktrees

We use **worktrunk** (the `wt` command) for git worktrees. Shell + tmux integration
is configured via Nix (`programs.lazytmux.worktrunk.enable`), so `wt` handles
navigation itself — do **not** wrap it in `cd "$(...)"`.

```bash
wt switch <branch>      # Switch to worktree (creates the worktree if the branch exists)
wt switch -c <branch>   # Create new branch + worktree, then switch
wt switch               # Interactive picker
wt list                 # List worktrees and their status
wt remove               # Remove the current worktree (deletes branch if merged)
wt merge                # Merge the current branch into the target branch
```

Useful flags / shortcuts:

- `-y` / `--yes`: Skip approval prompts (scripting/automation)
- `-b <base>` / `--base`: Base branch for `-c` (defaults to the default branch)
- `-x <cmd>` / `--execute`: Run a command after switching (e.g. `-x claude`)
- Branch shortcuts: `^` (default branch), `-` (previous), `@` (current), `pr:{N}`, `mr:{N}`

**The commands and flags listed above are the COMPLETE wt vocabulary — do not invent others.** Every wt action goes through one of the listed subcommands (`switch`, `list`, `remove`, `merge`); there is no bare `wt <branch>` form and no short flags beyond those listed (`-y`, `-b`, `-x`). Flags attach to the subcommand, e.g. `wt switch -c -y <branch>`, never `wt -yqn <branch>`. Red flags — if you catch yourself typing any of these, STOP and use the listed form instead:

| Wrong (invented) | Right |
|------------------|-------|
| `wt -yqn <branch>` / `wt <branch>` | `wt switch -c <branch>` (add `-y` to skip prompts) |
| `wt -q` / `wt -n` (no such flags) | `wt switch -y` |
| `cd "$(wt ...)"` | just `wt switch <branch>` — the post-switch hook owns navigation |

If you are unsure whether a flag exists, prefer the plain `wt switch <branch>` / `wt switch -c <branch>` form rather than guessing — do NOT spelunk through `wt --help` mid-task.

**tmux model**: Session = Project, Window = Worktree
- One tmux session per repository (e.g., 'nix-config')
- One window per worktree/branch
- A `post-switch` tmux hook (in `~/.config/worktrunk/config.toml`) owns navigation:
  it switches to the matching window or creates one. `[switch] cd = false`, so the
  parent shell is intentionally left where it is — the hook is authoritative.

## Pull Requests

When creating PRs, assign to me:

```bash
gh pr create --assignee @me --title "..." --body "..."
```

## Git Commits

Git commit actions (staging, committing, etc.) are always allowed without asking for confirmation.

## Nerd Font Icons

When working with Nerd Font icons that fail due to Unicode rendering issues, don't keep retrying the literal Unicode character. Instead:

1. Use a variable for the icon
2. Add a comment hinting at the intended icon name (e.g., `# nerd: nf-md-folder`)
3. The user will set the correct Nerd Font glyph in the variable

## Shell Preference

I use fish shell, not bash. Provide shell commands in fish syntax.

## Shell Script Validation

**REQUIRED**: Always run `shellcheck` on shell scripts after creating or editing them.

```bash
shellcheck <script-path>
```

Fix all warnings and errors before considering the work complete.

## Effort Estimation

Give ranges (1-2 hours), not precise numbers or calendar dates. Scope what's included/excluded. Flag where human decisions block progress. Mention where AI accelerates the work.

## Design Principles

- **Design it twice** — sketch 2 approaches before committing to one.
- **Pull complexity downward** — implementers work harder so callers don't.
- **Define errors out of existence** — design APIs where the error can't occur, rather than detecting and handling it.

## Writing Code (lean by default)

Write the diff a careful senior engineer *on this codebase* would write — nothing extra.

- **Comments earn their place.** Only explain a non-obvious WHY (hidden constraint, invariant, workaround). Never restate what the code does, reference the task/PR/ticket, or name callers. In doubt, delete it.
- **Match the surrounding code** — naming, error handling, logging, structure. Edit like the file, not like greenfield.
- **Stay in scope.** Change only what the task needs — no drive-by reformatting, renames, or unrelated "improvements".
- **No speculative robustness.** No try/catch, null guards, or fallbacks for cases that can't occur on a trusted path — see "Define errors out of existence" above.
- **No escape hatches** to silence a checker (`as any`, `@ts-ignore`, `# type: ignore`) — fix the type or the call.
- **Flatten with early returns** instead of deep conditional nesting.
- **Delete, don't preserve.** When replacing code, remove the old version — no commented-out blocks, dead branches, or compat shims kept "just in case". Git history is the backup.
- **Clean up scaffolding** — strip debug prints, leftover logging, and placeholder TODOs you introduced before calling it done.
- **Verify unfamiliar APIs before use** — never guess that an import, method, or option exists.

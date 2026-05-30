# Global Claude Code Instructions

## Claude Code Settings Architecture

Settings are split into two layers. **Never mix them.**

| Layer | File | Owns | Writable |
|-------|------|------|----------|
| `settings.json` | `home/ai/claude-code/settings.json` (symlinked to `~/.claude/settings.json`) | permissions, plugins, theme, sandbox, mcpServers, preferences — everything that's plain JSON | Yes (third-party tools and UI can edit) |
| `--settings` overlay | Nix-generated via `nix-settings-json` in `home/ai/claude-code/default.nix` | hooks, statusLine — **only** keys that reference `/nix/store` paths | No (read-only, rebuilt by Nix) |

**Rules:**
- If a setting needs a nix store path → `--settings` overlay (default.nix)
- Everything else → `settings.json`
- Never duplicate keys across the two layers (`--settings` wins and silently shadows `settings.json`)
- Third-party tools (lazytmux, etc.) should modify `settings.json` — changes appear as git diffs
- `feedbackSurveyState` and other runtime-mutated keys live in `settings.json`; ignore the noise in diffs

## Bash Command Simplicity

**Prefer** simple, single commands that match `Bash(cmd *)` permission patterns cleanly.

- **Avoid `$()` and backticks** — use direct arguments instead (e.g., `git commit -m "message"`, not HEREDOC with `$(cat ...)`).
- **Avoid `&&` / `||` chaining** — prefer separate Bash tool calls for each command.
- **Avoid pipes `|`** — prefer dedicated tools (Grep, Glob, Read) or separate calls.

These are **not hard bans** — use compound syntax when genuinely needed (e.g., a subshell `(cd dir && build)`, or a pipe that can't be split). But default to simple commands first.

## Reading Code (skeleton-first)

For files larger than ~300 lines, **structure before content**: run `ast-grep` for signatures, invoke the `context-efficient-tools:code-structure` skill, or `Grep` for the symbol you actually care about — *before* a full `Read`. Pull in the full body of a region only once you know which region matters.

Why: loading whole files burns context and rarely helps; most edits touch one small slice. This is the Dirac CLI insight — harness behavior beats model choice on benchmarks like TerminalBench, and "skeleton-by-default reads" is the single biggest contributor.

Exceptions: short files (<300 lines), config files where every line matters, or genuine whole-file work (security review, top-to-bottom audit).

## New Work Workflow (factify-inc repos only)

**REQUIRED** for repos under the `factify-inc` GitHub org. Does NOT apply to personal repos.

Before implementing or planning any new work:

1. **Create a Linear ticket** (if one doesn't exist):
   - Follow the "Linear Ticket Creation" guidelines below
   - Get user confirmation before creating

2. **Create a git worktree** for the work:
   - Use the branch name from Linear (`Cmd+Shift+.` to copy)
   - Run: `wt switch -c <branch-name>` (worktrunk creates the branch + worktree and navigates there)

This ensures all work is tracked and isolated properly.

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

## Playwright Screenshot Configuration

**CRITICAL REQUIREMENT**: When using `mcp__playwright__browser_take_screenshot`:

- Default to `type: "png"` for UI screenshots — keeps Hebrew text, thin borders,
  and progress bars crisp, which is what you almost always want when debugging
  the UI.
- Use `type: "jpeg"` only when token cost clearly dominates (very large
  screenshots, many-image batches).
- Claude Vision supports `image/jpeg`, `image/png`, `image/gif`, and
  `image/webp`. AVIF and HEIC are NOT supported.

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

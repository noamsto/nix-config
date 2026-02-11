# Global Claude Code Instructions

## New Work Workflow (factify-inc repos only)

**REQUIRED** for repos under the `factify-inc` GitHub org. Does NOT apply to personal repos.

Before implementing or planning any new work:

1. **Create a Linear ticket** (if one doesn't exist):
   - Follow the "Linear Ticket Creation" guidelines below
   - Get user confirmation before creating

2. **Create a git worktree** for the work:
   - Use the branch name from Linear (`Cmd+Shift+.` to copy)
   - Run: `cd "$(wt -yq <branch-name>)"`

This ensures all work is tracked and isolated properly.

## Task Context Switching

When a new task is **unrelated** to current in-progress work and there are uncommitted changes:

1. Briefly note: "Uncommitted changes from [previous task] — committing first."
2. Commit the previous work with an appropriate message
3. Proceed with the new task

No confirmation needed — this is the default. User can say "don't commit" to override.

## Linear Data Display

**IMPORTANT**: When displaying Linear data, always format it readably:

### Issues
Show in a clear format with key fields visible:
```
[PL-123] Issue Title
Status: In Progress | Priority: High | Assignee: @name
Labels: bug, backend

Description:
[formatted description]
```

### Comments
Format with author, timestamp, and proper markdown:
```
@author (2 hours ago):
> Comment content here
> With proper formatting

  @replier (1 hour ago):
  > Nested reply indented
```

### Projects
Display with status and key metadata:
```
Project: Project Name
Status: In Progress | Lead: @name
Progress: 45% (9/20 issues)

Description:
[formatted description]
```

## Linear Ticket Creation

**IMPORTANT**: Before creating a Linear ticket, you MUST:

1. Display the complete ticket content in a formatted markdown block showing:
   - Title
   - Description (full markdown with proper formatting)
   - Labels/tags
   - Priority
   - Any other metadata
2. Wait for user confirmation before actually creating the ticket
3. This ensures the user can review and approve the formatting before submission

Example format to show:

```
Title: [Ticket Title]
Priority: [Priority Level]
Labels: [label1, label2]

Description:
[Full formatted description with markdown]
- Bullet points properly formatted
- Code blocks if needed
- Clear acceptance criteria
```

## Safe File Deletion

- **Always use `gtrash put` instead of `rm`** when deleting files. This sends files to the trash instead of permanently deleting them.
- **Before running destructive git commands** (`git checkout -- <file>`, `git restore`, `git reset --hard`, `git clean -f`, `git stash drop`, etc.):
  1. Committed work is recoverable via reflog — no extra steps needed
  2. **Uncommitted changes and untracked files** are NOT recoverable — run `gtrash put` on them before proceeding

## Pre-commit Hook Notes

- `golangci-lint` pre-commit hook now uses `scripts/golangci-lint-staged.sh` to run only on modules with staged changes
- This works correctly in both normal repos and git worktrees

## Playwright Screenshot Configuration

**CRITICAL REQUIREMENT**: When using `mcp__playwright__browser_take_screenshot`:

- You MUST ALWAYS set the `type` parameter to `"jpeg"`
- NEVER use PNG format
- Reason: Anthropic API requires JPEG format for image viewing
- This is NON-NEGOTIABLE - no exceptions

## ToonFormat Preference

**IMPORTANT**: When outputting structured data (especially arrays/tables), prefer **ToonFormat** over JSON for token efficiency.

ToonFormat provides 30-60% token savings compared to JSON and is more readable for structured data.

**When to use TOON:**

- Outputting arrays, tables, or lists of records
- Data-heavy responses with repeated structures
- Any structured data that would typically be JSON

**Format example:**

```toon
users[3]{id,name,role}:
 1,Alice,admin
 2,Bob,user
 3,Charlie,user
```

**Guidelines:**

- Use 2-space indentation for data rows
- Declare array length `[N]` and fields `{field1,field2}` in header
- Parse TOON format naturally when provided in user messages
- Only use JSON when specifically required by tools/APIs or when the data structure is deeply nested

**Note:** Internal tool calling (Read, Write, Bash, etc.) uses JSON as required by the API - this cannot be changed and is not what this preference affects. This is about the CONTENT of responses and data exchange.

## Git Worktrees

When creating or switching to git worktrees, use the `wt` command:

```bash
# Create/switch to worktree and cd to it (no window switch)
cd "$(wt -yqn <branch-name>)"
```

Flags:

- `-y` / `--yes`: Skip confirmation prompts
- `-q` / `--quiet`: Only output the worktree path (for scripting)
- `-n` / `--no-switch`: Skip all tmux operations (no window creation/switching)

**Model**: Session = Project, Window = Worktree
- One tmux session per repository (e.g., 'nix-config')
- One window per worktree/branch

This creates the worktree (if needed), switches to its tmux window, and outputs the path for cd.

## Pull Requests

When creating PRs, always create them as **drafts** initially:

```bash
gh pr create --draft --title "..." --body "..."
```

This allows for review before marking ready.

## Shell Preference

I use fish shell, not bash. Provide shell commands in fish syntax.

## Shell Script Validation

**REQUIRED**: Always run `shellcheck` on shell scripts after creating or editing them.

```bash
shellcheck <script-path>
```

Fix all warnings and errors before considering the work complete.

## Effort Estimation with AI Context

When asked about task sizing, provide **structured effort estimates** (not calendar timelines):

**Format:**
- **Implementation effort:** X-Y hours (what's included)
- **Not included:** reviews, deployment, edge cases, etc.
- **Human decisions needed:** architecture choices, UX, business logic
- **AI advantage:** [where AI accelerates work]

**Examples:**

✅ "Implementation: 1-2 hours (API changes, tests, basic docs). Not included: client SDK updates, production deployment."

✅ "Quick win: ~30 min to add the field and update handlers. You'll need to decide on validation rules first."

❌ "This will be done by tomorrow afternoon"

❌ "Exactly 3.5 hours of work"

**Rules:**
1. Ranges, not precision (1-2 hours, not 1.5 hours)
2. Scope what's included/excluded
3. Never promise calendar dates
4. Flag where human decisions block progress

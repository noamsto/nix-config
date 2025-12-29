# Global Claude Code Instructions

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
# Create/switch to worktree + move window + cd to it
cd "$(wt -ymq <branch-name>)"
```

Flags:
- `-y` / `--yes`: Skip confirmation prompts
- `-m` / `--move`: Move current tmux window to new session
- `-q` / `--quiet`: Only output the worktree path (for scripting)

This creates the worktree, creates a tmux session, moves the current window to it, and outputs the path for cd.

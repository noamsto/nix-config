---
name: work-tracking
description: Use before starting new work or opening a PR in a repo, when deciding between a Linear ticket (factify-inc) and a GitHub issue (personal repos), naming a branch, creating a repo with gh, handling an external contributor's report, or displaying Linear issues.
---

# Work tracking by repo org

Decide by the origin remote's org: `factify-inc` uses Linear; anything else (`noamsto`, etc.) uses GitHub issues. The worktree-first rule in the always-loaded conventions applies to both.

## factify-inc (Linear)

- Create a Linear ticket if none exists. Show the full title, description, labels, and priority as markdown and wait for confirmation before creating or writing any ticket.
- Use the branch name Linear generates, verbatim, as the `wt switch -c` branch. Never reshape it into `type/id-desc`.
- Ticket writes need explicit approval. Customer identifiers must never land in commits or PR bodies.
- Display issues, comments, and projects with author, timestamp, status, and labels visible; use blockquotes for nested comments.

## Personal repos (GitHub)

- Open an issue only for substantial work (new feature, multi-session effort, anything worth finding later): `gh issue create`, after user confirmation. Skip it for trivial fix/chore/docs/lockfile edits.
- Branch name: `type/id-desc` where `id` is the issue number and `type` is feat, fix, refactor, chore, or docs (e.g. `feat/213-id-seed-avatars`). One slash only. Without an issue, drop the id: `chore/bump-flake-lock`.
- After `gh repo create`, run `gh-repo-defaults <owner/repo>` (squash-only merges, delete branch on merge, auto-merge, Actions may open PRs). `gh-repo-defaults --check --all` reports drift across owned repos; `--all` without `--check` fixes it.
- The tooling (`gh`, `git`, `wt`, tmux) is identical on Linux and macOS; don't reach for OS-specific shortcuts.

### External reporters and contributors (personal repos only)

- Once the bug is confirmed against the code, reply on the issue with what was verified, the planned fix, and, if their suggested fix is wrong or incomplete, why. Never adopt a proposed fix without checking it against the code.
- Credit them in the PR body: `Reported by @handle in #N`.
- Commit trailer: `Reported-by: <handle> <https://github.com/<handle>>`; use `Co-authored-by:` only when their code landed.

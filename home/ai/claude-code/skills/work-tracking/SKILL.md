---
name: work-tracking
description: Use before starting new work or opening a PR in a repo, when deciding whether a GitHub issue is warranted, naming a branch, creating a repo with gh, or handling an external contributor's report.
---

# Work tracking

Work is tracked in GitHub issues. The worktree-first rule in the always-loaded conventions applies to every repo.

## GitHub issues and branches

- Open an issue only for substantial work (new feature, multi-session effort, anything worth finding later): `gh issue create`, after user confirmation. Skip it for trivial fix/chore/docs/lockfile edits.
- Branch name: `type/id-desc` where `id` is the issue number and `type` is feat, fix, refactor, chore, or docs (e.g. `feat/213-id-seed-avatars`). One slash only. Without an issue, drop the id: `chore/bump-flake-lock`.
- After `gh repo create`, run `gh-repo-defaults <owner/repo>` (squash-only merges, delete branch on merge, auto-merge, Actions may open PRs). `gh-repo-defaults --check --all` reports drift across owned repos; `--all` without `--check` fixes it.
- The tooling (`gh`, `git`, `wt`, tmux) is identical on Linux and macOS; don't reach for OS-specific shortcuts.

### External reporters and contributors

- Once the bug is confirmed against the code, reply on the issue with what was verified, the planned fix, and, if their suggested fix is wrong or incomplete, why. Never adopt a proposed fix without checking it against the code.
- Credit them in the PR body: `Reported by @handle in #N`.
- Commit trailer: `Reported-by: <handle> <https://github.com/<handle>>`; use `Co-authored-by:` only when their code landed.

---
description: "Commit staged changes then push — conventional commit + git push"
allowed-tools:
  - Bash(git status*)
  - Bash(git diff*)
  - Bash(git add*)
  - Bash(git commit*)
  - Bash(git push*)
  - Bash(git branch*)
  - Bash(git remote*)
---

Stage, commit, and push the current branch.

1. `git status` + `git diff` to understand what changed
2. `git add -u`
3. Write a `type(scope): description` commit message (≤50 chars subject)
4. `git commit -m "<message>"`
5. `git push` (with `-u origin <branch>` if the branch has no upstream yet)

No PR creation — push only. No confirmation needed.

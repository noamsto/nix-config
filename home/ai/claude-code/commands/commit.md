---
description: "Conventional commit — inspect diff, stage tracked files, commit"
allowed-tools:
  - Bash(git status*)
  - Bash(git diff*)
  - Bash(git add*)
  - Bash(git commit*)
---

Stage all tracked changes and commit with a conventional commit message.

1. `git status` + `git diff` to understand what changed
2. `git add -u` (tracked files only — never `git add .`)
3. Write a `type(scope): description` subject, ≤50 chars
4. `git commit -m "<message>"`

Types: feat, fix, chore, docs, refactor, test, perf. No co-authored-by, no body unless the why is non-obvious. No confirmation needed.

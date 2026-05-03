---
name: deslop
description: Use when reviewing a branch before committing or creating a PR. Checks the diff against main and removes AI-generated slop (unnecessary comments, defensive blocks, casts, style inconsistencies).
---

# Remove AI code slop

Check the diff against main and remove AI-generated slop introduced in the branch.

## Focus Areas

- Extra comments that are unnecessary or inconsistent with local style
- Defensive checks or try/catch blocks that are abnormal for trusted code paths
- Casts to `any` used only to bypass type issues
- Deeply nested code that should be simplified with early returns
- Inline imports in Python (move to top of file with other imports)
- Other patterns inconsistent with the file and surrounding codebase

## Guardrails

- Keep behavior unchanged unless fixing a clear bug.
- Prefer minimal, focused edits over broad rewrites.
- Keep the final summary concise (1-3 sentences).

## Process

1. Get the diff against main: `git diff main...HEAD`
2. Review each changed file for slop patterns
3. Remove identified slop while preserving legitimate changes
4. Report a 1-3 sentence summary of what was changed

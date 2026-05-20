---
name: deslop
description: Use when reviewing a branch before committing or creating a PR. Checks the diff against main and removes AI-generated slop (unnecessary comments, defensive blocks, casts, style inconsistencies, hallucinated APIs).
---

# Remove AI code slop

Check the diff against the branch base and remove AI-generated slop introduced in the branch.

## General Focus Areas

- Comments that restate the code, reference the task/PR, or name callers — delete them. Keep a comment only when the WHY is non-obvious (hidden constraint, subtle invariant, workaround).
- Defensive checks or try/catch blocks abnormal for trusted code paths in this codebase.
- Type-system workarounds used to bypass real type issues rather than fix them.
- Deeply nested code that should be flattened with early returns.
- Hallucinated APIs — verify any unfamiliar import, method, or config option actually exists in the dependency.
- Convention-blind code — compare naming, error handling, and logging against the surrounding file before keeping new patterns.
- Over-engineering — extra abstraction, options, or indirection beyond what the task requires.

## Language-Specific Patterns

### Go
- Redundant `if err != nil { return err }` that loses context — wrap with `fmt.Errorf("...: %w", err)` only when adding information; otherwise return as-is.
- `fmt.Errorf` re-wrapping that adds nothing new to the message.
- Leftover `context.TODO()` where a real context is in scope.
- `_ = result` discards left over from scaffolding.
- Trivial godoc that restates the signature.
- Unnecessary interfaces created for a single implementation.

### TypeScript
- `as any`, `as unknown as X`, or `@ts-ignore` used to silence the type checker instead of fixing the type.
- Optional chaining (`?.`) chained after a non-null guard already proved the value exists.
- `useEffect` doing work that derived state or an event handler would handle correctly.
- Leftover `console.log` / `console.debug`.
- JSDoc blocks that restate parameter names and types.
- `try/catch` that re-throws unchanged or swallows the error silently.

### Python
- Imports declared inline inside functions — move to the top of the file with the rest.
- `except Exception` blocks that swallow or re-raise unchanged.
- Type hints written as comments when real annotations are available.
- Docstrings that restate the signature.

## Guardrails

- Keep behavior unchanged unless fixing a clear bug.
- Prefer minimal, focused edits over broad rewrites.
- Don't reformat unrelated code.

## Process

1. Identify the branch base (usually `main`, but a stacked branch may have a different parent — check `git log --oneline -20` if unsure).
2. Get the diff: `git diff <base>...HEAD`
3. Review each changed file for the patterns above.
4. Remove identified slop while preserving legitimate changes.
5. **Self-audit pass:** re-read your edits and ask "what still looks obviously AI-generated?" Fix anything that stands out.
6. Report a 1–3 sentence summary of what was changed.

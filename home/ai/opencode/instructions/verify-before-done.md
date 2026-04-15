# Verification Before Completion

Before claiming ANY task is complete, you MUST verify your work with evidence.

## Required Steps

1. **Run the relevant check command** for the change type:
   - Nix changes: `nix flake check` or `nh home build .` or `nh os build .`
   - Code changes: run the build, linter, or type checker
   - Test changes: run the tests and confirm they pass
2. **Read back the changed files** to confirm the edit is correct
3. **Check for regressions** - if you changed shared code, verify callers still work

## Rules

- Do NOT claim success based on "the code looks right" — run it
- Do NOT say "done" without showing command output as evidence
- If a check fails, fix it and re-verify before reporting completion
- If you cannot run a verification command, say so explicitly instead of assuming success

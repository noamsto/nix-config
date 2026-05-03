---
name: staged-pre-commit-hooks
description: Use when creating module-aware pre-commit hooks in Go monorepos, or understanding why golangci-lint only runs on changed modules
---

# Staged Pre-commit Hooks

## Overview

Run linters/generators only on modules with staged changes. In a monorepo with many modules, running tools on everything is slow; smart hooks detect affected modules and run only there.

**Core principle:** Analyze staged files, map to workspace modules, run tool per affected module.

## Pattern

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Get staged files (excluding deletions)
STAGED_FILES=$(git diff --cached --name-only --diff-filter=d '*.go' || true)
[[ -z "$STAGED_FILES" ]] && exit 0

# 2. Get workspace modules from go.work
WORKSPACE_MODULES=$(go work edit -json | jq -r '.Use[].DiskPath' | sed 's|^\./||')

# 3. Map files to modules
declare -A AFFECTED_MODULES=()
while IFS= read -r file; do
    for module in $WORKSPACE_MODULES; do
        if [[ "$file" == "$module/"* ]]; then
            AFFECTED_MODULES["$module"]=1
            break
        fi
    done
done <<< "$STAGED_FILES"

# 4. Run tool per module
EXIT_CODE=0
for module in "${!AFFECTED_MODULES[@]}"; do
    echo "Processing $module..."
    (cd "$module" && your-tool-here) || EXIT_CODE=1
done

exit $EXIT_CODE
```

## Pre-commit Config

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: golangci-lint
        name: go-lint
        entry: scripts/golangci-lint-staged.sh
        language: script
        types: [go]
        pass_filenames: false  # Script handles file detection
```

**Key settings:**
- `language: script` - Run a shell script
- `types: [go]` - Only trigger on Go file changes
- `pass_filenames: false` - Script discovers files itself

## Why This Pattern?

| Approach | Time on 8-module monorepo |
|----------|---------------------------|
| `golangci-lint run ./...` | ~45s (all modules) |
| Module-aware staged | ~5-8s (1-2 modules) |

## Git Worktree Compatibility

The pattern works in worktrees because:
- `git diff --cached` works from any worktree
- `go work edit -json` reads from workspace root
- Relative paths resolve correctly

## Common Variations

### With Auto-fix

```bash
(cd "$module" && golangci-lint run --fix --new-from-rev=HEAD) || EXIT_CODE=1
```

### sqlc Generate

```bash
# scripts/sqlc-generate-staged.sh
STAGED_SQL=$(git diff --cached --name-only --diff-filter=d '*.sql' || true)
# ... same module detection pattern ...
for module in "${!AFFECTED_MODULES[@]}"; do
    (cd "$module" && sqlc generate) || EXIT_CODE=1
done
```

### Multiple File Types

```bash
STAGED_FILES=$(git diff --cached --name-only --diff-filter=d | grep -E '\.(go|sql)$' || true)
```

## Debugging

```bash
# Test module detection
go work edit -json | jq -r '.Use[].DiskPath'

# See what files are staged
git diff --cached --name-only

# Run hook manually
./scripts/golangci-lint-staged.sh
```

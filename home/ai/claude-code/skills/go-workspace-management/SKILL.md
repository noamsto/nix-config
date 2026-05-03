---
name: go-workspace-management
description: Use when working in a Go monorepo with multiple modules, understanding module boundaries, or troubleshooting dependency resolution between local modules
---

# Go Workspace Management

## Overview

Go workspaces (`go.work`) manage multiple modules in a monorepo. The workspace coordinates local modules so they can import each other without publishing.

**Core principle:** `go.work` tells Go "these modules live together locally; use local code, not published versions."

## Quick Reference

| File | Purpose |
|------|---------|
| `go.work` | Lists modules in workspace |
| `<module>/go.mod` | Module definition + dependencies |
| `replace` directives | Point to local paths for inter-module imports |

## Workspace Structure

```
mono/
├── go.work                    # Workspace root
├── api/                       # Main application
│   └── go.mod                 # module github.com/org/api
├── services/
│   ├── document/
│   │   └── go.mod             # module github.com/org/service/document
│   ├── identity/
│   │   └── go.mod             # module github.com/org/service/identity
│   └── common/
│       └── go.mod             # module github.com/org/service/common
├── gen/go/
│   └── go.mod                 # module github.com/org/mono/gen/go
└── testing/api/
    └── go.mod                 # module github.com/org/testing/api
```

## go.work File

```go
go 1.24.11

use (
    ./api
    ./gen/go
    ./services/common
    ./services/document
    ./services/email
    ./services/identity
    ./services/proc
    ./testing/api
)
```

## Inter-Module Dependencies

Modules import each other by module path, but `replace` directives point to local paths:

```go
// api/go.mod
module github.com/factify-inc/api

require (
    github.com/factify-inc/service/document v0.0.0-00010101000000-000000000000
    github.com/factify-inc/service/identity v0.0.0-00010101000000-000000000000
)

replace github.com/factify-inc/service/document => ../services/document
replace github.com/factify-inc/service/identity => ../services/identity
```

**Key insight:** The `v0.0.0-00010101000000-000000000000` version is a pseudo-version that Go uses when the module isn't published. The `replace` directive makes Go use local code.

## Common Operations

### Run Commands Across Workspace

```bash
# From workspace root
go build ./...          # Build all modules
go test ./...           # Test all modules
go generate ./...       # Run generators in all modules
```

### Run Command in Single Module

```bash
# Option 1: cd into module
cd api && go build ./...

# Option 2: Use GOWORK=off to isolate
GOWORK=off go build ./api/...

# Option 3: Specify module path
go test ./services/identity/...
```

### Add New Module to Workspace

1. Create module directory with `go.mod`:
   ```bash
   mkdir -p services/newservice
   cd services/newservice
   go mod init github.com/org/service/newservice
   ```

2. Add to `go.work`:
   ```go
   use (
       // ... existing modules
       ./services/newservice
   )
   ```

3. If other modules need to import it, add `replace` directives:
   ```go
   // In api/go.mod
   require github.com/org/service/newservice v0.0.0-00010101000000-000000000000
   replace github.com/org/service/newservice => ../services/newservice
   ```

## Dependency Layers

Structure modules to avoid circular dependencies:

```
┌─────────────────┐
│      api/       │  ← Main application, imports all services
├─────────────────┤
│ services/proc   │  ← Workers, imports document, common
├─────────────────┤
│ services/doc    │  ← Business logic
│ services/identity│
│ services/email  │
├─────────────────┤
│ services/common │  ← Shared utilities (no service imports)
├─────────────────┤
│    gen/go       │  ← Generated code (protobuf)
└─────────────────┘
```

**Rule:** Lower layers cannot import higher layers.

## Debugging

### Module Not Found

```
cannot find module providing package github.com/org/service/document
```

**Fix:** Check `go.work` includes the module, and `replace` directive exists in importing module.

### Version Mismatch

```
go.mod requires github.com/some/pkg v1.2.3
    but go.sum has v1.2.2
```

**Fix:**
```bash
go mod tidy           # In affected module
# Or workspace-wide:
go work sync          # Sync all modules
```

### Check Workspace Graph

```bash
go work edit -json    # Show workspace structure as JSON
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Missing `replace` directive | Add `replace github.com/org/module => ../path` |
| Module not in `go.work` | Add `./path/to/module` to `use` block |
| Circular import | Restructure: extract shared code to `common` |
| Using `GOWORK=off` accidentally | Remove from environment, or use intentionally |
| Running `go mod tidy` at root | Run in each module directory |

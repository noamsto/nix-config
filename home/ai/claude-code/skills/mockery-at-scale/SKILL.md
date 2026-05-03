---
name: mockery-at-scale
description: Use when generating mocks for Go interfaces, configuring mockery for a service, or understanding Mock* vs Fake* vs mock* naming conventions
---

# Mockery at Scale

## Overview

Mockery generates type-safe mock implementations from Go interfaces. Configuration lives in `.mockery.yaml` per module, invoked via `go generate`.

**Core principle:** Generated mocks auto-cleanup via `t.Cleanup()`. No manual `AssertExpectations(t)` needed.

## Quick Reference

| Command | Purpose |
|---------|---------|
| `go generate ./...` | Regenerate all mocks (from repo root) |
| `mockery` | Run mockery in current module |

| Naming | Type | When to Use |
|--------|------|-------------|
| `Mock*` | Generated (mockery) | Standard mocking, interface has many methods |
| `Fake*` | In-memory implementation | Need working impl for integration tests |
| `mock*` | Hand-written test double | Mock needs internal state, per-test customization |

## Configuration (.mockery.yaml)

Place in module root (e.g., `services/document/.mockery.yaml`):

```yaml
with-expecter: true               # Enables type-safe .EXPECT() methods
resolve-type-alias: false
disable-version-string: true
issue-845-fix: true
dir: "{{.InterfaceDir}}/mocks"    # Output next to interface
outpkg: mocks
mockname: "Mock{{.InterfaceName}}"
filename: "mock_{{.InterfaceName | snakecase}}.go"
packages:
  github.com/factify-inc/service/document/store:
    interfaces:
      Store:
      FormStore:
      DocumentStore:
  github.com/factify-inc/service/document/components:
    interfaces:
      CacheClient:
```

**Key settings:**
- `with-expecter: true` - Generates `.EXPECT()` for type-safe assertions
- `dir: "{{.InterfaceDir}}/mocks"` - Mocks live next to interfaces
- Package-level interface whitelisting - Only generate what you need

## Triggering Generation

Add `generate.go` in module root:

```go
package document

//go:generate mockery
```

Then run from repo root:
```bash
go generate ./...
```

## Using Mocks in Tests

### Basic Pattern

```go
func TestMyService(t *testing.T) {
    mockStore := mocks.NewMockFormStore(t)  // Auto-registers cleanup

    // Set up expectations
    mockStore.On("Get", ctx, "form-id").Return(&models.Form{ID: "form-id"}, nil)

    // Use mock
    service := NewService(mockStore)
    result, err := service.GetForm(ctx, "form-id")

    require.NoError(t, err)
    assert.Equal(t, "form-id", result.ID)
    // No AssertExpectations needed - automatic via t.Cleanup()
}
```

### Type-Safe EXPECT Pattern

With `with-expecter: true`:

```go
func TestWithExpect(t *testing.T) {
    mockStore := mocks.NewMockFormStore(t)

    // Type-safe: compiler catches wrong argument types
    mockStore.EXPECT().
        Get(mock.Anything, "form-id").
        Return(&models.Form{ID: "form-id"}, nil)

    service := NewService(mockStore)
    // ...
}
```

### Flexible Matching

```go
// Match any context
mockStore.On("Create", mock.Anything, mock.MatchedBy(func(f *models.Form) bool {
    return f.DocumentID == "doc-123"
})).Return(&models.Form{ID: "created"}, nil)

// Match any arguments
mockStore.On("Delete", mock.Anything, mock.Anything).Return(nil)
```

### Table-Driven Tests

```go
func TestShareLink(t *testing.T) {
    tests := []struct {
        name      string
        setupMock func(*mocks.MockShareLinkStore)
        wantErr   bool
    }{
        {
            name: "success",
            setupMock: func(m *mocks.MockShareLinkStore) {
                m.On("Create", mock.Anything, mock.Anything).
                    Return(&models.ShareLink{ID: "link-1"}, nil)
            },
            wantErr: false,
        },
        {
            name: "store_error",
            setupMock: func(m *mocks.MockShareLinkStore) {
                m.On("Create", mock.Anything, mock.Anything).
                    Return(nil, errors.New("db error"))
            },
            wantErr: true,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            mockStore := mocks.NewMockShareLinkStore(t)
            tt.setupMock(mockStore)

            service := NewService(mockStore)
            _, err := service.Create(ctx, &models.ShareLink{})

            if tt.wantErr {
                require.Error(t, err)
            } else {
                require.NoError(t, err)
            }
        })
    }
}
```

## When to Use Each Approach

| Approach | Use When |
|----------|----------|
| `Mock*` (generated) | Interface has many methods, only testing a few |
| `mock*` (hand-written) | Mock needs internal state (maps, slices), per-test customization |
| `Fake*` (in-memory impl) | Integration tests need realistic data behavior |

## Adding a New Interface to Mock

1. Add interface to `.mockery.yaml`:
   ```yaml
   packages:
     github.com/your/package:
       interfaces:
         NewInterface:
   ```

2. Regenerate:
   ```bash
   go generate ./...
   ```

3. Import and use:
   ```go
   import "github.com/your/package/mocks"

   mockNew := mocks.NewMockNewInterface(t)
   ```

## Import Cycle Prevention

If interface returns types from its own package, the generated mock creates an import cycle.

**Fix:** Move the returned type to a shared `models` package:

```go
// Before: components/interface.go
type Processor interface {
    Process(ctx context.Context) (*ProcessingResult, error)  // ProcessingResult in same package
}

// After: Move ProcessingResult to models/processing.go
// Then import models in components/interface.go
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Editing generated mock files | Never edit - regenerate instead |
| Manual `AssertExpectations(t)` | Not needed with `NewMock*(t)` |
| Forgetting `mock.Anything` for context | Use `mock.Anything` for `ctx` parameters |
| Not whitelisting interface | Add to `.mockery.yaml` packages section |

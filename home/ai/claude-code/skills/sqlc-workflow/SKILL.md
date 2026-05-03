---
name: sqlc-workflow
description: Use when adding database queries to Go services, setting up sqlc in a new service, or understanding the SQL → Go code generation pipeline
---

# sqlc Workflow

## Overview

sqlc generates type-safe Go code from SQL queries. The workflow is:

```
queries/*.sql → sqlc generate → data/sqlc/*.go → mappers.go → store implementation
```

**Core principle:** Write SQL, get type-safe Go. No runtime reflection, compile-time safety.

## When to Use

- Adding new database queries to a service
- Setting up sqlc in a new Go service
- Understanding why generated code looks the way it does
- Debugging type mismatches between SQL and Go

## Quick Reference

| File | Purpose |
|------|---------|
| `sqlc.yaml` | Configuration: package name, type overrides |
| `queries/*.sql` | SQL with `-- name: FuncName :one/:many/:exec` annotations |
| `data/sqlc/querier.go` | Generated interface (mockable) |
| `data/sqlc/models.go` | Generated structs from schema |
| `data/sqlc/*.sql.go` | Generated query implementations |
| `data/postgres/mappers.go` | sqlc types → domain models |

## Query Annotations

```sql
-- name: GetUser :one
SELECT id, name, email FROM users WHERE id = $1;

-- name: ListUsers :many
SELECT id, name, email FROM users WHERE org_id = $1;

-- name: CreateUser :one
INSERT INTO users (id, name, email) VALUES ($1, $2, $3)
RETURNING id, name, email, created_at;

-- name: DeleteUser :exec
DELETE FROM users WHERE id = $1;

-- name: UpdateUserName :execrows
UPDATE users SET name = $2 WHERE id = $1;
```

| Annotation | Returns | Use When |
|------------|---------|----------|
| `:one` | Single struct | SELECT expecting one row |
| `:many` | Slice of structs | SELECT expecting multiple rows |
| `:exec` | `error` only | DELETE, UPDATE (don't need count) |
| `:execrows` | `int64, error` | UPDATE/DELETE when you need affected count |

## Configuration (sqlc.yaml)

```yaml
version: "2"
sql:
  - engine: "postgresql"
    queries: "./queries"
    schema: "./schema/sql"
    gen:
      go:
        package: "sqlcgen"
        out: "./data/sqlc"
        sql_package: "pgx/v5"
        emit_json_tags: true
        emit_interface: true              # Creates Querier interface
        emit_pointers_for_null_types: true
        json_tags_case_style: "snake"
        overrides:
          # UUID as string (matches protobuf, avoids conversions)
          - db_type: "uuid"
            go_type: "string"
          - db_type: "uuid"
            nullable: true
            go_type:
              type: "string"
              pointer: true
          # timestamptz as time.Time (not pgtype.Timestamptz)
          - db_type: "timestamptz"
            go_type:
              import: "time"
              type: "Time"
          - db_type: "timestamptz"
            nullable: true
            go_type:
              import: "time"
              pointer: true
              type: "Time"
```

**Key settings:**
- `emit_interface: true` - Generates `Querier` interface for mocking
- `sql_package: "pgx/v5"` - Use pgx driver (not database/sql)
- UUID → string overrides - Matches protobuf, zero conversions at API boundary

## Mapper Pattern

sqlc generates types directly from SQL. Domain models differ:

| sqlc | Domain Model | Reason |
|------|--------------|--------|
| `*string` for NULL | `string` (empty = null) | Simpler API |
| `ProfileImageUrl` | `ProfileImageURL` | Go naming conventions |
| Generated struct | Domain struct | Computed fields, validation |

**Mapper file** (`data/postgres/mappers.go`):

```go
// Helper functions
func ptrToString(s *string) string {
    if s == nil {
        return ""
    }
    return *s
}

func stringToPtr(s string) *string {
    if s == "" {
        return nil
    }
    return &s
}

// Mapper function
func toModelUser(u sqlcgen.User) *models.User {
    return &models.User{
        ID:              u.ID,
        DisplayName:     u.DisplayName,
        GivenName:       ptrToString(u.GivenName),
        ProfileImageURL: ptrToString(u.ProfileImageUrl), // Fix casing
        CreatedAt:       u.CreatedAt,
    }
}
```

## Store Implementation

```go
type PostgresStore struct {
    DB      *pgxpool.Pool
    queries *sqlcgen.Queries
}

func NewStore(db *pgxpool.Pool) *PostgresStore {
    return &PostgresStore{
        DB:      db,
        queries: sqlcgen.New(db),
    }
}

func (s *PostgresStore) GetUser(ctx context.Context, id string) (*models.User, error) {
    u, err := s.queries.GetUser(ctx, id)
    if errors.Is(err, pgx.ErrNoRows) {
        return nil, store.NewNotFoundError("user")
    } else if err != nil {
        return nil, store.NewInternalError("failed to get user", err)
    }
    return toModelUser(u), nil
}
```

**Transactions:**
```go
tx, err := s.DB.Begin(ctx)
if err != nil { return err }
defer tx.Rollback(ctx)

qtx := s.queries.WithTx(tx)
// Use qtx for all operations in transaction

return tx.Commit(ctx)
```

## Commands

```bash
# Generate code
sqlc generate

# Or via justfile
just sqlc-gen

# After schema changes: migrate then regenerate
just db-regen  # runs: migrate-apply sqlc-gen
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Editing generated files | Never edit `data/sqlc/*.go` - regenerate instead |
| Missing RETURNING clause | `:one` queries need RETURNING to get data back |
| Wrong annotation | `:one` for single row, `:many` for multiple |
| Forgetting mappers | Always convert sqlc types → domain models |
| Array parameters | Use `$1::uuid[]` not `$1` for slice params |

## Adding a New Query

1. Add SQL to `queries/<entity>.sql` with annotation
2. Run `sqlc generate` (or `just sqlc-gen`)
3. Add mapper if new type (in `data/postgres/mappers.go`)
4. Add store method using generated query + mapper
5. Add interface method to store interface

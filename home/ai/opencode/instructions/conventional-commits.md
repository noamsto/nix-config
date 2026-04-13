# Conventional Commits Guidelines

When creating git commits, ALWAYS use Conventional Commits format.

## Format

```
<type>(<optional-scope>): <short summary>

[optional body]

[optional footer(s)]
```

## Types (MUST use one of these)

- **feat**: A new feature
- **fix**: A bug fix
- **docs**: Documentation only changes
- **style**: Code style changes (formatting, semicolons, etc; no code change)
- **refactor**: Code change that neither fixes a bug nor adds a feature
- **perf**: Performance improvement
- **test**: Adding or correcting tests
- **build**: Changes to build system, dependencies, or CI/CD
- **chore**: Maintenance tasks (dependency updates, config changes)
- **ci**: CI/CD configuration changes
- **revert**: Reverting a previous commit

## Rules

1. **Type is required** - Must be one of the types listed above
2. **Scope is optional** - Use lowercase, hyphenated (e.g., `auth`, `ui/login`)
3. **Summary rules**:
   - Use imperative mood ("add" not "added" or "adds")
   - Start lowercase
   - No period at the end
   - Keep under 50 characters for the first line
4. **Body rules**:
   - Separate from summary with blank line
   - Wrap at 72 characters
   - Explain WHAT and WHY, not HOW
5. **Breaking changes**: Add `BREAKING CHANGE: <description>` in footer

## Examples

```
feat(auth): add OAuth2 login support

Implement Google and GitHub OAuth2 providers.
- Add passportjs configuration
- Create auth middleware
- Update user model for OAuth fields
```

```
fix(api): resolve null pointer in user validation

Check for undefined user object before accessing properties.
Fixes #123
```

```
refactor(db): simplify query builder logic

Consolidate duplicate query patterns into shared utility.
No functional changes.
```

```
chore(deps): update typescript to 5.4.0

Update devDependencies for latest type improvements.
```

## Commit Process

When committing:
1. Analyze the staged changes
2. Determine the primary type
3. Identify appropriate scope (if any)
4. Write concise summary in imperative mood
5. Add body explaining what changed and why (if non-trivial)
6. Reference issues in footer with `Fixes #XXX` or `Closes #XXX`

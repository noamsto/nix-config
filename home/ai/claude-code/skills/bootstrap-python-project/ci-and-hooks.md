# CI and hooks for a uv Python project

Used by `bootstrap-python-project` step 6. For Go/Rust CI timing patterns and the `git-hooks-nix` alternative, see the `bootstrap-nix-repo` skill.

## prek hooks

prek runs the pre-commit config format. Hooks are `repo: local` with `uv run` entries, so they work for contributors without Nix and use the versions from `uv.lock`. `git-hooks-nix` is not used: it needs Nix and generates its own config.

`.pre-commit-config.yaml` (committed, hand-written):

```yaml
repos:
  - repo: local
    hooks:
      - id: ruff-check
        name: ruff check
        entry: uv run ruff check --fix
        language: system
        types: [python]
      - id: ruff-format
        name: ruff format
        entry: uv run ruff format
        language: system
        types: [python]
      - id: pyrefly
        name: pyrefly check
        entry: uv run pyrefly check
        language: system
        types: [python]
        pass_filenames: false
```

Install once per clone with `uv run prek install`. Observed behaviour:

- A failing commit (unused import plus `x: int = "s"`): `ruff check` fails with `files were modified by this hook` (it fixed the import), and `pyrefly check` fails with `ERROR ... is not assignable to int [bad-assignment]`. No commit is created. After fixing, `git add` and commit again.
- A clean commit passes all three hooks.
- A commit touching only non-Python files skips all three (`no files to check`).

## GitHub Actions

`.github/workflows/ci.yml`:

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  check:
    name: check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: astral-sh/setup-uv@v10.3.3
        with:
          enable-cache: true
      - run: uv sync --locked
      - run: uv run ruff check
      - run: uv run ruff format --check
      - run: uv run pyrefly check
      - run: uv run pytest
```

- CI uses `uv sync --locked` (fail on a stale lock); the local `.envrc` uses plain `uv sync` so it can refresh the lock.
- CI runs without Nix: `setup-uv` installs uv, and uv downloads the interpreter on the runner, pinned by `.python-version`.
- The `name: check` on the job stays fixed so required status checks keep matching.
- The workflow file was written from the verified scratch project but not executed on GitHub Actions; the pinned action versions were resolved via `gh api` (setup-uv v10.3.3, checkout v7.0.1).

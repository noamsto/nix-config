---
name: bootstrap-python-project
description: Use when starting a new Python project repo that needs uv, a Nix devShell, direnv, ruff, pyrefly, pytest, prek or GitHub Actions, following Noam's conventions, or when numpy/pandas/grpcio wheels fail with libstdc++.so.6 or libz.so.1 import errors on NixOS.
---

# Bootstrap a Python Project

## Overview

Python projects use **uv for dependencies, Nix only for the shell**: the flake supplies `uv`, the interpreter and the system libraries that wheels link against; `uv` owns `pyproject.toml`, `uv.lock` and `.venv`. Packaging through Nix is out of scope here (see uv2nix / pyproject-nix when a Nix build is needed). For flake-parts conventions, treefmt (nix files only), Nix CI patterns and the `git add` gotcha, follow the `bootstrap-nix-repo` skill; hooks use prek, not its git-hooks-nix (see `ci-and-hooks.md`). This skill covers only what differs for Python.

## Canonical stack

| Concern | Choice | Notes |
|---|---|---|
| Flake framework | `flake-parts` | inline `perSystem`, same as `bootstrap-nix-repo`; no devenv |
| Dependencies | `uv` | `uv add`, `uv.lock` committed |
| Interpreter | Nix `python314` | `UV_PYTHON` points at it; `UV_PYTHON_DOWNLOADS=never` |
| Build backend | `uv_build` | `src/<pkg>/` layout |
| Lint + format | `ruff` | uv dev group, not treefmt; needs nix-ld on NixOS (see flake notes) |
| Type check + LSP | `pyrefly` | uv dev group; fallback `basedpyright` (most conformant, slower, needs node) when pyrefly misreports a library or pattern; `ty` is beta (0.0.x), not yet recommended |
| Tests | `pytest` | `tests/` |
| Pre-commit | `prek` | uv dev group, committed `.pre-commit-config.yaml` |
| CI | GitHub Actions + `astral-sh/setup-uv` | see `ci-and-hooks.md` |
| direnv | `.envrc` runs `use flake`, then `uv sync` | |

## Steps

1. `git init` if the repo is new. Create the files below (`flake.nix`, `.envrc`, `.gitignore`, `.python-version`, `pyproject.toml`), plus `src/<pkg>/__init__.py` (`"""<pkg>."""`; `<pkg>` is the project `<name>` with `-` as `_`) and `tests/test_smoke.py`:
   ```python
   import <pkg>


   def test_import() -> None:
       assert <pkg>.__doc__
   ```
2. `git add -A`: **untracked files are invisible to flakes**.
3. `direnv allow` (or `nix develop`). The first entry runs `uv sync`, which creates `.venv` and `uv.lock`.
4. Add runtime dependencies with `uv add <dep>...`; the dev tools are already in `[dependency-groups]`. Done when `direnv exec . python -c "import <dep>"` succeeds.
5. Run the checks through `uv run`: `ruff check`, `ruff format --check`, `pyrefly check`, `pytest`. On NixOS, first `test -e /lib64/ld-linux-x86-64.so.2` (`/lib/ld-linux-aarch64.so.1` on aarch64); if it fails, the host needs `programs.nix-ld.enable = true` (see the flake notes). Done when all four pass.
6. Read [`ci-and-hooks.md`](ci-and-hooks.md) and create `.pre-commit-config.yaml` and `.github/workflows/ci.yml` from it.
7. `uv run prek install`, then `git add -A` and commit from inside the devShell (the hooks call `uv run`): `uv.lock` and `flake.lock` are committed with the code.

## flake.nix

```nix
{
  description = "<name>";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];

      perSystem = {pkgs, lib, ...}: {
        devShells.default = pkgs.mkShell ({
            packages = [pkgs.uv];
            UV_PYTHON = "${pkgs.python314}/bin/python";
            UV_PYTHON_DOWNLOADS = "never";
          }
          // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
            # Wheels link libstdc++/libz from the system; add project libs here, e.g. pkgs.libGL
            LD_LIBRARY_PATH = lib.makeLibraryPath [pkgs.stdenv.cc.cc.lib pkgs.zlib];
          });
      };
    };
}
```

- **flake-parts over devenv.** The devShell is ~15 lines; devenv adds an input, eval cost and a second DSL, and buys nothing here.
- **`UV_PYTHON` plus `UV_PYTHON_DOWNLOADS=never`; no Python in `packages`.** `.venv` links to the Nix interpreter, and uv never fetches a managed one. A downloaded CPython on NixOS needs `programs.nix-ld` to run at all. An interpreter in `mkShell.packages` makes nixpkgs' setup hook export `PYTHONPATH=/nix/store/...-python3.../site-packages`, which leaks into the venv interpreter (pyrefly warns); `UV_PYTHON` alone suffices.
- **`python314`, not `python3`.** An explicit version keeps a `nix flake update` from moving the project to a new default.
- **`LD_LIBRARY_PATH` from `lib.makeLibraryPath`.** numpy, pandas and grpcio need exactly `stdenv.cc.cc.lib` (libstdc++) and `zlib`; nothing else was needed. The shell supplies them, so Python extension imports work with or without nix-ld. Add a project library to the list (`pkgs.libGL`). The Linux-only guard keeps macOS untouched. Use `stdenv.hostPlatform.isLinux`; `stdenv.isLinux` is deprecated.
- **nix-ld is a NixOS prerequisite for the uv-managed CLI tools.** ruff, pyrefly and prek install from PyPI as ELF executables with the FHS loader (`/lib64/ld-linux-x86-64.so.2` on x86_64, `/lib/ld-linux-aarch64.so.1` on aarch64), which on NixOS exists only through `programs.nix-ld`; `LD_LIBRARY_PATH` does not help. Non-NixOS Linux and macOS are unaffected. Keep the tools uv-locked; nixpkgs copies would drift from `uv.lock`.
- **Source builds.** `LD_LIBRARY_PATH` covers runtime libraries only. A package with no wheel for the platform (e.g. `psycopg2` without `-binary`) builds from its sdist: add `pkgs.pkg-config` and the library (its `dev` output provides the headers) to `packages`; `mkShell` already provides a C compiler.
- **Interpreter changes.** `.venv/bin/python` links into the Nix store. Observed: when `UV_PYTHON` moves to another store path of the same minor (`nix flake update`), `uv sync` recreates the venv and reinstalls by itself. Editing the `python3xx` attribute to a minor outside `requires-python` makes `uv sync` fail: bump `requires-python` and `.python-version` together. nix-direnv's gcroot keeps the devShell's interpreter alive; a venv outlives it only until a GC after the shell changes, so a dangling `.venv/bin/python` needs `rm -rf .venv` and `uv sync`.

## .envrc

```bash
if has nix; then
  use flake
fi
# Determinate Nix (macOS) lives in /nix/var/nix/profiles/default/bin and is added
# to PATH only by login-shell path_helper, which a devshell's PATH rebuild drops.
[ "$(uname)" = Darwin ] && PATH_add /nix/var/nix/profiles/default/bin
# After `use flake`: nix-direnv reads DIRENV_WATCHES, so earlier placement re-evaluates the devShell.
watch_file pyproject.toml uv.lock
uv sync
PATH_add .venv/bin
export VIRTUAL_ENV="$PWD/.venv"
```

- **Plain `uv sync`.** `--locked` fails on a missing or stale `uv.lock` (first entry, hand-edited `pyproject.toml`); plain `uv sync` creates or refreshes the lock and takes ~0.07s when current. direnv 2.38 has no `layout uv`, so the venv step is written by hand.
- **`watch_file` goes after `use flake`.**
- Not exercised: `.envrc` through direnv on a host without `nix` on PATH (the `has nix` guard). The no-Nix path below is plain `uv sync`.

## .gitignore

```
result
result-*
.direnv
.claude/settings.local.json
.venv
__pycache__
.pytest_cache
.ruff_cache
```

## .python-version

```
3.14
```

Pins the interpreter family for contributors without Nix. On Nix, `UV_PYTHON` takes precedence, so the file is harmless there.

## pyproject.toml

```toml
[project]
name = "<name>"
version = "0.1.0"
requires-python = ">=3.14"
dependencies = []

[build-system]
requires = ["uv_build>=0.13.4,<0.14"]
build-backend = "uv_build"

[dependency-groups]
dev = ["pytest", "ruff", "pyrefly", "prek"]

[tool.ruff]
line-length = 100
target-version = "py314"

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B", "SIM"]

[tool.pytest.ini_options]
testpaths = ["tests"]

[tool.pyrefly]
project-includes = ["src", "tests"]
```

`dependencies` fills through `uv add`. `uv_build` expects the package at `src/<pkg>/`. `pyrefly init` emits only `project-includes`; the other `[tool.pyrefly]` keys are not needed here.

Tooling lives in uv dev groups, not treefmt or git-hooks-nix, so a contributor with only uv gets identical versions. If the repo also adds treefmt for nix files, leave ruff out of it.

## No-Nix path

A contributor with only uv runs `uv sync` in a clone (`uv.lock` is committed). Without `.python-version`, uv downloads the newest CPython matching `requires-python` (observed 3.15 for `>=3.14`); with it, 3.14. macOS and other Linux work as-is. On NixOS this path needs `programs.nix-ld` enabled, for the same reason as the devShell path.

## Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Forgot `git add -A` | flake cannot see `flake.nix`; `path does not exist` | `git add -A` before `direnv allow` / `nix develop` |
| `LD_LIBRARY_PATH` missing `stdenv.cc.cc.lib` | `ImportError: libstdc++.so.6: cannot open shared object file` (numpy "Importing the numpy C-extensions failed") | add `pkgs.stdenv.cc.cc.lib` to `lib.makeLibraryPath` |
| `LD_LIBRARY_PATH` missing `zlib` | `libz.so.1: cannot open shared object file` | add `pkgs.zlib` |
| uv downloaded an interpreter on NixOS without nix-ld | managed CPython will not run | keep `UV_PYTHON` + `UV_PYTHON_DOWNLOADS=never` in the devShell, or enable `programs.nix-ld` |
| `nix develop -c python` | `python: command not found` (no interpreter in the devShell; `.envrc` does not apply) | `.venv/bin/python`, or `direnv exec . python`; keep Python out of `packages` |
| `watch_file` placed before `use flake` | devShell re-evaluates on every `pyproject.toml` edit | place it after `use flake` |
| First commit with the ruff `--fix` hook | `files were modified by this hook` | `git add` the fixed files and commit again |
| pyrefly prints `WARN PYTHONPATH environment variable is set to /nix/store/...` | warning only; 0 errors | the interpreter is in `mkShell.packages`; remove it and rely on `UV_PYTHON` |
| Running `ruff`, `pyrefly` or `prek` on NixOS without `programs.nix-ld` | `Could not start dynamically linked executable`, or `cannot execute: required file not found` / `No such file or directory` (no FHS loader) | enable `programs.nix-ld`; Python imports are unaffected |
| `stdenv.isLinux` in the flake | eval warning `stdenv.isLinux is deprecated, use stdenv.hostPlatform.isLinux instead` | use `stdenv.hostPlatform.isLinux` |

## When NOT to use

- The repo already has a working flake: edit it.
- Non-Python repos (Go, Rust, Node, generic): `bootstrap-nix-repo`.
- This `nix-config` repo: its own project skills.
- A Python package destined for nixpkgs: `nix-package-authoring` (inside nix-config).

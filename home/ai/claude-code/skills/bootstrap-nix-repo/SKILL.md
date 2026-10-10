---
name: bootstrap-nix-repo
description: Use when starting a new project repo (Go, Rust, Node, generic) that needs a Nix flake, direnv, devShell, treefmt and pre-commit, following Noam's conventions.
---

# Bootstrap a Nix Repo

## Overview

New project repos follow one house pattern: **flake-parts, inline `perSystem`, all four systems, `use flake` direnv**. There are no `flake-modules/` directories in project repos — that split is only for `nix-config` itself. Pick the package builder by language, keep everything else identical.

## Canonical stack

| Concern | Choice | Notes |
|---|---|---|
| Flake framework | `flake-parts` | inline `perSystem`, never a `flake-modules/` dir |
| Systems | `["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"]` | trim to linux-only only if the project can't be macOS |
| nixpkgs | `github:NixOS/nixpkgs/nixos-unstable` | always unstable |
| Go | `pkgs.buildGoModule` | inline in `perSystem` |
| Rust | `crane` + `rust-overlay` | `craneLib.buildPackage` / `craneLib.devShell` |
| Node/TS | `pkgs.buildNpmPackage` or devshell-only | `nodejs_22` + `pnpm` |
| Formatting | `treefmt-nix` flakeModule | add when the repo has code worth formatting |
| Pre-commit | `git-hooks-nix` flakeModule | add only when you want hooks; it generates `.pre-commit-config.yaml` |
| direnv | `.envrc` → `use flake` | enhanced variant only if `.env.local` is needed |

## Steps

1. Create the files below (`flake.nix`, `.envrc`, `.gitignore`).
2. `git add -A` — **untracked files are invisible to flakes**; this is non-negotiable, not just for committing. This covers your source too: Go needs `go.mod` (+ `go.sum` once there are deps) staged; Rust needs `Cargo.toml`/`Cargo.lock`. (This is the flake git-tracking gotcha from the nix-config `nix-rebuild` skill.)
3. `direnv allow` (or `nix develop`).
4. Set the dependency hash, then `nix build`:
   - **Go, no dependencies (stdlib only):** leave `vendorHash = null` — no hash step, it just builds.
   - **Go, has dependencies / Rust:** set `vendorHash`/`cargoHash` to `lib.fakeHash`, run `nix build`, copy the real hash from the `got:` line of the mismatch error, paste it back, rebuild.

## Base flake — Go (most common)

```nix
{
  description = "<one-line description>";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];

      perSystem = {pkgs, ...}: {
        packages.default = pkgs.buildGoModule {
          pname = "<name>";
          version = "0.1.0";
          src = ./.;
          vendorHash = null; # null = stdlib only; else "sha256-..." from build error
          ldflags = ["-s" "-w"];
          meta = {
            description = "<one-line description>";
            mainProgram = "<name>";
          };
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.go
            pkgs.gopls
            pkgs.gotools
            pkgs.golangci-lint
          ];
        };
      };
    };
}
```

## Variant — Rust (crane)

Add inputs `crane.url = "github:ipetkov/crane";` and `rust-overlay` (with `inputs.nixpkgs.follows = "nixpkgs"`), then (this block assumes the treefmt section below is also added — that's where `config.treefmt.build.wrapper` comes from; drop it from `packages` if you skip treefmt):

```nix
perSystem = {pkgs, system, config, ...}: let
  rustPkgs = import inputs.nixpkgs {inherit system; overlays = [(import inputs.rust-overlay)];};
  craneLib = (inputs.crane.mkLib pkgs).overrideToolchain rustPkgs.rust-bin.stable.latest.default;
  src = craneLib.cleanCargoSource ./.;
  commonArgs = {inherit src; pname = "<name>"; version = "0.1.0"; strictDeps = true;};
  cargoArtifacts = craneLib.buildDepsOnly commonArgs;
  pkg = craneLib.buildPackage (commonArgs // {inherit cargoArtifacts;});
in {
  packages.default = pkg;
  devShells.default = craneLib.devShell {
    packages = [pkgs.cargo-watch config.treefmt.build.wrapper];
    inputsFrom = [pkg];
  };
};
```

## Variant — Node/TS (devshell-only)

```nix
perSystem = {pkgs, ...}: {
  devShells.default = pkgs.mkShell {
    packages = with pkgs; [nodejs_22 pnpm typescript];
    shellHook = ''echo "dev shell ready — node $(node -v), pnpm $(pnpm -v)"'';
  };
};
```

## Add formatting (treefmt-nix)

Add input `treefmt-nix` (follows nixpkgs), then `imports = [inputs.treefmt-nix.flakeModule];` and inside `perSystem`:

```nix
treefmt = {
  projectRootFile = "flake.nix";
  programs = {
    alejandra.enable = true;   # nix
    gofmt.enable = true;       # or rustfmt / prettier per language
  };
};
```

Wire `config.treefmt.build.wrapper` into the devShell `packages` so `treefmt` is on PATH.

## Add pre-commit (git-hooks-nix)

Add input `git-hooks-nix.url = "github:cachix/git-hooks.nix";` (follows nixpkgs), `imports = [inputs.git-hooks-nix.flakeModule];`, then in `perSystem`:

```nix
pre-commit.settings.hooks = {
  statix.enable = true;
  deadnix.enable = true;
  alejandra.enable = true;
  typos.enable = true;
  check-merge-conflicts.enable = true;
  trim-trailing-whitespace.enable = true;
};

devShells.default = pkgs.mkShell {
  inherit (config.pre-commit) shellHook;
  packages = config.pre-commit.settings.enabledPackages ++ [/* lang tools */];
};
```

`git-hooks-nix` **generates** `.pre-commit-config.yaml` — never edit it by hand; add it to `.gitignore`.

## Supporting files

**`.envrc`** (default):
```bash
use flake
# Determinate Nix (macOS) lives in /nix/var/nix/profiles/default/bin and is added
# to PATH only by login-shell path_helper, which a devshell's PATH rebuild drops.
# Re-add it after `use flake` so `nix` resolves inside the devshell. No-op on Linux.
[ "$(uname)" = Darwin ] && PATH_add /nix/var/nix/profiles/default/bin
```

The `PATH_add` must come **after** `use flake`: direnv runs the global `direnvrc` before `.envrc`, and `use flake` rebuilds `PATH` from the devshell's inputs (which omit Determinate's `nix`), so anything earlier gets overwritten.

Enhanced variant (only when the repo reads `.env.local`): `dotenv .env.local` guard + pinned `nix-direnv` `source_url` + `watch_file flake.nix flake.lock` + `use flake . --impure`.

**`.gitignore`** (base; add language outputs):
```
result
result-*
.direnv
.claude/settings.local.json
```
- Go: also `/bin/` and the built binary name (your `pname`)
- Rust: also `/target`
- Node: also `node_modules/`, `dist/`, `.env`
- With git-hooks: also `.pre-commit-config.yaml`

## Exporting a module (when the tool ships HM/NixOS config)

Put it at the **flake level**, defaulting the package to the flake's own build so it matches the binary cache:

```nix
flake.homeManagerModules.default = {pkgs, ...} @ args:
  import ./modules/home-manager.nix (args // {
    pkg = inputs.self.packages.${pkgs.system}.default;
  });
# or: flake.nixosModules.default = {pkgs, lib, ...}: {
#   imports = [./nix/module.nix];
#   services.<name>.package = lib.mkDefault inputs.self.packages.${pkgs.system}.default;
# };
```

## CI (GitHub Actions)

Evidence: a CI audit cut nix-amd-ai#247 from 9m09s to 4m54s, prdash#161 from 5–9m to 2m53s, aeye#327 from 3m48s–5m34s to 3m07s. Apply these patterns from the start.

**Go gate.** Expose one `checks.go-gate` derivation instead of several checks that each rebuild:

- Set `buildPhase = "true"` and share one GOCACHE across the steps.
- Run in order: lint → nilaway → test → `-race`.
- Do not repeat those tests in the package (`doCheck`) unless there is a sandbox-only reason. hookyard keeps its `doCheck` for one.

**Workflow shape.**

- Run independent work as parallel jobs, not sequential steps.
- Anything outside the Nix sandbox (devshell `go test`, bats) gets `actions/cache` on GOCACHE and GOMODCACHE.
- Pin each job's `name:`. A matrix key changes the job name and breaks required status checks.

**Checking outputs.**

- Cachix repos: use `nix-fast-build --skip-cached` instead of `nix build` + `nix flake check`.
- Add `nix flake check --no-build` to cover non-check outputs (packages, modules) that fast-build skips.

**Pitfalls.**

- magic-nix-cache now needs FlakeHub. Do not rely on it; use cachix or `actions/cache`.
- Slow `-race` render-matrix tests can skip under `-short` (prdash#161).

**Auditing CI time.**

- Read job and step durations, not wall-clock times: those include re-runs.
- `nix build` without `-L` prints only "building …" lines; add `-L` to see where time goes.
- "previously built" in the log means the time went to evaluation, not building.
- Time a suspect check locally with `--rebuild` before blaming it.

## Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Forgot `git add` after creating files | `path does not exist` / flake can't see `flake.nix` | `git add -A` before `nix build` / `direnv allow` |
| `vendorHash`/`cargoHash` left as placeholder | `hash mismatch` on first build | copy the `got:` hash into the field, rebuild |
| Pinned an input to `rev = "main"` | works now, `hash mismatch` after upstream pushes | pin to a 40-char commit SHA (`nurl <url>`) — see CLAUDE.md gotcha |
| Hand-edited `.pre-commit-config.yaml` | changes vanish on next `nix develop` | edit `pre-commit.settings.hooks` in flake.nix; the YAML is generated |
| Made a `flake-modules/` dir for a small project | needless indirection | keep `perSystem` inline; that split is only for `nix-config` |

## When NOT to use

- Adding a package to **this** `nix-config` repo → `nix-package-authoring` skill (inside nix-config)
- Rebuilding / switching → `nix-rebuild` skill (inside nix-config)
- The repo already has a working flake — just edit it

---
name: nix-package-authoring
description: Use when adding a new package to the `packages/` directory, writing a fresh derivation, finding which nixpkgs package owns a binary/file, or resolving `command not found` on a host. Covers `nurl`, `nix-init`, and `nix-locate` workflows in the nix-config repo.
---

# Nix Package Authoring

## Overview

Three small tools speed up package work in this repo:

| Tool | Use it when | Lives in |
|---|---|---|
| `nurl <url>` | You know the source URL and need a ready-to-paste `fetchFromGitHub` / `fetchurl` block with the correct hash | devshell |
| `nix-init <url>` | You want to scaffold a whole derivation (src, deps, license, meta) from a URL, then tweak | devshell |
| `nix-locate <path>` | You need to find which nixpkgs package provides a binary or file — before deciding to vendor it | HM (always-on) |
| `, <pkg> <args>` | You want to run a package once without adding it to `home/packages.nix` | HM (always-on) |

`nurl` / `nix-init` are only in the devshell (`nix develop` / `just dev`) — scaffolding tools, not daily drivers. `nix-locate` / `,` are installed via `home/nix-tools/` and always available.

## Workflows

### Adding a new package to `packages/`

**Option A — simple fetcher, write the derivation yourself:**

```fish
nurl https://github.com/owner/repo v1.2.3
# Pastes:
#   fetchFromGitHub {
#     owner = "owner";
#     repo = "repo";
#     rev = "v1.2.3";
#     hash = "sha256-...";
#   }
```

Drop that into your `packages/<name>.nix` and wire up `buildGoModule` / `stdenv.mkDerivation` / etc. by hand.

**Option B — full scaffold:**

```fish
nix-init --url https://github.com/owner/repo packages/new-pkg.nix
```

Walks you through a best-guess builder (Go, Rust, Python, …), fills in deps, fetches hashes, writes a complete derivation. Review + tidy before committing.

Then register in `packages/default.nix` as usual, `git add`, rebuild.

### Finding a package that already exists

Before adding a new derivation, check if nixpkgs already ships it:

```fish
nix-locate bin/some-tool         # substring match on file path
nix-locate --whole-name bin/rg   # basename must match exactly
nix-locate --at-root /bin/rg     # treat pattern as absolute package-root path
nix-locate -t x bin/rg           # only executables
```

Output columns: `<attr>  <size>  <type>  <path>` — the first column is what you'd put in `home/packages.nix`. An `(attr)` in parens means nix-index only knows a dependent package, not the producing one.

Also triggers automatically: running an unknown command in an interactive shell prints the nixpkgs attr that provides it (via the `command-not-found` hook from `nix-index-database`).

### Running something once without installing

```fish
, cowsay hello           # fetch cowsay, run it, forget it
, --from nixpkgs-unstable <pkg>   # pin a channel
```

Use for one-shot experiments. If you find yourself reaching for `,` twice for the same package, add it to `home/packages.nix`.

## Index freshness

`nix-index-database` ships a pre-built index — no manual `nix-index` run required; it updates on every HM switch. If `nix-locate` ever complains the index is stale, rerun `nh home switch .`.

## Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Running `nix-init` / `nurl` outside the devshell | `command not found` | `just dev` (or `nix develop`) first |
| Pasting `nurl` output without picking a `rev` | Scaffold uses `HEAD`; reproducibility breaks | Pass an explicit tag/commit: `nurl <url> <rev>` |
| Using `,` for something you'll run daily | Cold start every time; clutters `~/.cache/nix-index` | Add to `home/packages.nix` instead |
| Forgetting to check `nix-locate` before vendoring | Duplicate of an upstream package | Always `nix-locate bin/<name>` first |

## When NOT to use this skill

- Rebuilding / switching configs → use `nix-rebuild` skill
- Editing an already-working derivation in `packages/` — just edit it
- Searching **NixOS module options** (not packages) → use `search.nixos.org/options` in a browser

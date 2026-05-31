# nix-darwin for MBP M4 Pro — Design

**Date:** 2026-05-31
**Status:** Approved (design), pending spec review
**Author:** Noam Stolero (with Claude)

## Goal

Bring the nix-config repo to a new MacBook Pro (M4 Pro, `aarch64-darwin`) using
**nix-darwin**, **Determinate Nix**, and **nix-homebrew**, with a "full port":
system-integrated Home Manager reusing the cross-platform `home/` modules, macOS
system defaults, and GUI apps (including **Claude Desktop**, which is not in
nixpkgs for darwin) installed declaratively via Homebrew Casks.

## Decisions (locked)

| Decision | Choice |
|----------|--------|
| Scope | Full port (system + HM + casks + macOS defaults) |
| Profile | `personal` |
| Hostname | `mbp-m4-pro` |
| macOS username | `noams` (home dir `/Users/noams`) |
| Homebrew management | `nix-homebrew` (declarative install + pinned taps) |
| Nix management | Determinate Nix (`determinateNix.enable = true`) |
| Home Manager wiring | System-integrated via `home-manager.darwinModules` (one `darwin-rebuild`) |

## Hard constraint: cannot build darwin here

The dev machine is `x86_64-linux`; it **cannot build or test `aarch64-darwin`**.
The deliverable is an **evaluation-clean config + a Mac-side bootstrap runbook**.
Final verification and any darwin-specific build fixes happen on the MBP. The
first `darwin-rebuild switch` on the Mac IS the verification step.

Corollary: `nix flake check` / pre-commit must **not** attempt to build the
darwin config from Linux. Keep `darwinConfigurations` as plain flake outputs
(system-independent, under `flake = { ... }`), not in `perSystem`, and do not add
`aarch64-darwin` to the flake `systems` list.

## Architecture

### Section 1 — Flake wiring

Add inputs to `flake.nix`:

- `nix-darwin` → `github:nix-darwin/nix-darwin`, `inputs.nixpkgs.follows = "nixpkgs"`
- `nix-homebrew` → `github:zhaofengli/nix-homebrew`
- `homebrew-core` → `github:Homebrew/homebrew-core`, `flake = false`
- `homebrew-cask` → `github:Homebrew/homebrew-cask`, `flake = false`
- `determinate` — **already present**, reuse its `darwinModules.default`.

New `flake-modules/darwin-systems.nix` mirroring `nixos-systems.nix`:

```nix
{inputs, ...}: let
  mkDarwin = hostModule:
    inputs.nix-darwin.lib.darwinSystem {
      modules = [hostModule];
      specialArgs = { inherit inputs; inherit (inputs) self; };
    };
in {
  flake.darwinConfigurations = {
    mbp-m4-pro = mkDarwin ../hosts/mbp-m4-pro;
  };
}
```

Register it in `flake.nix`'s `imports`.

### Section 2 — Shared config & options

- Add `mbp-m4-pro` to `lib/host-configs.nix`:
  `{ username = "noams"; user-full-name = "Noam Stolero"; email = "noamstolero@gmail.com"; hostname = "mbp-m4-pro"; desktop.mode = "none"; machine.type = "laptop"; profile = "personal"; }`
- Make `options.nix` platform-aware. It is now shared by NixOS **and** darwin:
  - Add `pkgs` to its argument set.
  - Add a read-only derived `isDarwin = pkgs.stdenv.hostPlatform.isDarwin`.
  - Make `flakePath` default conditional: `/Users/${username}/nix-config` on
    darwin, `/home/${username}/nix-config` otherwise.

### Section 3 — Darwin host module (`hosts/mbp-m4-pro/default.nix`)

Imports:
- `../../options.nix`
- `inputs.determinate.darwinModules.default`
- `inputs.nix-homebrew.darwinModules.nix-homebrew`
- `inputs.home-manager.darwinModules.home-manager`

System config:
- Identity: `inherit (hostConfigs.mbp-m4-pro) ...` for username/hostname/etc.
- `determinateNix.enable = true` — Determinate owns Nix; nix-darwin's `nix.*`
  options become inert (see Quirks).
- `system.stateVersion = <current nix-darwin int>` (e.g. `6`) — distinct from HM
  `stateVersion`.
- `system.primaryUser = "noams"` — required by recent nix-darwin for user-scoped
  options (homebrew, `system.defaults`).
- `users.users.noams.home = "/Users/noams";`
- `nix-homebrew`: `{ enable = true; enableRosetta = true; user = "noams"; taps = { ... pinned from flake inputs ... }; mutableTaps = false; }`
- `homebrew`:
  - `enable = true;`
  - `onActivation = { autoUpdate = true; upgrade = true; cleanup = "uninstall"; };`
    (**start at `uninstall`, not `zap`** — see Quirks; promote to `zap` once the
    declared list is complete)
  - `casks = [ "claude" "ghostty" "firefox" ... ];` (final list TBD in plan)
- `system.defaults`: small starter set — fast `KeyRepeat`/`InitialKeyRepeat`,
  `dock.autohide`, `finder.AppleShowAllExtensions`, `NSGlobalDomain` tweaks.
- Home Manager block (mirrors `home/default.nix`):
  `home-manager = { useGlobalPkgs = true; useUserPackages = true; backupFileExtension = "bak"; extraSpecialArgs = { inherit inputs; osConfig = <this config>; }; users.noams = ../../home/noams.nix; };`

### Section 4 — Home tree reuse

Target import set on darwin (already produced by existing gating: `desktop.mode =
"none"` skips `./desktop` + `./flatpak`; `profile = "personal"` skips `./work` +
`./kubernetes`):

`packages`, `terminal`, `xdg`, `git`, `direnv`, `ssh`, `nvim`, `ipython`, `ai`,
`nix-tools`.

Two hard blockers to fix in `home/noams.nix`:
1. `homeDirectory = "/home/${username}"` → conditional on `isDarwin`
   (`/Users/${username}`).
2. `xdg.configFile."flakehub/auth"` symlinks `/run/agenix/noams_flakehub` (absent
   on macOS) → gate to Linux only. FlakeHub auth on the Mac uses
   `determinate-nixd login`.

Each shared module then gets a darwin audit (per-module checklist in the plan).
Known landmines documented in Quirks.

### Section 5 — Bootstrap runbook (Mac-side)

1. Install **Determinate Nix** (official Determinate installer for macOS).
2. `softwareupdate --install-rosetta --agree-to-license` (for `enableRosetta`).
3. `git clone` the config to `~/nix-config`.
4. First build (nix-darwin not yet installed):
   `nix run nix-darwin -- switch --flake ~/nix-config#mbp-m4-pro`
5. Subsequent rebuilds: `darwin-rebuild switch --flake ~/nix-config#mbp-m4-pro`
   or `nh darwin switch ~/nix-config`.
6. Confirm Claude Desktop installed (`/Applications/Claude.app`).
7. Iterate on any module that fails to build (expected — see Quirks §C).
8. Set login shell to fish if desired (see Quirks).

## Quirks & gotchas to handle

### A. Determinate ⇄ nix-darwin

- **`nix.*` options are inert** under `determinateNix.enable = true`. nix-darwin
  will NOT write `nix.conf`. Anything relying on `nix.settings`, `nix.gc`,
  `nix.optimise`, or `nix.linux-builder` is silently ignored. Configure extra
  substituters/caches via Determinate (`/etc/nix/nix.custom.conf` or
  `determinateNix.customSettings`) — not via `nix.settings`.
- **Caches:** the flake's `nixConfig.substituters` mostly list Linux-only caches
  (hyprland, noctalia, nix-amd-ai, vicinae). Harmless on darwin but useless.
  FlakeHub Cache requires `determinate-nixd login` on the Mac.
- **Bootstrap order:** Determinate first, then nix-darwin via `nix run nix-darwin`.
  nix-darwin is not on PATH until the first switch completes.

### B. Homebrew / nix-homebrew

- **`cleanup = "zap"` is destructive** — it uninstalls every cask/brew not
  declared, including anything installed manually. **Start with `"uninstall"`**
  (or `"none"`) until the declared cask list is complete, then promote to `"zap"`.
- **Apple Silicon prefix is `/opt/homebrew`**; `user = "noams"` must own it.
  `enableRosetta = true` needs Rosetta 2 installed first (runbook step 2).
- **Some casks need manual post-install steps** macOS can't automate: Gatekeeper
  approval, Accessibility/Screen-Recording permission grants, sign-in. Claude
  Desktop cask installs the `.app`; first launch may prompt Gatekeeper.
- **`masApps` (Mac App Store)** require `mas` and an active App Store sign-in —
  not fully declarative; omit from first cut.
- **`mutableTaps = false`** pins taps to flake inputs; running `brew tap` manually
  afterward will be reverted on next switch. Intended, but worth knowing.

### C. Home modules — concrete Linux-only landmines

These are in the **always-on** import set and WILL break the darwin build until
gated:

- `home/packages.nix` base list contains Linux-only tools:
  `strace`, `ltrace`, `lm_sensors`, `ethtool`, `pciutils` (lspci),
  `usbutils` (lsusb), `sysstat`, `file-roller`, and the `amdgpu_top`
  `writeShellScriptBin` (references the AMD-only `amdgpu_top` package). Gate all
  of these behind `lib.optionals (!osConfig.isDarwin)` (or `pkgs.stdenv.isLinux`).
- `home/terminal/default.nix`:
  - imports `./foot` — **foot is a Wayland terminal, Linux-only.** Must be gated
    out on darwin. (`kitty`, `ghostty` are fine on macOS.)
  - `home.packages = [pkgs.wtc]` and `programs.lazytmux` (worktrunk integration) —
    depend on your own flake inputs; verify darwin support (§D).
  - yazi `dragon-drop` keybindings reference `dragon-drop` (Linux X11 tool) — the
    keybinds are harmless strings, but the binary won't exist; acceptable, or gate.
- `home/ai`: `claude-code`, `opencode`, `amp`, `cursor`, `mcp*`. CLI configs
  should be cross-platform, but `cursor` and any hardcoded Linux paths need an
  audit. The `pi` agent (`llm-agents.nix`) in `packages.nix` — verify darwin
  output exists.
- `home/nix-tools`: `nix-index-database` + `comma` — cross-platform, expected OK.

### D. Your own flake inputs may lack darwin outputs

Shared modules pull these personal flakes: **`wtc`**, **`zr`**, **`lazytmux`**,
and `pi` (via `llm-agents.nix`). If their flakes only declare `x86_64-linux` (or
`default-linux` systems), `packages.${aarch64-darwin}` won't exist and evaluation
fails. **Action:** for each, either confirm it exposes `aarch64-darwin`, gate its
usage to Linux, or add darwin to the upstream flake's systems. Track per-input in
the plan.

### E. Platform / environment

- **Login shell:** macOS defaults to zsh. nix-darwin doesn't cleanly change the
  shell of a pre-existing account; set fish via `chsh -s` manually (after adding
  it to `/etc/shells`, which `programs.fish.enable` in nix-darwin can do) or an
  activation script. Flagged as a manual/known step.
- **Xcode Command Line Tools** likely needed for any source builds (e.g. nvim
  treesitter parsers) — `xcode-select --install` if a build complains.
- **XDG paths:** macOS apps use `~/Library`, but our HM `xdg.configFile` writes to
  `~/.config` for the CLI tools we manage — fine.
- **Overlays:** `lib/overlays.nix` is applied to the darwin nixpkgs. Overlays are
  lazy, so Linux-only overlay attrs only fail if referenced — but audit for any
  that force-evaluate Linux packages.

## Non-goals (first cut)

- agenix system secrets on darwin (FlakeHub auth handled by Determinate login).
- `nix.linux-builder` / remote builders.
- Mac App Store apps (`masApps`).
- Porting the Hyprland / desktop / work / kubernetes trees.
- A darwin devShell or adding `aarch64-darwin` to `perSystem`.

## Verification plan

Because darwin can't build here:

1. **On Linux (this repo):** `nix flake check` must still pass for the existing
   Linux configs; confirm `darwinConfigurations.mbp-m4-pro` at least **evaluates**
   (e.g. `nix eval .#darwinConfigurations.mbp-m4-pro.system.name` may still need a
   darwin builder — note where Linux eval is/ isn't possible).
2. **On the Mac:** the bootstrap runbook; first `darwin-rebuild switch` is the
   real test. Fix gating issues iteratively (Quirks §C/§D).

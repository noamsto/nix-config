# nix-darwin MBP M4 Pro Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `darwinConfigurations.mbp-m4-pro` to the flake — Determinate Nix + nix-darwin + nix-homebrew + system-integrated Home Manager reusing the cross-platform `home/` modules, installing Claude Desktop via a Homebrew cask.

**Architecture:** Mirror the existing `nixos-systems.nix` pattern with a new `darwin-systems.nix` flake-module producing a system-independent `flake.darwinConfigurations` output. The darwin host imports `options.nix` (made platform-aware), the Determinate + nix-homebrew darwin modules, and `home-manager.darwinModules.home-manager`. The existing `profile`/`desktop.mode` gating already excludes the Linux desktop/work trees; remaining Linux-only references in the shared modules are gated with `pkgs.stdenv.isLinux`.

**Tech Stack:** Nix flakes, flake-parts, nix-darwin, nix-homebrew, Determinate Nix, Home Manager.

**Spec:** `docs/superpowers/specs/2026-05-31-nix-darwin-mbp-m4-design.md`

---

## Critical constraints (read before starting)

1. **No darwin builds here.** This repo's dev host is `x86_64-linux`. Do NOT attempt `darwin-rebuild`/`nix build` of the darwin config. The Linux gates below are *partial*; the authoritative test is the Mac runbook in Task 11.
2. **Gate in `home/` modules with `pkgs.stdenv.isLinux` / `pkgs.stdenv.isDarwin`, never `osConfig.isDarwin`.** In standalone Linux HM (`flake-modules/home-manager.nix`), `osConfig` is a raw attrset from `host-configs.nix` with no `isDarwin` key — referencing it would break the Linux builds. `pkgs.stdenv` is always present.
3. **`osConfig.isDarwin` / `config.isDarwin` is only valid in system (NixOS/darwin) modules**, where `options.nix` is imported into the module system. Use it only in `hosts/` and `options.nix`.
4. **Frequent commits** — one per task. Branch is `feat/nix-darwin-mbp-m4`.

### Standard verification commands (referenced by tasks)

- **Linux flake check (must stay green throughout):**
  `nix flake check 2>&1 | tail -30`
- **Darwin eval — quick structural gate:**
  `nix eval .#darwinConfigurations.mbp-m4-pro.config.networking.hostName`
  Expected once Tasks 1–5 land: `"mbp-m4-pro"`
- **Darwin eval — deep gate (forces HM + custom-input eval; catches quirk D):**
  `nix eval --raw .#darwinConfigurations.mbp-m4-pro.config.system.build.toplevel.drvPath`
  Expected: a `/nix/store/...-darwin-system-....drv` path. If this fails with *“attribute 'aarch64-darwin' missing”* or *“attribute 'X' missing”*, that's a quirk-D gap → gate it (Task 9). If it fails on **IFD requiring a darwin builder**, that's expected — note it and defer to the Mac build.

---

## File structure

| File | Action | Responsibility |
|------|--------|----------------|
| `flake.nix` | Modify | Add `nix-darwin`, `nix-homebrew`, `homebrew-core`, `homebrew-cask` inputs; import `darwin-systems.nix` |
| `flake-modules/darwin-systems.nix` | Create | `mkDarwin` helper + `flake.darwinConfigurations` |
| `lib/host-configs.nix` | Modify | Add `mbp-m4-pro` host entry |
| `options.nix` | Modify | Add `pkgs` arg, `isDarwin` derived bool, platform-aware `flakePath` |
| `hosts/mbp-m4-pro/default.nix` | Create | The darwin system module |
| `home/noams.nix` | Modify | Platform-aware `homeDirectory`; gate FlakeHub agenix symlink to Linux |
| `home/packages.nix` | Modify | Move Linux-only base packages behind `pkgs.stdenv.isLinux` |
| `home/terminal/default.nix` | Modify | Gate `./foot`, `wtc`, and `lazytmux` to Linux |
| `hosts/mbp-m4-pro/README.md` | Create | Mac-side bootstrap runbook |

---

## Task 1: Add flake inputs

**Files:**
- Modify: `flake.nix` (inputs block, ~line 62–215; imports list ~line 10–15)

- [ ] **Step 1: Add the four inputs**

In `flake.nix`, inside `inputs = { ... }`, add (place near `determinate`, which already exists — do not re-add it):

```nix
    # === macOS (nix-darwin) ===
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Homebrew taps pinned for nix-homebrew (flake = false: plain source trees)
    homebrew-core = {
      url = "github:Homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:Homebrew/homebrew-cask";
      flake = false;
    };
```

- [ ] **Step 2: Register the darwin flake-module import**

In `flake.nix`, add to the `imports = [ ... ]` list (after `./flake-modules/home-manager.nix`):

```nix
        ./flake-modules/darwin-systems.nix
```

- [ ] **Step 3: Lock the new inputs**

Run: `nix flake lock 2>&1 | tail -20`
Expected: lock entries added for `nix-darwin`, `nix-homebrew`, `homebrew-core`, `homebrew-cask`; no errors.

> Note: `git add` the changed files before any `nix` eval/lock — this repo's flake gotcha (untracked files are invisible to Nix). The pre-commit hook may reformat `flake.nix`; re-stage if so.

- [ ] **Step 4: Commit**

```bash
git add flake.nix flake.lock
git commit -m "feat(darwin): add nix-darwin, nix-homebrew, and homebrew tap inputs"
```

---

## Task 2: Add the darwin-systems flake-module

**Files:**
- Create: `flake-modules/darwin-systems.nix`

- [ ] **Step 1: Create the module**

```nix
# nix-darwin (macOS) system configurations
{inputs, ...}: let
  mkDarwin = hostModule:
    inputs.nix-darwin.lib.darwinSystem {
      modules = [hostModule];
      specialArgs = {
        inherit inputs;
        inherit (inputs) self;
      };
    };
in {
  flake.darwinConfigurations = {
    mbp-m4-pro = mkDarwin ../hosts/mbp-m4-pro;
  };
}
```

- [ ] **Step 2: Verify it parses (host doesn't exist yet — expect a path error, not a syntax error)**

Run: `git add flake-modules/darwin-systems.nix; nix flake show 2>&1 | tail -20`
Expected: error referencing the missing `../hosts/mbp-m4-pro` path (proves the module itself parses). Syntax errors here mean fix before continuing.

- [ ] **Step 3: Commit**

```bash
git add flake-modules/darwin-systems.nix
git commit -m "feat(darwin): add darwin-systems flake-module"
```

---

## Task 3: Make options.nix platform-aware

**Files:**
- Modify: `options.nix` (arg set line 1–5; `flakePath` ~line 68–72)

- [ ] **Step 1: Add `pkgs` to the argument set**

Change the header from:

```nix
{
  config,
  lib,
  ...
}: {
```

to:

```nix
{
  config,
  lib,
  pkgs,
  ...
}: {
```

- [ ] **Step 2: Add the `isDarwin` derived option**

Inside `options = { ... }`, after the `profile` option block, add:

```nix
    isDarwin = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isDarwin;
      readOnly = true;
      description = "True on nix-darwin (macOS) systems";
    };
```

- [ ] **Step 3: Make `flakePath` platform-aware**

Replace the existing `flakePath` option:

```nix
    flakePath = lib.mkOption {
      type = lib.types.str;
      default = "/home/${config.username}/nix-config";
      readOnly = true;
    };
```

with:

```nix
    flakePath = lib.mkOption {
      type = lib.types.str;
      default =
        if pkgs.stdenv.hostPlatform.isDarwin
        then "/Users/${config.username}/nix-config"
        else "/home/${config.username}/nix-config";
      readOnly = true;
    };
```

- [ ] **Step 4: Verify Linux configs still evaluate**

Run: `git add options.nix; nix flake check 2>&1 | tail -20`
Expected: no new errors (existing Linux configs still build/eval as before).

- [ ] **Step 5: Commit**

```bash
git add options.nix
git commit -m "feat(options): add isDarwin and platform-aware flakePath"
```

---

## Task 4: Add the mbp-m4-pro host config

**Files:**
- Modify: `lib/host-configs.nix` (after the `thinkpad-p14s-g6` block, ~line 39)

- [ ] **Step 1: Add the host entry**

Inside the returned attrset, after the `thinkpad-p14s-g6 = { ... };` block:

```nix
  mbp-m4-pro = {
    username = "noams";
    user-full-name = "Noam Stolero";
    email = "noamstolero@gmail.com";
    hostname = "mbp-m4-pro";
    desktop.mode = "none";
    machine.type = "laptop";
    profile = "personal";
  };
```

- [ ] **Step 2: Verify it parses**

Run: `git add lib/host-configs.nix; nix eval --json --file lib/host-configs.nix --apply 'c: c.mbp-m4-pro.hostname'`
Expected: `"mbp-m4-pro"`

- [ ] **Step 3: Commit**

```bash
git add lib/host-configs.nix
git commit -m "feat(hosts): add mbp-m4-pro to shared host-configs"
```

---

## Task 5: Create the darwin host module

**Files:**
- Create: `hosts/mbp-m4-pro/default.nix`

- [ ] **Step 1: Write the host module**

```nix
{
  inputs,
  config,
  ...
}: let
  host = (import ../../lib/host-configs.nix).mbp-m4-pro;
in {
  imports = [
    ../../options.nix
    inputs.determinate.darwinModules.default
    inputs.nix-homebrew.darwinModules.nix-homebrew
    inputs.home-manager.darwinModules.home-manager
  ];

  # Custom options (from options.nix)
  inherit (host) username user-full-name email hostname profile;
  desktop.mode = host.desktop.mode;
  machine.type = host.machine.type;

  # nixpkgs for this host (overlays + unfree, mirrors the Linux side)
  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = import ../../lib/overlays.nix inputs;

  # Determinate owns Nix; nix-darwin's nix.* options become inert (by design).
  determinateNix.enable = true;

  # nix-darwin system identity.
  # NOTE: bump stateVersion to the current nix-darwin value if the changelog
  # on the Mac says otherwise; 6 is correct as of this writing.
  system.stateVersion = 6;
  system.primaryUser = host.username;
  networking.hostName = host.hostname;
  networking.computerName = host.hostname;

  users.users.${host.username}.home = "/Users/${host.username}";

  # Declarative Homebrew via nix-homebrew (Apple Silicon prefix /opt/homebrew).
  nix-homebrew = {
    enable = true;
    enableRosetta = true;
    user = host.username;
    mutableTaps = false;
    taps = {
      "homebrew/homebrew-core" = inputs.homebrew-core;
      "homebrew/homebrew-cask" = inputs.homebrew-cask;
    };
  };

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      # Start conservative: "uninstall" removes undeclared casks but keeps
      # their data. Promote to "zap" only once the cask list is complete.
      cleanup = "uninstall";
    };
    casks = [
      "claude"
      "ghostty"
      "firefox"
    ];
  };

  # Minimal starter macOS defaults — grow over time.
  system.defaults = {
    NSGlobalDomain = {
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      AppleShowAllExtensions = true;
    };
    dock.autohide = true;
    finder.AppleShowAllExtensions = true;
  };

  # System-integrated Home Manager. osConfig is auto-injected as this darwin
  # config, so the shared home/ modules read desktop.mode/profile/username
  # exactly as on NixOS.
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = {inherit inputs;};
    users.${host.username} = ../../home/noams.nix;
  };
}
```

- [ ] **Step 2: Quick structural eval (will likely surface home-module gating gaps — that's Tasks 6–9)**

Run: `git add hosts/mbp-m4-pro/default.nix; nix eval .#darwinConfigurations.mbp-m4-pro.config.networking.hostName 2>&1 | tail -20`
Expected: `"mbp-m4-pro"`. If it errors inside a `home/` module, that's expected and addressed next; the hostName attr itself should resolve once the module graph evaluates. If the error is in *this* file (option typo, wrong module path), fix it now.

- [ ] **Step 3: Commit**

```bash
git add hosts/mbp-m4-pro/default.nix
git commit -m "feat(hosts): add mbp-m4-pro nix-darwin host module"
```

---

## Task 6: Fix home/noams.nix blockers

**Files:**
- Modify: `home/noams.nix` (arg set line 1–6; `homeDirectory` line 31; xdg symlink line 43)

- [ ] **Step 1: Add `pkgs` to the argument set**

Change:

```nix
{
  config,
  lib,
  osConfig,
  ...
}: {
```

to:

```nix
{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}: {
```

- [ ] **Step 2: Make `homeDirectory` platform-aware**

Replace:

```nix
    homeDirectory = "/home/${osConfig.username}";
```

with:

```nix
    homeDirectory =
      if pkgs.stdenv.hostPlatform.isDarwin
      then "/Users/${osConfig.username}"
      else "/home/${osConfig.username}";
```

- [ ] **Step 3: Gate the FlakeHub agenix symlink to Linux**

Replace:

```nix
  # FlakeHub authentication (symlink to agenix-managed secret)
  xdg.configFile."flakehub/auth".source = config.lib.file.mkOutOfStoreSymlink "/run/agenix/noams_flakehub";
```

with:

```nix
  # FlakeHub authentication (symlink to agenix-managed secret).
  # Linux only: /run/agenix doesn't exist on darwin — FlakeHub auth there is
  # handled by `determinate-nixd login`.
  xdg.configFile = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    "flakehub/auth".source = config.lib.file.mkOutOfStoreSymlink "/run/agenix/noams_flakehub";
  };
```

- [ ] **Step 4: Verify Linux configs unaffected**

Run: `git add home/noams.nix; nix flake check 2>&1 | tail -20`
Expected: no new errors.

- [ ] **Step 5: Commit**

```bash
git add home/noams.nix
git commit -m "fix(home): platform-aware homeDirectory; gate FlakeHub symlink to Linux"
```

---

## Task 7: Gate Linux-only packages in home/packages.nix

**Files:**
- Modify: `home/packages.nix` (base `home.packages` list ~line 54–145)

Context: the always-on base list contains Linux-only tools that won't build on darwin (`strace`, `ltrace`, `lm_sensors`, `ethtool`, `pciutils`, `usbutils`, `sysstat`, `file-roller`, `zr`, `pi`, and the `amdgpu_top` wrapper). Move them into a Linux-gated list. Keep cross-platform tools (`lsof`, `nmap`, `mtr`, `gnused`, etc.) in the base list.

- [ ] **Step 1: Add a `linux-only` let-binding**

Inside the `let ... in` block (alongside `desktop-packages` / `personal-packages`), add:

```nix
  linux-only = with pkgs; [
    # syscall / hardware introspection — Linux kernel specific
    strace
    ltrace
    sysstat
    lm_sensors
    ethtool
    pciutils # lspci
    usbutils # lsusb
    file-roller # GNOME archive manager
    zr # custom flake input, Linux-only outputs
    pi # llm-agents.nix, Linux-only
    (writeShellScriptBin "amdgpu_top" ''
      scheme=$(dconf read /org/gnome/desktop/interface/color-scheme 2>/dev/null)
      if [ "$scheme" = "'prefer-light'" ]; then
        flag="--light"
      else
        flag="--dark"
      fi
      exec ${amdgpu_top}/bin/amdgpu_top "$flag" "$@"
    '')
  ];
```

- [ ] **Step 2: Remove those entries from the base `with pkgs [ ... ]` list**

Delete these lines from the base list: `strace`, `ltrace`, `sysstat`, `lm_sensors`, `ethtool`, `pciutils`, `usbutils`, `file-roller`, `zr`, `pi`, and the entire `(writeShellScriptBin "amdgpu_top" ''...'')` block. Leave `lsof` in the base list (cross-platform).

- [ ] **Step 3: Append the Linux-gated list**

Change the closing of `home.packages`:

```nix
    ++ lib.optionals (osConfig.desktop.mode != "none") desktop-packages
    ++ lib.optionals (osConfig.profile != "work") personal-packages;
```

to:

```nix
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux linux-only
    ++ lib.optionals (osConfig.desktop.mode != "none") desktop-packages
    ++ lib.optionals (osConfig.profile != "work") personal-packages;
```

- [ ] **Step 4: Verify Linux configs unaffected (the gated set still resolves on Linux)**

Run: `git add home/packages.nix; nix flake check 2>&1 | tail -20`
Expected: no new errors. (On Linux, `isLinux` is true, so the same packages are present as before — pure refactor.)

- [ ] **Step 5: Commit**

```bash
git add home/packages.nix
git commit -m "refactor(home): gate Linux-only packages behind stdenv.isLinux"
```

---

## Task 8: Gate Linux-only bits in home/terminal/default.nix

**Files:**
- Modify: `home/terminal/default.nix` (`home.packages` line 13; `imports` line 21–30; `programs.lazytmux` line 31–46)

Context: `foot` is a Wayland-only terminal; `pkgs.wtc` and the `lazytmux`/worktrunk integration depend on Linux-only custom flake outputs. Gate all three to Linux for the first cut. (`kitty`, `ghostty`, `fish`, `process_compose`, `television`, `btop`, `lazydocker`, `yazi`, `starship` are cross-platform and stay.)

- [ ] **Step 1: Gate `wtc` in `home.packages`**

Change:

```nix
    packages = [pkgs.wtc];
```

to:

```nix
    packages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [pkgs.wtc];
```

- [ ] **Step 2: Gate the `./foot` and `lazytmux` imports**

Change the `imports` block:

```nix
  imports = [
    inputs.lazytmux.homeManagerModules.default
    ./foot
    ./kitty
    ./fish
    ./process_compose
    ./television
    ./btop.nix
    ./lazydocker.nix
  ];
```

to:

```nix
  imports =
    [
      ./kitty
      ./fish
      ./process_compose
      ./television
      ./btop.nix
      ./lazydocker.nix
    ]
    # foot is Wayland-only; lazytmux/worktrunk depend on Linux-only outputs.
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      inputs.lazytmux.homeManagerModules.default
      ./foot
    ];
```

- [ ] **Step 3: Gate the `programs.lazytmux` config block**

Wrap the entire `programs.lazytmux = { ... };` block in `lib.mkIf` (the option only exists when the module is imported, i.e. on Linux):

```nix
  programs.lazytmux = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    enable = true;
    worktrunk.enable = true;
    claudeIntegration.enable = true;
    persist.enable = true;
    persist.restoreMode = "auto";
    processIcons = {
      houston = "🚀";
    };
    startupSession = {
      enable = true;
      name = "nix-config";
      directory = "${config.home.homeDirectory}/nix-config";
      terminal.emulator = "kitty";
    };
  };
```

- [ ] **Step 4: Verify Linux configs unaffected**

Run: `git add home/terminal/default.nix; nix flake check 2>&1 | tail -20`
Expected: no new errors.

- [ ] **Step 5: Commit**

```bash
git add home/terminal/default.nix
git commit -m "refactor(terminal): gate foot, wtc, and lazytmux to Linux"
```

---

## Task 9: Drive the darwin eval to green (discover remaining quirk-D gaps)

**Files:**
- Modify: whichever `home/` module the eval error points to (likely candidates: `home/ai/cursor`, `home/ai/opencode`, `home/ssh`, `home/git`, `home/direnv`, `home/ipython`, `home/nvim`).

Context: Tasks 6–8 cover the *known* Linux-only references. This task is the iterative loop to catch the rest — specifically custom-flake-input references that have no `aarch64-darwin` output (these DO surface in Linux eval as “attribute 'aarch64-darwin' missing”). Linux-only *nixpkgs* packages (with `meta.platforms = linux`) will NOT surface here — they only fail on the Mac build (Task 11).

- [ ] **Step 1: Run the deep eval gate**

Run: `git add -A; nix eval --raw .#darwinConfigurations.mbp-m4-pro.config.system.build.toplevel.drvPath 2>&1 | tail -30`

- [ ] **Step 2: Interpret the result**

- **Success** (prints a `...-darwin-system-....drv` path): eval is clean. Skip to Step 4.
- **`error: attribute 'aarch64-darwin' missing`** or **`attribute '<name>' missing`**: a custom flake input or overlay package lacks a darwin output. Note the module from the stack trace and go to Step 3.
- **IFD error requiring a darwin builder** (e.g. “a 'aarch64-darwin' with features {} is required to build … but I am a 'x86_64-linux'”): this is the expected Linux limitation. Record it in the Task 11 runbook as “verify on Mac” and treat eval as structurally clean. Skip to Step 4.

- [ ] **Step 3: Gate the offending reference, then re-run Step 1**

Apply the same pattern used in Tasks 7–8 to the module the trace points at:
- A package in a list: `++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.<thing> ]` (add `pkgs`/`lib` to the module's arg set if absent).
- An imported HM module from a Linux-only input: move it into a `lib.optionals pkgs.stdenv.hostPlatform.isLinux [ ... ]` import branch.
- A `programs.<x>` / config block tied to a gated import: wrap in `lib.mkIf pkgs.stdenv.hostPlatform.isLinux { ... }`.

Re-run Step 1. Repeat until Step 2 yields Success or the IFD case. **Commit after each module you gate** with a focused message, e.g.:

```bash
git add home/<module>
git commit -m "refactor(<module>): gate Linux-only reference for darwin"
```

- [ ] **Step 4: Confirm Linux still green**

Run: `nix flake check 2>&1 | tail -20`
Expected: no new errors.

- [ ] **Step 5: Final commit for this task (if any uncommitted gating remains)**

```bash
git add -A
git commit -m "refactor(home): gate remaining Linux-only references for darwin eval"
```

---

## Task 10: Mirror caches into Determinate settings (optional but recommended)

**Files:**
- Modify: `hosts/mbp-m4-pro/default.nix` (`determinateNix` block)

Context: under `determinateNix.enable`, nix-darwin's `nix.settings` are inert. The cross-platform caches worth having on darwin are the FlakeHub + Determinate + nix-community + nixpkgs-unfree ones (the Linux-specific caches — hyprland, noctalia, nix-amd-ai, vicinae, yazi — are useless on darwin and can be omitted).

- [ ] **Step 1: Add `customSettings` to the determinate module**

Replace:

```nix
  determinateNix.enable = true;
```

with:

```nix
  determinateNix = {
    enable = true;
    customSettings = {
      extra-substituters = [
        "https://cache.flakehub.com"
        "https://nix-community.cachix.org"
        "https://nixpkgs-unfree.cachix.org"
        "https://claude-code.cachix.org"
      ];
      extra-trusted-public-keys = [
        "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixpkgs-unfree.cachix.org-1:hqvoInulhbV4nJ9yJOEr+4wxhDV4xq2d1DK7S6Nj6rs="
        "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      ];
    };
  };
```

> If `determinateNix.customSettings` is rejected at eval as an unknown option, the Determinate module version in the lock predates it — fall back to `enable = true;` only and configure caches via `/etc/nix/nix.custom.conf` on the Mac (note in Task 11). Confirm the option name against the locked `determinate` input before relying on it.

- [ ] **Step 2: Verify**

Run: `git add hosts/mbp-m4-pro/default.nix; nix eval .#darwinConfigurations.mbp-m4-pro.config.networking.hostName 2>&1 | tail -10`
Expected: `"mbp-m4-pro"` (or a clear option error to act on per the note above).

- [ ] **Step 3: Commit**

```bash
git add hosts/mbp-m4-pro/default.nix
git commit -m "feat(darwin): mirror cross-platform caches into Determinate settings"
```

---

## Task 11: Write the Mac-side bootstrap runbook

**Files:**
- Create: `hosts/mbp-m4-pro/README.md`

- [ ] **Step 1: Write the runbook**

```markdown
# mbp-m4-pro bootstrap

Built and verified ON the Mac (the config repo's Linux host cannot build
aarch64-darwin). Steps:

## 1. Install Determinate Nix
Use the Determinate installer for macOS: https://docs.determinate.systems/
(Determinate owns Nix; this config sets `determinateNix.enable = true`.)

## 2. Install Rosetta 2 (for `enableRosetta` casks)
```sh
softwareupdate --install-rosetta --agree-to-license
```

## 3. Clone the config
```sh
git clone <repo-url> ~/nix-config
cd ~/nix-config
```

## 4. First switch (nix-darwin not yet on PATH)
```sh
nix run nix-darwin -- switch --flake ~/nix-config#mbp-m4-pro
```
- Requires sudo for system activation.
- nix-homebrew will install Homebrew into /opt/homebrew on first run.
- Expect this to surface any Linux-only *nixpkgs* packages that slipped past
  the Linux eval gate (meta.platforms = linux). Gate each one with
  `lib.optionals pkgs.stdenv.hostPlatform.isLinux` in the offending home/ module
  and re-run.

## 5. Confirm Claude Desktop
```sh
ls /Applications/Claude.app
```

## 6. Subsequent rebuilds
```sh
darwin-rebuild switch --flake ~/nix-config#mbp-m4-pro
# or
nh darwin switch ~/nix-config
```

## 7. FlakeHub Cache auth (replaces the Linux agenix symlink)
```sh
sudo determinate-nixd login
```

## 8. Set fish as login shell (nix-darwin won't change a pre-existing account)
```sh
# fish path comes from `which fish` after the first switch
echo (which fish) | sudo tee -a /etc/shells
chsh -s (which fish)
```

## 9. Promote Homebrew cleanup
Once the cask list is complete, change `homebrew.onActivation.cleanup` from
`"uninstall"` to `"zap"` in hosts/mbp-m4-pro/default.nix.

## Known deferrals
- Custom flakes (wtc, zr, lazytmux, pi) are gated to Linux; add aarch64-darwin
  outputs upstream later to re-enable on the Mac.
- agenix system secrets not configured on darwin (first cut).
```

- [ ] **Step 2: Commit**

```bash
git add hosts/mbp-m4-pro/README.md
git commit -m "docs(darwin): add mbp-m4-pro bootstrap runbook"
```

---

## Task 12: Final Linux verification & wrap-up

- [ ] **Step 1: Full flake check**

Run: `nix flake check 2>&1 | tail -30`
Expected: all existing Linux configs pass; no eval errors introduced.

- [ ] **Step 2: Confirm the darwin output is present**

Run: `nix flake show 2>&1 | grep -A2 darwinConfigurations`
Expected: `mbp-m4-pro` listed under `darwinConfigurations`.

- [ ] **Step 3: Confirm treefmt/pre-commit clean**

Run: `nix fmt 2>&1 | tail -10`
Then: `git status --short`
Expected: no unformatted changes; if `nix fmt` changed files, review and commit them.

- [ ] **Step 4: Final commit (if formatting changed anything)**

```bash
git add -A
git commit -m "chore(darwin): treefmt pass"
```

---

## Self-review notes (coverage vs spec)

- Spec §1 Flake wiring → Tasks 1–2. ✓
- Spec §2 Shared config & options → Tasks 3–4. ✓
- Spec §3 Darwin host module → Tasks 5, 10. ✓
- Spec §4 Home tree reuse + blockers → Tasks 6–9. ✓
- Spec §5 Bootstrap runbook → Task 11. ✓
- Quirk A (Determinate/nix.* inert, caches) → Task 10 + runbook §7. ✓
- Quirk B (Homebrew zap/Rosetta/prefix) → Task 5 (`cleanup="uninstall"`, `enableRosetta`) + runbook §2,§9. ✓
- Quirk C (Linux-only nixpkgs pkgs) → Tasks 7–8 (known ones) + runbook §4 (Mac-build catches the rest). ✓
- Quirk D (custom flakes lack darwin outputs) → Task 9 iterative loop. ✓
- Quirk E (fish login shell, Xcode CLT, overlays) → runbook §8 + Task 9 IFD note. ✓
- Verification plan (Linux eval partial; Mac build authoritative) → standard commands block + Tasks 9/11. ✓
```

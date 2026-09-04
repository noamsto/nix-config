# halo Steam Machine Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make halo boot into Steam Gaming Mode on the TV as a dedicated
unprivileged user, without disturbing its inference role or `noams`'s headless
workflow.

**Architecture:** A new `steamConsole` option axis in `options.nix`, orthogonal to
`desktop.mode`, consumed by a self-gating `nixos/steam-console/` module that configures
Jovian-NixOS. halo keeps `desktop.mode = "none"`; the console session runs as a
separate system user whose home is the existing `/var/lib/games` subvolume.

**Tech Stack:** NixOS (flake-parts), Jovian-NixOS, btrfs, systemd.

**Spec:** [`docs/superpowers/specs/2026-09-04-halo-steam-machine-design.md`](../specs/2026-09-04-halo-steam-machine-design.md)

## Global Constraints

- **No TDD cycle applies.** This is declarative configuration, not application
  code. The red/green equivalent is evaluation and build. Every task's gate is
  `nix flake check` and/or `nh os build .#halo`, with the exact expected output
  given per task. Do not invent unit tests.
- **`git add` before every build.** Flakes evaluate from the git index; an
  unstaged new file produces `error: path '...' does not exist`. This is the
  single most common failure mode in this repo.
- **Pre-commit hooks reformat on first run.** `alejandra`/`prettier` rewrite
  files and exit non-zero. That is expected: `git add` the reformatted files and
  re-run the *same* commit. Do not change the commit message.
- **Cache lists must stay in sync** between `flake.nix:nixConfig` and
  `lib/caches.nix`. `flake.nix` carries the `SYNC:` comment saying so.
- **halo is `x86_64-linux`, hostname `halo`**, and runs
  `pkgs.linuxPackages_latest`. Nothing in this plan may pin a kernel.
- **Jovian cache** (verified live against the Cachix API):
  `https://jovian-nixos.cachix.org`
  `jovian-nixos.cachix.org-1:mAWLjAxLNlfxAnozUjOqGj4AxQwCl7MXwOfu7msVlAo=`
- **Do not enable `jovian.devices.steamdeck`.** That module pulls
  `linux-neptune` and would displace the gfx1151 kernel.
- Work happens on branch `feat/halo-steam-machine`, worktree
  `~/Data/git/.worktrees/noams/nix-config/feat-halo-steam-machine`.

---

### Task 1: Add the Jovian flake input and its binary cache

**Files:**
- Modify: `flake.nix` (inputs block; `nixConfig.substituters`; `nixConfig.trusted-public-keys`)
- Modify: `lib/caches.nix` (`substituters`; `trustedPublicKeys`)

**Interfaces:**
- Consumes: nothing.
- Produces: `inputs.jovian.nixosModules.default` (verified: Jovian's
  `flake.nix` declares `nixosModules = rec { default = jovian; jovian = ./modules; }`).
  Task 3 imports this. The module also applies Jovian's overlay itself via
  `modules/jovian/overlay.nix`, so no manual overlay wiring is needed anywhere.

- [ ] **Step 1: Add the input**

In `flake.nix`, in the `inputs` block, next to the other `noamsto`/third-party
entries (the `lazytmux`/`agent-smith` group around line 248):

```nix
    # Steam Deck UI (Gaming Mode) for halo's console role. Deliberately only
    # the Steam session — `jovian.devices.steamdeck` stays off, since it would
    # pull linux-neptune over the gfx1151 kernel halo needs.
    jovian = {
      url = "github:Jovian-Experiments/Jovian-NixOS";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

- [ ] **Step 2: Add the cache to `flake.nix:nixConfig`**

Append to `substituters` (after `"https://lazytmux.cachix.org"`):

```nix
      "https://jovian-nixos.cachix.org"
```

Append to `trusted-public-keys` (after the `lazytmux` key):

```nix
      "jovian-nixos.cachix.org-1:mAWLjAxLNlfxAnozUjOqGj4AxQwCl7MXwOfu7msVlAo="
```

- [ ] **Step 3: Add the same cache to `lib/caches.nix`**

Append to `substituters` (after `"https://lazytmux.cachix.org"`):

```nix
    "https://jovian-nixos.cachix.org"
```

Append to `trustedPublicKeys` (after the `lazytmux` key):

```nix
    "jovian-nixos.cachix.org-1:mAWLjAxLNlfxAnozUjOqGj4AxQwCl7MXwOfu7msVlAo="
```

- [ ] **Step 4: Stage and lock**

```bash
git add flake.nix lib/caches.nix
nix flake lock
```

Expected: `flake.lock` gains a `jovian` node. If it does not, the input was not
staged — re-check Step 4's `git add`.

- [ ] **Step 5: Verify the input resolves and the caches match**

```bash
nix flake metadata --json | python3 -c "import json,sys; print(json.load(sys.stdin)['locks']['nodes']['jovian']['locked']['rev'])"
```

Expected: a 40-character commit SHA.

```bash
grep -c jovian-nixos flake.nix lib/caches.nix
```

Expected: `flake.nix:2` and `lib/caches.nix:2` — one URL and one key in each
file. Any other count means the two lists have drifted, which is exactly what
the `SYNC:` comment in `flake.nix` exists to prevent.

- [ ] **Step 6: Commit**

```bash
git add flake.nix lib/caches.nix flake.lock
git commit -m "feat(flake): add Jovian-NixOS input and binary cache

Refs #210"
```

(If pre-commit reformats, `git add` the changed files and re-run the same commit.)

---

### Task 2: Add the `steamConsole` option axis

**Files:**
- Modify: `options.nix` (add a `steamConsole` block inside `options`)

**Interfaces:**
- Consumes: `config.desktop.isEnabled` (existing, read-only, defined in the same file).
- Produces: `config.steamConsole.enable` (bool), `config.steamConsole.user` (str),
  `config.steamConsole.autoStart` (bool). Tasks 3 and 4 read all three.

- [ ] **Step 1: Add the option block**

In `options.nix`, inside `options = { ... }`, after the `desktop` block and
before `machine`:

```nix
    # Deliberately NOT a `desktop.mode` value. `desktop.mode` governs whether
    # *this user* gets a desktop and drives the `home/desktop` import in
    # home/noams.nix; the console session runs as a separate account, so none of
    # that should change. Orthogonal axis, not a fourth enum member.
    steamConsole = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Run Steam Gaming Mode (Jovian) as a dedicated console user.";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = "steam";
        description = ''
          Unprivileged account the console session runs as. Deliberately not
          `username`: autologin means whoever holds the TV remote is logged in,
          and that must not be the account with SSH keys, sudo and agent access.
        '';
      };
      autoStart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Launch Gaming Mode at boot. False leaves it startable from a VT with
          `start-gamescope-session`.
        '';
      };
    };
```

- [ ] **Step 2: Verify it evaluates**

```bash
git add options.nix
nix eval .#nixosConfigurations.halo.config.steamConsole.user
```

Expected: `"steam"`

```bash
nix eval .#nixosConfigurations.halo.config.steamConsole.enable
```

Expected: `false` (nothing sets it yet — this is the "before" state).

- [ ] **Step 3: Commit**

```bash
git add options.nix
git commit -m "feat(options): add console option axis for Steam Machine mode

Refs #210"
```

---

### Task 3: Create the `nixos/steam-console` module

**Files:**
- Create: `nixos/steam-console/default.nix`
- Modify: `hosts/halo/default.nix` (add `../../nixos/steam-console` to `imports`)

**Interfaces:**
- Consumes: `config.steamConsole.{enable,user,autoStart}` (Task 2);
  `inputs.jovian.nixosModules.default` (Task 1).
- Produces: a system user named by `config.steamConsole.user`, whose home is
  `/var/lib/games`. Task 4 references that same path for tmpfiles and nodatacow.

**Verified option paths** (do not substitute from memory — these were read from
Jovian's source):
- `jovian.steam.enable`, `jovian.steam.autoStart`, `jovian.steam.user`
- `jovian.hardware.has.amd.gpu`
- `jovian.steamos.enableHdmiCecIntegration` — note its default is
  `config.jovian.steamos.useSteamOSConfig`, which is false here, so it **must**
  be set explicitly.

- [ ] **Step 1: Create the module**

```nix
{
  config,
  inputs,
  lib,
  ...
}: let
  cfg = config.steamConsole;
in {
  imports = [inputs.jovian.nixosModules.default];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !config.desktop.isEnabled;
        message = ''
          steamConsole.enable and desktop.mode != "none" both want the display, and
          Jovian's autostart path owns the display manager. Pick one.
        '';
      }
    ];

    jovian = {
      steam = {
        enable = true;
        inherit (cfg) autoStart user;
        # Required whenever autoStart is on: Jovian's autostart unit
        # interpolates this into an ExecStart unconditionally
        # (modules/steam/autostart.nix:106) and it defaults to null, so
        # evaluation dies with "cannot coerce null to a string". halo has no
        # desktop to switch to, and "gamescope-wayland" is the value Jovian's
        # own check message prescribes for exactly that case — "Switch to
        # Desktop" just relaunches Gaming Mode.
        desktopSession = "gamescope-wayland";
      };
      # Gates Jovian's AMD backlight/modesetting helpers. NOT
      # jovian.devices.steamdeck, which would pull linux-neptune over the
      # linuxPackages_latest that gfx1151 needs.
      hardware.has.amd.gpu = true;
      # Defaults to useSteamOSConfig (false here), so it needs saying: this is
      # what lets the TV remote drive the UI over HDMI.
      steamos.enableHdmiCecIntegration = true;
    };

    # Jovian's modules/steam/steam.nix already sets programs.steam.enable,
    # hardware.graphics and hardware.steam-hardware. remotePlay.openFirewall is
    # deliberately left off: halo keeps ports off the LAN and is reached over
    # tailscale, same posture as lemond and ds4.

    users.users.${cfg.user} = {
      isNormalUser = true;
      description = "Steam Gaming Mode session";
      # Home is the @games subvolume root, so libraries, Proton prefixes and
      # shader caches stay off @home.
      home = "/var/lib/games";
      # No wheel, no authorizedKeys: autologin must not reach sudo or SSH.
      extraGroups = ["video" "render" "input" "audio"];
    };
  };
}
```

- [ ] **Step 2: Register the module — host-scoped, not global**

**Do not** add `./steam-console` to `nixos/default.nix`. A NixOS `imports` list
cannot sit under `lib.mkIf` — only `config` can — so importing this module from
`nixos/default.nix` (which every host pulls in) would apply Jovian's overlay,
and its `steam`/`steam-unwrapped` override, to every host in the flake, not
just halo. `steamConsole.enable` would still correctly gate the `config` block,
but the overlay leaks regardless of that gate.

Instead, add `../../nixos/steam-console` to `hosts/halo/default.nix`'s
`imports`, beside the existing `inputs.nix-amd-ai.nixosModules.default` entry:

```nix
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./host_secrets.nix
    ../../nixos
    ../../home
    ../../overlays
    ../../secrets
    ../../options.nix
    inputs.disko.nixosModules.disko
    inputs.nixos-hardware.nixosModules.common-cpu-amd-pstate
    inputs.nixos-hardware.nixosModules.common-gpu-amd
    inputs.nixos-hardware.nixosModules.common-pc
    inputs.nixos-hardware.nixosModules.common-pc-ssd
    ../../nixos/core/lanzaboote.nix
    ../../nixos/core/iwd-known-networks.nix
    inputs.nix-amd-ai.nixosModules.default
    ../../nixos/steam-console
  ];
```

- [ ] **Step 3: Verify the ThinkPads are byte-identical, not just green**

A successful build of `thinkpad-p14s-g6` does **not** prove the import changed
nothing — Jovian's overlay swaps `programs.steam.package` for a build that
still evaluates and builds fine, it just resolves to a different derivation.
The real gate is a `drvPath` comparison of `programs.steam.package` between
base and branch:

```bash
git add nixos/steam-console/default.nix hosts/halo/default.nix
nix eval .#nixosConfigurations.thinkpad-p14s-g6.config.steamConsole.enable
```

Expected: `false`

```bash
nix eval --raw .#nixosConfigurations.thinkpad-p14s-g6.config.programs.steam.package.drvPath
```

Expected: byte-identical to the same eval on `main` (`git stash` or a worktree
of `main` gives the baseline). Any difference means the overlay leaked and the
import is not properly host-scoped — do not proceed until this matches.

```bash
nh os build .#thinkpad-p14s-g6
```

Expected: builds successfully — necessary, but only the `drvPath` match above
actually proves the desktop host is unaffected.

- [ ] **Step 4: Commit**

```bash
git add nixos/steam-console/default.nix hosts/halo/default.nix
git commit -m "feat(console): add Jovian Gaming Mode module

Refs #210"
```

---

### Task 4: Enable console mode on halo

**Files:**
- Modify: `hosts/halo/default.nix` (`steamConsole.enable`; `lemonade.settings`;
  `systemd.services.games-nodatacow`; `systemd.tmpfiles.rules`)

**Interfaces:**
- Consumes: `steamConsole.enable` (Task 2), the console user from Task 3.
- Produces: a halo system closure with Gaming Mode. Task 5 activates it.

- [ ] **Step 1: Turn console mode on**

In `hosts/halo/default.nix`, after the `machine.type` / `machine.serverMode`
lines:

```nix
  # Couch console on the TV. Runs as its own unprivileged user, so autologin
  # never reaches noams's SSH keys, sudo, or the agents.
  steamConsole.enable = true;
```

- [ ] **Step 2: Let lemond yield memory to games**

In the existing `hardware.amd-npu.lemonade` block, alongside `cacheDir`:

```nix
      # Games and lemond both draw from the same GTT pool. auto_evict unloads
      # idle models under memory pressure and reloads on the next request, so a
      # game does not need the endpoint stopped. Unverified whether this
      # observes a game's allocations specifically — see the plan's Task 5
      # measurement; if it does not, stop lemond before gaming, as with ds4.
      settings.auto_evict = true;
```

- [ ] **Step 3: Add ownership and nodatacow for the games subvolume**

disko creates `@games` as `root:root`, exactly as it does `@models`. Extend the
existing `systemd` block. Add to `systemd.services`, next to `models-nodatacow`:

```nix
      # Same rationale as models-nodatacow: game files are partially rewritten
      # by updates, which CoW shatters into extents. Must land before Steam
      # writes anything, since the flag only affects files created after it.
      games-nodatacow = {
        description = "Disable btrfs CoW on /var/lib/games";
        wantedBy = ["multi-user.target"];
        unitConfig.RequiresMountsFor = "/var/lib/games";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.e2fsprogs}/bin/chattr +C /var/lib/games";
        };
      };
```

Add to the existing `systemd.tmpfiles.rules` list:

```nix
      "d /var/lib/games 0700 ${config.steamConsole.user} users -"
```

Note: `hosts/halo/default.nix`'s argument list is currently
`{pkgs, inputs, ...}`. Add `config` to it — the tmpfiles rule needs
`config.steamConsole.user`.

- [ ] **Step 4: Verify the closure builds**

```bash
git add hosts/halo/default.nix
nix eval .#nixosConfigurations.halo.config.steamConsole.enable
```

Expected: `true`

```bash
nix eval .#nixosConfigurations.halo.config.users.users.steam.home
```

Expected: `"/var/lib/games"`

Confirm the kernel was not displaced by Jovian:

```bash
nix eval --raw .#nixosConfigurations.halo.config.boot.kernelPackages.kernel.version
```

Expected: a 7.x version matching `linuxPackages_latest` — **not** a
`neptune`-suffixed version. If it is neptune, `jovian.devices.steamdeck` got
enabled somewhere; stop and fix before proceeding.

```bash
nh os build .#halo
```

Expected: builds successfully. `gamescope` may build from source on a cache miss.

- [ ] **Step 5: Commit**

```bash
git add hosts/halo/default.nix
git commit -m "feat(halo): enable Steam Machine console mode

Refs #210"
```

---

### Task 5: Activate and verify on the box

This task has no code. It is the only place the spec's claims about hardware get
tested, and several cannot be checked any other way — halo has never driven a
display.

**Files:** none.

**Interfaces:**
- Consumes: the closure from Task 4.
- Produces: a verdict on the `auto_evict` open risk, to be written back into the
  spec.

- [ ] **Step 1: Attach a display and controller**

Connect halo to the TV over HDMI and put a controller in pairing mode. Note
which TV input, for the CEC check.

- [ ] **Step 2: Activate**

```bash
nh os switch .#halo
```

- [ ] **Step 3: Verify noams's workflow is untouched — do this BEFORE rebooting**

```bash
ssh halo systemctl is-active lemond
```

Expected: `active`. If this regressed, stop: the console module was supposed to
be additive.

- [ ] **Step 4: Reboot and check Gaming Mode comes up**

```bash
ssh halo sudo systemctl reboot
```

Then, from the couch, confirm in order:
1. Picture reaches the TV at all.
2. Gaming Mode appears and has autologged in.
3. `ssh halo whoami` still works and `loginctl` shows the session as the console
   user, not `noams`.

- [ ] **Step 5: Verify controller, audio and CEC**

1. Controller pairs and navigates the UI.
2. Audio reaches the TV (play anything with sound).
3. **CEC:** the TV remote's direction pad moves the Gaming Mode cursor. If not,
   check `systemctl status cecd` and that the TV has CEC enabled — most vendors
   ship it under a brand name (Anynet+, Bravia Sync, Simplink).

- [ ] **Step 6: Measure the `auto_evict` open risk**

This settles the spec's largest unknown.

```bash
ssh halo systemctl is-active lemond    # confirm loaded
```

Start a game, then from another terminal:

```bash
ssh halo 'cat /sys/class/drm/card*/device/mem_info_gtt_used'
ssh halo 'curl -s localhost:13305/api/v1/health'
```

Record whether lemond unloaded its models under the game's allocation pressure,
and whether the next request after the game reloads them.

- [ ] **Step 7: Write the verdict back into the spec**

Edit the "Open risks" section of
`docs/superpowers/specs/2026-09-04-halo-steam-machine-design.md` to record what
actually happened, replacing the "Unverified" language either way.

```bash
git add docs/superpowers/specs/2026-09-04-halo-steam-machine-design.md
git commit -m "docs(halo): record auto_evict measurement result

Refs #210"
```

- [ ] **Step 8: Push and open the PR**

```bash
git push
gh pr create --assignee @me --title "feat(halo): Steam Machine console mode" --body "Closes #210"
```

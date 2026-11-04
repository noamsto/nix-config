# halo Steam Machine mode — design

**Issue:** [#210](https://github.com/noamsto/nix-config/issues/210)
**Date:** 2026-09-04
**Builds on:** [2026-08-29-halo-host-design.md](2026-08-29-halo-host-design.md),
[2026-09-01-halo-llm-inference-design.md](2026-09-01-halo-llm-inference-design.md)

## Purpose

halo sits under the TV and boots unattended to serve inference. This adds a
second role: a couch console, reached by switching the TV to its input, running
Steam Gaming Mode as a **dedicated unprivileged user** so autologin never exposes
`noams`'s SSH keys, sudo, or agent access.

The inference role stays primary and unchanged. Nothing here alters how `noams`
logs in, what `desktop.mode` means, or how lemond and ds4 are configured beyond
one eviction setting.

## What is already in place

halo was provisioned with this in mind, though nothing turns it on:

| Already there | Where | Why it matters |
|---|---|---|
| `machine.type = "desktop"` | `lib/host-configs.nix:51` | its own comment says this is to get `pc.nix`'s pipewire `alsa.support32Bit` (Steam) and bluetooth (controller) |
| `@games` subvolume at `/var/lib/games`, `noatime` | `hosts/halo/disko.nix` | game library storage, already separated from `@home` |
| headless, no display manager, TPM auto-unlock | `hosts/halo/default.nix` | the constraint the separate-user decision protects |

The gap: `desktop.mode = "none"`, so the `programs.steam` block in
`nixos/desktop/default.nix` (gated on `desktop.isEnabled`) never applies to halo.

## Approach: a `steamConsole` axis orthogonal to `desktop.mode`

`desktop.mode` governs whether **`noams`** gets a desktop — it drives both
`nixos/desktop` and the `home/desktop` import in `home/noams.nix`. The console
session runs as a *different user*, so none of `noams`'s configuration should
change, and therefore neither should `desktop.mode`.

Rejected alternatives:

- **`desktop.mode = "console"` as a fourth enum value.** Flips
  `desktop.isEnabled` true on halo, pulling in chromium, zoom, flatpak, qt,
  hyprland portals *and* all of `home/desktop` for `noams`. Would require
  threading `isConsole` exceptions through modules unrelated to gaming.
- **`desktop.mode = "hyprland"` with Steam layered on.** Drags the entire desktop
  onto a box whose purpose is to stay headless for agents.

## Why Jovian-NixOS

Two findings from design-time investigation, both of which had to hold before
Jovian was viable on this host:

1. **It does not pin a kernel on non-Deck hardware.** `linux-neptune` lives in
   `modules/devices/steamdeck/kernel.nix`, gated behind the Deck *device* module.
   With `jovian.devices.steamdeck` off, halo keeps `pkgs.linuxPackages_latest`,
   which it needs for gfx1151 support.
2. **Its overlay does not replace `mesa` or `pipewire`.** It *adds*
   `mesa-radeonsi-jupiter`, `mesa-radv-jupiter`, `pipewire-jupiter` as new
   attributes rather than replacing `mesa`/`pipewire`, so the nix-amd-ai ROCm
   stack is untouched. It *does* override `steam` and `steam-unwrapped`
   (`overlay.nix:98-103`), plus `inputplumber` (`37-39`), `mangohud` (`41-43`)
   and `gamescope` (`25-28`) — this is precisely why the module
   must be imported per-host rather than globally: a NixOS `imports` list
   cannot sit under `lib.mkIf`, so a global import would apply this overlay,
   and its `steam` override, to every host in the flake.

Jovian also requires `nixos-unstable`, which this flake already tracks
(`flake.nix:70`).

What it buys over hand-rolling `programs.steam.gamescopeSession`:
`jovian.steam.user` (the dedicated-account model, built in), the actual Deck UI,
Decky, and the session plumbing that otherwise has to be hand-rolled.

**Not HDMI-CEC.** An earlier draft of this document listed CEC — the TV remote
driving the box — as the deciding advantage. That was wrong, and it was asserted
without testing the hardware. `amdgpu` imports only the CEC *notifier*
(`cec_notifier_conn_register`, `cec_notifier_set_phys_addr`) and DisplayPort AUX
tunnelling (`drm_dp_cec_*`); it never calls `cec_allocate_adapter`, so it
registers no HDMI CEC adapter. Measured on halo with the TV live on
`HDMI-A-1`: no `/dev/cec*` and no `/sys/class/cec`. This kernel compounds it by
building only `cec.ko` core (`CONFIG_MEDIA_CEC_SUPPORT` unset), so there is no
userspace CEC API at all.

CEC is not impossible here, just not worth it: halo has eight DisplayPort
outputs and `drm_dp_cec_*` is real, so a DP->HDMI adapter implementing
CEC-Tunneling-over-AUX plus a kernel rebuilt with `CONFIG_MEDIA_CEC_SUPPORT`
would work. That is a custom kernel on a host deliberately tracking
`linuxPackages_latest`, recompiled on every bump. The Jovian choice stands on
its other merits.

## Components

### 1. `options.nix`

```nix
steamConsole = {
  enable = mkOption { type = types.bool; default = false; };
  user = mkOption { type = types.str; default = "steam"; };
  autoStart = mkOption { type = types.bool; default = true; };
};
```

No derived booleans — nothing needs them yet (YAGNI).

**Not `console`.** nixpkgs already declares `options.console` for the virtual
console/TTY (`nixos/modules/config/console.nix:51` — `console.enable`,
`console.font`, `console.keyMap`). Declaring our own `console.enable` is a hard
module-system conflict, not a mergeable override: evaluation fails with "The
option `console.enable' ... is already declared". The module directory is
`nixos/steam-console/` to match.

An assertion rejects `steamConsole.enable && desktop.isEnabled`: both want the
display, and Jovian's autostart path owns the display manager.

### 2. `nixos/steam-console/default.nix`

Imported from `hosts/halo/default.nix`, not from `nixos/default.nix`, and
self-gated on `steamConsole.enable` within that import. `lib.mkIf` gates
`config`, but never `imports` — a NixOS module's `imports` list is always
evaluated regardless of any `mkIf` around its `config` block. Importing this
module globally would therefore apply Jovian's overlay (see "Why Jovian-NixOS"
above) to every host in the flake, not just halo, even though
`steamConsole.enable` would still correctly gate the `config` it produces.
Host-scoping the import is the only way to keep the overlay off every other
host.

- `jovian.steam.{enable, autoStart, user}` from the options above
- `jovian.hardware.has.amd.gpu = true`
- `jovian.steamos.enableHdmiCecIntegration = false` — **must be set
  explicitly.** It inherits `jovian.steamos.useSteamOSConfig`, which evaluates
  true here, so leaving it alone starts `cecd` against an adapter that does not
  exist. See "Why Jovian-NixOS" below.
- `jovian.steam.desktopSession = "gamescope-wayland"` — **required whenever
  `autoStart` is on.** Jovian's autostart unit interpolates this into an
  `ExecStart` unconditionally (`modules/steam/autostart.nix:106`) while the
  option itself defaults to `null`, so leaving it unset fails evaluation with
  `cannot coerce null to a string`. halo has no desktop to switch to, and
  `"gamescope-wayland"` is the value Jovian's own check message prescribes for
  that case: "Switch to Desktop" simply relaunches Gaming Mode.

No `programs.steam` block is needed. Jovian's `modules/steam/steam.nix:36` sets
`programs.steam.enable = mkDefault true` itself, along with `hardware.graphics`
and `hardware.steam-hardware.enable`. The docs line "to enable *desktop* Steam,
enable the usual NixOS options" refers to the Steam desktop app inside a DE, not
to Gaming Mode.

`remotePlay.openFirewall` is deliberately **not** set: halo keeps ports off the
LAN and reaches the ThinkPads over tailscale, matching the posture the host
config already documents for lemond and ds4.

### 3. Console user and storage

A normal system user: **not** in `wheel`, no `openssh.authorizedKeys`, groups
limited to `video`, `render`, `input`, `audio`.

That group list understates what the console user can actually reach: Jovian's
`modules/steam/steam.nix:160` installs a polkit rule granting any **local
active session** in group `users` unconditional `yes` on all
`org.freedesktop.NetworkManager.*` actions. It is halo-only (the rule ships
only when `jovian.steam.enable` is on, which is host-scoped — see Components
§2) and local-only (an SSH session is not an "active local session", so `noams`
over SSH is unaffected), but it does mean whoever holds the TV remote can
reconfigure halo's networking. This is inherent to Jovian's Deck UI and is
accepted here rather than worked around.

`home = "/var/lib/games"` — the subvolume root *is* the console user's home, so
`~/.local/share/Steam`, Proton prefixes and shader caches all land there rather
than on `@home`.

disko creates the subvolume `root:root`, exactly as it does for `@models`, so
ownership needs a `systemd.tmpfiles` rule alongside the existing `@models` ones
in `hosts/halo/default.nix`:

```
d /var/lib/games 0700 <console-user> users -
```

A `games-nodatacow` oneshot mirroring the existing `models-nodatacow` unit: game
files are partially rewritten by updates, which is exactly the CoW-shattering
case the `@models` comment already documents. The flag only takes on files
created after it is set, so it must land before Steam writes anything — ordered
the same way `models-nodatacow` is, via `RequiresMountsFor`.

### 4. GPU coexistence

`hardware.amd-npu.lemonade.settings.auto_evict = true` on halo — lemond frees
idle models under memory pressure and reloads on the next request.

**No automatic arbitration between the session and the inference servers.** The
mechanism initially planned (systemd `Conflicts=`, as `exclusiveInference` uses
at `amd-npu.nix:842`) does not work here: Jovian's `gamescope-session` is a
`systemd.user.service` (`modules/steam/autostart.nix:117`), and a user unit
cannot `Conflicts=` a system unit.

It is also not needed. `ds4.autoStart = false` already, so an 80.76 GiB model is
only resident when deliberately started. lemond coexists via `auto_evict`. The
sole collision is manually starting ds4 mid-game — a deliberate act, not an
accident to defend against.

If that proves wrong, the fallback is a polkit rule granting the console user
`manage-units` on exactly `lemond.service` and `ds4-server.service`, plus
`ExecStartPre`/`ExecStopPost` overrides on Jovian's user unit. Deliberately not
built now.

### 5. Flake input and caches

Jovian input following `nixpkgs`. Its cache must be added to **both**
`flake.nix:nixConfig` and `lib/caches.nix` — CLAUDE.md flags these as needing to
stay in sync:

```
https://jovian-nixos.cachix.org
jovian-nixos.cachix.org-1:mAWLjAxLNlfxAnozUjOqGj4AxQwCl7MXwOfu7msVlAo=
```

(Verified live against `https://jovian-nixos.cachix.org/nix-cache-info` and the
Cachix API; Jovian's own docs page for this 404s.)

## Verification

Build gate: `nh os build .` for halo.

On-box, in order — each is a thing that cannot be verified by evaluation:

1. Display output reaches the TV at all (halo has never driven a display).
2. Gaming Mode starts and autologs in as the console user.
3. Controller pairs over bluetooth.
4. Audio reaches the TV through pipewire.
6. `noams`'s SSH/tmux/agent workflow is unaffected while a session runs.
7. **Measurement:** start a game with lemond loaded, watch whether `auto_evict`
   observes the game's allocations and unloads.
8. **Measurement:** with `autoStart = true`, gamescope and Steam are resident
   24/7 on a box whose primary job is inference, not just while a game runs.
   Measure the **idle** cost — GTT and RAM usage with Gaming Mode up but no
   game running — so the standing overhead on the inference role is known.

## Open risks

- **`auto_evict` may only see lemonade's own models**, not external VRAM
  pressure from a game. Unverified; step 7 above measures it. If it does not,
  the honest fallback is that lemond and games do not coexist, and lemond gets
  stopped manually before gaming — the same posture ds4 has today.
- **`gamescope` builds from source on a cache miss.** halo has 16 cores; a first
  switch may be slow.
- **`nixos/desktop/sddm` is dead code** — gated `isDesktop && !isHypr`, which
  cannot be true given the `none | hyprland` enum. Jovian's autostart owns its
  own display manager, so this stays dead. Out of scope here; worth deleting
  separately.

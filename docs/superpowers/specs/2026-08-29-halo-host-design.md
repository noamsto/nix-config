# AMD Strix Halo host — design

**Issue:** [#175](https://github.com/noamsto/nix-config/issues/175)
**Date:** 2026-08-29

## Purpose

A new host for an AMD Strix Halo (Ryzen AI Max) box with 128 GB unified memory,
living under the TV. Three roles, in priority order:

1. **LLM inference server** (primary) — reachable from the ThinkPads over Tailscale.
2. **Headless server** — podman containers for background services.
3. **Steam machine** (occasional) — turn on the TV, switch to its HDMI input,
   and Big Picture is already there. No keyboard, no ssh, no laptop.

The workload split is roughly 90% server / 10% games. That ratio drives several
decisions below; if it shifts, revisit the Steam session choice first.

## Topology: one bare-metal NixOS install

No dual-boot and no VM touching the GPU.

Strix Halo has a single iGPU and no SR-IOV. A GPU-passthrough VM would blind the
host while the guest ran, and the unified-memory split would have to be
negotiated across two schedulers. The only real argument for dual-booting
Windows was kernel anti-cheat, which is not needed here.

VMs and containers still have a job, just a GPU-less one: podman via
`virtualisation.oci-containers` for server services. Real VMs only if something
untrusted needs isolating later.

If Windows is ever wanted, most Halo boards have a second M.2 slot — add it on
its own disk then, rather than partitioning for it now.

## Storage

Single NVMe. disko, LUKS, btrfs — modelled directly on
`hosts/thinkpad-p14s-g6/disko.nix`, with three deltas.

| Subvolume | Mountpoint | Options |
|---|---|---|
| `@` | `/` | `compress=zstd,noatime` |
| `@home` | `/home` | `compress=zstd,noatime` |
| `@nix` | `/nix` | `compress=zstd,noatime` |
| `@log` | `/var/log` | `compress=zstd,noatime` |
| `@models` | `/var/lib/models` | `noatime` (no compression) |
| `@games` | `/var/lib/games` | `noatime` (no compression) |
| `@swap` | `/swap` | `noatime` |

**Delta 1 — `@models` and `@games` are uncompressed.** GGUF quants and Steam
depots are already compressed; zstd buys nothing and costs decompression on
every read of a multi-gigabyte file.

**Delta 2 — they are separate subvolumes.** Btrfs does not snapshot
recursively, so carving them out keeps a snapshot policy from ever pinning
multiple copies of a 70B model or a large Steam library. This is the bigger win
of the two.

Both paths need to actually be used: `llama-server` is pointed at
`/var/lib/models`, and Steam must have `/var/lib/games` added as a library
folder (Steam's default is `~/.local/share/Steam`, which would land games on
`@home` and inside any snapshot policy). The library folder is set once in the
Steam UI on first run; it is not something the Nix config asserts.

**Delta 3 — 1 GB ESP** instead of g6's 512 MB. Lanzaboote signs each generation
into the ESP; 512 MB gets tight on a host that will be rebuilt often.

**Swap and hibernation.** Keep `@swap` with a modest swapfile as ballast (or use
zram). Do not configure hibernation: a 128 GB resume image is not worth it, and
`resumeDevice` stays unset.

## Boot

Lanzaboote Secure Boot plus TPM2 LUKS auto-unlock, same as g5/g6 — see the
`secure-boot-tpm` skill. Auto-unlock is not optional here: a box under the TV
that stops at a passphrase prompt means walking over with a keyboard.

**Enroll a strong recovery passphrase alongside the TPM token from day one.**
TPM2 unlock against PCR 7 breaks on BIOS updates; this is exactly the situation
that had to be recovered from on g6.

## Memory split — the highest-risk area

The 128 GB is unified, and Linux handles it very differently from Windows.

- **Set the BIOS UMA / dedicated VRAM to minimum** (typically 512 MB). This is
  the opposite of the usual Windows advice. On Linux the GPU should draw from
  the GTT window, which is flexible and reaches far beyond any BIOS setting.
- **Size GTT via kernel parameters** (`amdgpu.gttsize`, `ttm.pages_limit`).
  Recent kernels auto-size GTT to roughly half of RAM; exceeding that needs the
  explicit parameters.

Published guidance in this area has rotted badly across kernel versions. Treat
specific numbers as unvalidated until measured against the kernel this host
actually lands on. This is the single most likely thing in the design to need
adjustment after first boot.

## LLM stack

`llama-cpp` with `vulkanSupport = true` (verified: the override evaluates
against the pinned nixpkgs), exposed as an OpenAI-compatible `llama-server`
systemd unit bound to the Tailscale interface so the ThinkPads point at it
directly.

Vulkan first rather than ROCm: gfx1151 has had a rough ROCm road, the nixpkgs
ROCm stack lags, and the Vulkan backend has been competitive-to-better on Halo,
particularly for prompt processing. Benchmark a ROCm build side by side
afterwards and keep whichever wins — both are a package attribute in the same
module. `services.ollama.rocmOverrideGfx` exists if the
`HSA_OVERRIDE_GFX_VERSION` workaround is needed.

Models live on `/var/lib/models`.

## Steam session

**`programs.steam.gamescopeSession.enable = true` with greetd autologin.**

The requirement — TV on, switch input, it's already there — means the session
must be *running*, not started on demand. greetd rather than SDDM: a few lines,
and it does not drag in a desktop environment. The session comes up at boot and
stays up.

The cost is small: idle Steam plus gamescope is on the order of 1–2 GB and
effectively no GPU, so the host's server character is unchanged.

### Not Jovian-NixOS

Jovian was seriously considered and rejected on the workload split. What it
provides that nixpkgs does not: `gamescope-session`, `steamos-manager`,
`powerbuttond`, `holo-polkit-helpers`, `vpower`, `dmemcg-booster`,
`galileo-mura` (verified absent from nixpkgs). That is a real gap — most
visibly `steamos-manager`, the D-Bus service behind in-UI performance, TDP, and
brightness controls, and `powerbuttond`, which maps the power button to Steam's
power menu.

Against that: the overlay globally replaces `gamescope`, `mangohud`, and
`inputplumber` with Valve's forks, and it is another fast-moving flake input.
At a 90/10 split those costs are paid on every rebuild to serve the 10%.

Two things that were *not* reasons to reject it, having checked the source:

- The Deck-forked mesa (`mesa-radeonsi-jupiter`, `mesa-radv-jupiter`) and the
  Jovian kernel are gated behind `jovian.devices.steamdeck.enable`, which would
  not be set. Stock nixpkgs graphics are kept — which matters, since Strix Halo
  needs a *recent* mesa and kernel, not Valve's Deck-pinned ones.
- `jovian.steam.autoStart` is documented as incompatible with a traditional
  display manager. That constrains the design but does not rule it out.

Adding Jovian later is a flake input plus a session swap; the disk layout, LLM
stack, and services are unaffected. That door stays cheap to open, and should be
opened if the couch experience is poor.

## LLM ↔ game arbitration

`programs.gamemode.settings.custom.start` stops `llama-server`;
`programs.gamemode.settings.custom.end` starts it again. (Verified: the option
exists and takes shell commands.)

This triggers on actual game launch rather than session start, so the model
stays loaded and serving the ThinkPads the entire time the TV is off. No daemon,
no manual `systemctl`, no ssh.

## Known risk: HDMI connector availability

When the TV is off or on another input, HDMI hot-plug detect typically drops and
the kernel sees no display attached. A gamescope session starting at boot with
no connector may fail outright — the failure mode that would make the whole
couch UX flaky at exactly the wrong moment.

Two mitigations, both applied:

- Force the connector enabled regardless of TV state with a kernel parameter
  (`video=HDMI-A-1:1920x1080@60e`; the trailing `e` forces enable), plus a
  custom EDID via `drm.edid_firmware` if the TV's EDID is unreadable while off.
- `Restart=always` on the session unit as a backstop, so it retries into
  existence if the connector appears late.

**This needs hands-on validation at install.** TVs vary considerably in whether
they hold HPD on standby, and no configuration can promise the behaviour in
advance.

## Host options and repo integration

```nix
machine.type = "server";
machine.serverMode = true;   # no autonomous suspend; ssh/tmux survive
desktop.mode = "none";
profile = "personal";
```

Note `desktop.mode`'s enum is `["none" "hyprland"]` — there is no `"kde"`
(`options.nix:11`). The repo's `CLAUDE.md` is stale on this point and should be
corrected.

Integration follows the existing pattern: a new directory under `hosts/`, an
entry in `lib/host-configs.nix`, and a `nixosConfigurations` entry in
`flake-modules/nixos-systems.nix`.

## Other services

- **Tailscale** — the LLM API and ssh bind here rather than the LAN.
- **SSH** — primary administrative access.
- **Sunshine** (`services.sunshine`, with `capSysAdmin` for the Wayland KMS
  grab) for streaming to the ThinkPads via Moonlight.
- **podman** via `virtualisation.oci-containers` for background services.

## Open items for install time

1. GTT sizing parameters, validated against the shipped kernel.
2. HDMI connector forcing — whether the `video=` parameter alone suffices, or a
   custom EDID is needed.
3. Vulkan vs. ROCm benchmark for `llama-server`.
4. Exact NVMe device path for the disko configuration.

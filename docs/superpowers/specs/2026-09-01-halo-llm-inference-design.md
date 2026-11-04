# halo LLM inference server — design

**Issue:** [#175](https://github.com/noamsto/nix-config/issues/175) (Stage 2)
**Date:** 2026-09-01
**Supersedes:** the "LLM stack" section of
[2026-08-29-halo-host-design.md](2026-08-29-halo-host-design.md)
**Implemented by:** [2026-08-30-halo-host-stage2.md](../plans/2026-08-30-halo-host-stage2.md)
— Tasks 1, 2, 2b, 3, 4, 4b. That plan already carried the module choice, the
gfx1151 target, the 13305 bind and the modprobe conflict; this document adds the
cache redirect, `ds4-server`, and the API-key note, which it was missing.

## Purpose

Stage 1 (#179) left halo bootable: LUKS, Secure Boot, TPM unlock, a 96 GiB GTT
window, and an uncompressed nodatacow `@models` subvolume (#192). Nothing serves
inference yet. This stage makes halo do its primary job.

## What changed since the stage-1 design

The stage-1 design specified a hand-rolled `llama-server` systemd unit. That is
now the wrong answer: `nix-amd-ai` — our own flake, already a pinned input and
already imported on g6 — ships a `hardware.amd-npu` module that covers it, with
a declarative model list and reconcile units we would otherwise reimplement.

That module also makes halo the **reference Strix Halo host for nix-amd-ai**.
Until now the module has only ever run on Strix Point (g6, gfx1150). Gaps found
here are upstream bugs, not local workarounds: fix them in nix-amd-ai and bump
the lock, rather than papering over them in `hosts/halo/`.

## Architecture

Two independent OpenAI-compatible servers from the one module.

| Unit | Serves | Port | Backend |
|------|--------|------|---------|
| `lemond` | general model set, declarative `lemonade.models` | 13305 | ROCm + Vulkan |
| `ds4-server` | DeepSeek-V4-Flash only, `--ssd-streaming` | 8000 | ROCm only |

Those are the module's own defaults and do not collide, so neither port needs
setting. They are siblings — `hardware.amd-npu.ds4` is a top-level option, not
nested under `lemonade` — so either can fail without taking the other down.

GPU access differs between the two, which is easy to get wrong: `ds4-server`
sets `SupplementaryGroups = ["video" "render"]` in its own unit, but `lemond`
does not, so `noams` still needs `extraGroups = ["video" "render"]` exactly as
on g6. (The `ds4.user` option's description says the user "must be in the render
and video groups" even though the unit supplies them — an upstream doc nit worth
fixing while we are in there.)

`pkgs.ds4` already defaults to `gpuTarget = "gfx1151"`, so halo needs no package
override — the DeepSeek path was built for this chip.

`ds4.model` is deliberately typed as a string, not a path, so a multi-GB GGUF is
referenced at runtime instead of being copied into the Nix store. The corollary
is that **nothing provisions it**: `lemonade.models` has reconcile units, `ds4`
has no equivalent, so the GGUF is fetched by hand into
`/var/lib/models/gguf/` before first start or the unit restart-loops. That
asymmetry is itself an upstream candidate.

### Backend choice

Both ROCm and Vulkan are enabled. The stage-1 design argued Vulkan-first on the
grounds that gfx1151 ROCm has been unreliable; that reasoning still holds, and
enabling both is how we test it rather than a hedge. `ds4-server` is ROCm-only,
so ROCm has to work for the DeepSeek path regardless. Benchmark and record the
winner per model class; `lemond` already carries `Restart=on-failure`.

## Storage

`@models` becomes the single root for weights. This matters more than it looks:
g6 currently holds **157 GB** under `~/.cache/huggingface` (147 GB) and
`~/.cache/lemonade` (9.9 GB). On halo that path is `@home` — `compress=zstd`
plus CoW, both actively harmful for weights.

```
/var/lib/models/hf/         HF_HOME for lemond
/var/lib/models/lemonade/   lemonade's own cache
/var/lib/models/gguf/       plain GGUFs; ds4.model points here
```

`lemond` runs as a normal user and inherits the default HF cache location, so
without a redirect the `@models` subvolume sits empty and the 157 GB lands on
the wrong subvolume. The redirect is an **upstream option** in nix-amd-ai, not a
local unit override: the module owns the unit, and a local `environment` poke
would silently stop working if upstream renamed anything. g6 gets the same
option for free.

## Exposure

Both servers bind `0.0.0.0` — overriding the `localhost` / `127.0.0.1`
defaults — and neither port is added to `allowedTCPPorts`.
`nixos/services/tailscale.nix` already sets `trustedInterfaces = ["tailscale0"]`,
so tailnet traffic is accepted and LAN traffic is dropped by default.

This is chosen over literally binding the `tailscale0` address, which would race
`tailscaled` at boot and leave the units restart-looping until an address
appeared. Same reachability, no race, no retry loop. The endpoints are
unauthenticated, so the firewall is the only thing between them and the TV's
network segment — that is the reason the port must stay out of
`allowedTCPPorts`.

**Prerequisite:** halo's `tailscaled` is active but `NeedsLogin`. `tailscale up`
is a hands-on step and blocks validation, though not the build.

## Memory split — a conflict to resolve

`hosts/halo/default.nix` hand-rolls the GTT window:

```nix
boot.extraModprobeConfig = ''
  options ttm pages_limit=25165824 page_pool_size=25165824
'';
```

The module emits that same line from `gpuMemory.ttmSizeGiB`. `extraModprobeConfig`
is `types.lines`, so enabling the module without removing the block appends a
*second* `options ttm pages_limit=` line rather than replacing the first.

Convert it in the same commit: `25165824 / 262144 = 96`, so `ttmSizeGiB = 96`
and `pagePoolSizeGiB = 96` produce byte-identical output. Keep the existing
comment explaining why `amdgpu.gttsize` is deliberately absent.

## Models

Declared, not pulled by hand — g6's 16 models are entirely imperative and
undocumented, which is the state this avoids.

- `Qwen3.5-4B-GGUF` — small and fast, for cheap tasks.
- `Qwen3-Coder-30B-A3B-Instruct-GGUF` — the large coder MoE, already proven on g6.
- DeepSeek-V4-Flash, as a plain GGUF under `/var/lib/models/gguf/`, for `ds4`.

Exact lemonade catalog identifiers are confirmed against `lemonade-server list`
during implementation; the names above are the g6 cache directory names.

`pruneUnlistedModels` already defaults to `false`, so anything pulled by hand
for testing survives a rebuild without setting anything. Revisit once the
declared set is trusted.

Most of g6's models exist because g6 is RAM-constrained; halo does not need the
small quants, and mirroring them would cost ~157 GB of downloads for models it
should never serve.

## Out of scope

One-line additions once the box is proven, deliberately excluded so that a
failure has one plausible cause:

- `enableNPU` / `enableFastFlowLM` — Strix Halo's XDNA2 is a second unproven
  variable, and the iGPU is the point of a 128 GB box.
- `enableVllm`, `enableImageGen`.
- Steam / gamescope, Sunshine, and the gamemode arbitration that stops
  `llama-server` around a game launch — all downstream of a working session, and
  all needing hands-on time at the TV.

## Sequencing

1. **nix-amd-ai** — add the cache-directory option; fix whatever else gfx1151
   surfaces. Own repo, own PR.
2. **nix-config** — bump `flake.lock`, then one PR enabling `hardware.amd-npu`
   on halo: `gpuTarget = "gfx1151"`, ROCm + Vulkan, the `gpuMemory` conversion
   above, `lemonade.models`, `ds4`, and `noams` into `render`/`video`.
3. **Deploy and validate** — `tailscale up`, rebuild from a ThinkPad
   (`--target-host`; halo cannot evaluate the flake itself), confirm both
   endpoints answer over the tailnet and that weights landed on `@models`.

## Risks

| Risk | Mitigation |
|------|-----------|
| gfx1151 ROCm unproven; `ds4-server` is ROCm-only | Vulkan enabled alongside for `lemond`; treat failures as upstream nix-amd-ai bugs |
| Model downloads are multi-hour and can mask a config fault | Minimal declared set; verify the endpoint answers before growing it |
| `ds4-server` restart-loops if its GGUF is absent | Fetch the DeepSeek GGUF before enabling `ds4`, or land `ds4.enable` in a follow-up commit |
| Weights silently land on `@home` | Assert the cache path after first start — `@models` non-empty, `@home` unchanged |
| Rebuild is slow (nix-amd-ai builds from source when the cache misses) | `nix-amd-ai.cachix.org` is already configured; warn before starting a switch |

# nix-amd-ai: AMD AI Stack for NixOS

**Repo:** `noamsto/nix-amd-ai`
**Local path:** `/home/noams/Data/git/noamsto/nix-amd-ai`
**Date:** 2026-04-16

## Problem

Getting AMD NPU + ROCm GPU inference working on NixOS requires assembling packages from multiple broken/stale sources:

- `robcohen/nix-amd-npu` pins FastFlowLM to 0.9.36 (lemonade needs 0.9.38+), and `xrt-plugin-amdxdna` fails to compile because it fetches by removed git tags instead of AMD's release branches.
- XRT wrapper scripts break under NixOS's `/run/current-system/sw/bin/` symlink merging (the `unwrapped/loader` problem).
- XRT's plugin discovery (`libxrt_driver_*.so.2` scanning in `$XILINX_XRT/lib/`) requires a merged directory workaround since the Nix store is read-only.
- The `lemond` systemd service doesn't inherit environment variables, so it can't find FLM or XRT libs at runtime.

There is no single, maintained Nix flake that packages the full AMD AI inference stack correctly.

## Solution

A new flake (`nix-amd-ai`) that packages the entire stack from source, provides a NixOS module, and uses GitHub Actions CI with Cachix for binary caching.

## Packages

All built from source. All `x86_64-linux` only.

### XRT (Xilinx Runtime)

- **Source:** `Xilinx/XRT`, pinned to the commit referenced by `amd/xdna-driver`'s release branch submodule.
- **Why from source:** Large C++ project with non-standard install prefix (`opt/xilinx/xrt/`). Binary extraction is fragile across versions.
- **Key build details:** Python 3.12 build deps, generates pkg-config, installs to `$out/opt/xilinx/xrt/` with convenience symlinks at `$out/bin`, `$out/lib`.
- **Must preserve:** `bin/unwrapped/` directory structure (XRT wrapper scripts resolve `loader` relative to themselves).

### xrt-plugin-amdxdna

- **Source:** `amd/xdna-driver` **release branch `1.7`** (not tags — AMD removed them, see [xdna-driver#1236](https://github.com/amd/xdna-driver/issues/1236#issuecomment-4189743628)).
- **Why release branch matters:** The compile error (`query::aie_coredump::args` missing) occurred because `nix-amd-npu` fetched a stale tag. The `1.7` branch is AMD's supported release point.
- **Output:** `libxrt_driver_xdna.so.2` — a single shared library that XRT dlopen's from its lib directory.
- **Depends on:** XRT (build-time for headers, runtime for `libxrt_coreutil.so.2`).
- **Fallback:** If the release branch still doesn't compile, extract pre-built binary from Arch Linux `xrt-plugin-amdxdna` package as a temporary measure. Track this as an issue.

### FastFlowLM

- **Source:** `FastFlowLM/FastFlowLM`, pinned to latest release tag (currently `v0.9.39`).
- **Why from source:** Rust + C++ project, builds cleanly with nix-amd-npu's derivation (just needs version bump).
- **Depends on:** XRT (for NPU access), Boost, FFTW, FFmpeg.
- **Output:** `flm` binary in `$out/bin/`, XCLBIN model configs in `$out/share/flm/`.
- **Key detail:** Lemonade discovers FLM by searching PATH for `flm` executable.

### Lemonade

- **Source:** `lemonade-sdk/lemonade`, pinned to latest release tag (currently `v10.2.0`).
- **License:** Apache 2.0, C++.
- **Output:** `lemonade`, `lemond`, `lemonade-server` binaries plus `resources/` directory.
- **Key detail:** `lemond` searches for `resources/` relative to the binary. Must be placed next to it in the store.
- **Depends on:** zstd, zlib, openssl, libwebsockets, systemd.

## NixOS Module

Provided as `nixosModules.default`. Consumers import it and set options.

### Options

```nix
hardware.amd-npu = {
  enable = mkEnableOption "AMD XDNA NPU support";
  enableFastFlowLM = mkOption { type = bool; default = true; };
  enableLemonade = mkOption { type = bool; default = true; };
  enableROCm = mkOption { type = bool; default = false; };
  lemonade.port = mkOption { type = port; default = 13305; };
  lemonade.host = mkOption { type = str; default = "localhost"; };
};
```

### What the module configures

**Kernel & hardware:**

- Assertion: kernel >= 6.14
- Kernel params: `iommu.passthrough=0`
- Kernel modules: `amdxdna`
- Udev rules for NPU device access (`accel`/`misc` subsystems, group `video`)
- PAM limits: unlimited memlock for `@video` and `@render` groups

**xrt-combined (internal):**

- `runCommand` that merges XRT's `opt/xilinx/xrt/` tree with `xrt-plugin-amdxdna`'s `.so` via `cp -rs` + symlink overlay.
- Not exposed as a package — implementation detail for XRT's plugin discovery.

**Environment:**

- `XILINX_XRT` and `XRT_PATH` pointing to xrt-combined.
- System packages: xrt-combined, optionally fastflowlm.

**Lemonade service (`systemd.services.lemond`):**

- Runs as configured user.
- `Environment` directives for `XILINX_XRT`, `XRT_PATH`, `LD_LIBRARY_PATH` (XRT libs + optionally ROCm libs), and `PATH` (xrt-combined + fastflowlm bins).
- `LimitMEMLOCK=infinity` on the service unit for NPU buffer allocation.
- Restart on failure, 5s backoff.

**ROCm (when `enableROCm = true`):**

- Adds ROCm runtime libs (`rocmPackages.clr`) to `LD_LIBRARY_PATH` on the lemond service.
- Installs ROCm packages to system so `llamacpp:rocm` backend works.

### Consumer usage

```nix
# flake.nix
inputs.nix-amd-ai.url = "github:noamsto/nix-amd-ai";

# host config
imports = [ inputs.nix-amd-ai.nixosModules.default ];
hardware.amd-npu = {
  enable = true;
  enableFastFlowLM = true;
  enableLemonade = true;
  enableROCm = true;
};
users.users.<name>.extraGroups = [ "video" "render" ];
```

This replaces: `lib/overlays.nix` AMD entries, `packages/lemonade.nix`, `packages/xrt-plugin-amdxdna-bin.nix`, `nixos/hardware/amd-npu.nix`, `nixos/services/lemonade.nix`, and the `nix-amd-npu` flake input.

## Overlay

`overlays.default` exposes all packages as `pkgs.xrt`, `pkgs.xrt-plugin-amdxdna`, `pkgs.fastflowlm`, `pkgs.lemonade` for consumers who want packages without the module.

## Repo Structure

```
noamsto/nix-amd-ai/
  flake.nix                          # flake-parts, single system x86_64-linux
  flake.lock
  pkgs/
    xrt/default.nix                  # XRT from source
    xrt-plugin-amdxdna/default.nix   # XDNA plugin from release branch
    fastflowlm/default.nix           # FLM from source
    lemonade/default.nix             # Lemonade from source
  modules/
    amd-npu.nix                      # NixOS module (hardware + lemonade service)
  .github/workflows/
    build.yml                        # Build all packages, push to Cachix
    update.yml                       # Check upstream for new releases, open PR
```

## CI / GitHub Actions

### Build workflow (`build.yml`)

- **Triggers:** push to main, PRs.
- **Steps:** Install Nix, configure Cachix auth, `nix build .#xrt .#xrt-plugin-amdxdna .#fastflowlm .#lemonade`, push results to Cachix.
- **Runner:** `ubuntu-latest` (or larger runner if XRT build exceeds memory/time limits).
- **Cache:** Dedicated Cachix cache (e.g. `nix-amd-ai`).

### Update workflow (`update.yml`)

- **Triggers:** weekly schedule, manual dispatch.
- **Checks:**
  - `amd/xdna-driver` branch `1.7` for new commits (affects XRT + plugin).
  - `FastFlowLM/FastFlowLM` for new release tags.
  - `lemonade-sdk/lemonade` for new release tags.
- **Action:** If new versions found, update `rev`/`version`/`hash` in the package files, open a PR. CI build on the PR validates everything compiles.
- **Hash update:** Use `nix-prefetch-url` or `nix flake prefetch` to compute new hashes.

### Cachix setup

- Create `nix-amd-ai` Cachix cache.
- Add `CACHIX_AUTH_TOKEN` to repo secrets.
- Consumers add `nix-amd-ai.cachix.org` to their substituters (the module can do this automatically via `nix.settings`).

## Migration from nix-config

After the flake is working:

1. Add `nix-amd-ai` input to `nix-config/flake.nix`.
2. Import `inputs.nix-amd-ai.nixosModules.default` in G6 host config.
3. Set `hardware.amd-npu` options.
4. Remove from nix-config:
   - `nix-amd-npu` flake input
   - AMD entries in `lib/overlays.nix`
   - `packages/lemonade.nix`
   - `packages/xrt-plugin-amdxdna-bin.nix`
   - `nixos/hardware/amd-npu.nix`
   - `nixos/services/lemonade.nix`
5. Add `nix-amd-ai.cachix.org` to `lib/caches.nix` and `flake.nix` nixConfig.

## Open Questions / Risks

1. **xrt-plugin-amdxdna on release branch `1.7`:** Untested — might still have compile issues. Fallback is Arch binary extraction. Will validate during implementation.
2. **Lemonade from source:** Build system not yet explored. May need patches for Nix sandbox compatibility. Fallback is RPM extraction (current approach).
3. **XRT + plugin ABI compatibility:** When updating independently, soname `.so.2` stays the same but internal ABI could break. The update workflow should bump both together when xdna-driver updates.
4. **ROCm scope:** Just `LD_LIBRARY_PATH` for lemonade, or full ROCm/HIP stack? Starting minimal — just enough for `llamacpp:rocm` backend.
5. **CI runner resources:** XRT is a large build. May need `ubuntu-24.04` large runner or build caching strategies.

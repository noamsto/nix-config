---
name: thinkfan-tuning
description: Use when editing ThinkPad fan behavior, thinkfan config, fan curves, sensor paths, or fixing fan oscillation / noise / thermal throttling on thinkpad-p14s hosts. Covers the custom `hardware.thinkpad.thinkfan` option in nixos/hardware/thinkfan.nix (gen4/gen5/gen6 generations).
---

# Thinkfan Tuning

## Overview

This repo defines a custom NixOS option `hardware.thinkpad.thinkfan` (in `nixos/hardware/thinkfan.nix`) that wraps `services.thinkfan` with generation-aware sensor paths and a shared fan curve. Enable it per-host with `generation = "gen4" | "gen5" | "gen6"`.

Fan control requires `thinkpad_acpi fan_control=1` (the module sets this via `boot.extraModprobeConfig`).

## When to use

- Adding thinkfan to a new ThinkPad host
- Changing fan aggressiveness (the shared `levels` curve)
- Fixing fan oscillation / hunting
- Sensor paths change after a kernel/BIOS update (stable-path sensors stop matching)
- Adding support for a new generation (e.g. gen7)

## Quick Reference

| File | Role |
|---|---|
| `nixos/hardware/thinkfan.nix` | Custom option + generation-aware sensors + shared fan curve |
| `hosts/<host>/default.nix` | Per-host enable + `generation = "gen?"` |
| `/proc/acpi/ibm/fan` | Runtime fan state (read to verify) |
| `/sys/class/hwmon/*` | Sensor inputs (gen4 uses name-based, gen5/gen6 use path-based) |

## Enabling on a host

```nix
# hosts/<host>/default.nix
hardware.thinkpad.thinkfan = {
  enable = true;
  generation = "gen5";   # "gen4" | "gen5" | "gen6"
};
```

The assertion in `thinkfan.nix` fails if `generation` is null while `enable` is true.

## Sensor strategy by generation

| Gen | Strategy | Why |
|---|---|---|
| gen4 | Name-based (`name = "amdgpu"`, `"k10temp"`, `"thinkpad"`, `"nvme"`, `"acpitz"`) against `/sys/class/hwmon` | Stable hwmon ordering on that platform |
| gen5, gen6 | Path-based (PCI device paths under `/sys/devices/...`) | hwmon enumeration is non-deterministic across boots on newer kernels; path lookup is stable |

NVMe temp gets a `-5` correction (the controller reports consistently high).

## Shared fan curve

```nix
levels = [
  [0 0 50]         # off until 50°C
  [1 45 55]
  [2 50 60]
  [3 55 65]
  [4 58 70]
  [5 63 75]
  [7 68 80]
  ["level full-speed" 75 32767]
];
```

Tuning philosophy: **ramps early, wide hysteresis to prevent oscillation**. Each row is `[level low_temp high_temp]` — fan goes up when temp exceeds `high`, down when below `low`.

**If you're getting fan hunting/oscillation:** widen the gap between `low` and `high` on adjacent levels. Never let them touch.

**If fans stay too quiet and CPU throttles:** lower the `high_temp` of upper levels (e.g. drop level 4 `high` from 70 to 65).

## Adding a new generation

1. Add the enum value in `options.hardware.thinkpad.thinkfan.generation.type`.
2. Add a new `else if cfg.generation == "genN"` branch in the `sensors` expression.
3. Find the stable paths on the machine: `find /sys/devices -name 'hwmon*' -type d` and cross-reference sensor names via `cat /sys/class/hwmon/*/name`.
4. Keep the NVMe `correction = [(-5)]` unless proven otherwise.

## Verification after a rebuild

```fish
# Is thinkfan running?
systemctl status thinkfan

# Current fan level / speed reported to kernel
cat /proc/acpi/ibm/fan

# Watch it react to load
stress-ng --cpu 4 --timeout 30s
watch -n1 'cat /proc/acpi/ibm/fan; sensors | grep -E "Tctl|edge"'
```

If thinkfan fails to start, journalctl usually says *"no sensors found matching..."* — your path/name query doesn't match reality on this kernel. Re-query hwmon.

## Common mistakes

| Mistake | Symptom | Fix |
|---|---|---|
| Enabling without `generation` | Eval-time assertion failure | Set `generation = "genN"` |
| Using gen4 name-based sensors on gen5/6 | Works at first, breaks after kernel update | Switch to path-based for newer gens |
| Fan levels with touching temps | Oscillation between levels | Widen hysteresis gap |
| Forgetting `thinkpad_acpi fan_control=1` | Thinkfan can't drive fan | Already set by the module — don't override `extraModprobeConfig` without merging |
| Editing `services.thinkfan` directly | Conflicts with the wrapper | Edit `nixos/hardware/thinkfan.nix` instead |

## Related

- Rebuild workflow: see `nix-rebuild` skill
- Secure Boot / TPM on gen5/gen6: see `secure-boot-tpm` skill

# NasPi Unattended Build Guide

## Overview

When deploying to naspi requires kernel compilation, building on your laptop causes:
- **High CPU usage** (cross-compilation via qemu-aarch64)
- **Thermal stress** (86-88°C on laptop)
- **Fan noise** (maxed out fans)
- **30-60 minutes** of laptop being hot

**Solution:** Build directly on naspi (RPi4) natively.

## Trade-offs

| Build Location | Time | Laptop Heat | Pros | Cons |
|----------------|------|-------------|------|------|
| **Laptop (cross-compile)** | 30-60 min | 🔥 High | Fast | Thermal stress, fan noise |
| **Naspi (native)** | 1-3 hours | ❄️ None | Cool laptop | Slower, uses RPi resources |

## When to Use Unattended Build

Use unattended naspi build when:
- ✅ Kernel compilation required (not in cache)
- ✅ You're on battery/throttled
- ✅ Laptop running hot from other work
- ✅ Don't need immediate deployment
- ✅ Can wait 1-3 hours

Use laptop build when:
- ✅ Everything cached (fast deploy)
- ✅ Need immediate deployment
- ✅ Laptop plugged in and cool

## Quick Start

```bash
# Start unattended build on naspi
just naspi-build-remote

# Monitor progress (optional)
ssh naspi "tail -f /tmp/naspi-rebuild.log"

# Check if still running
ssh naspi "ps aux | grep nixos-rebuild"

# Check completion
ssh naspi "grep 'Exit code' /tmp/naspi-rebuild.log"
# Exit code: 0 = success

# Test result
ssh noams@192.168.3.6  # Local SSH should work
```

## How It Works

### Step 1: Copy Configuration
```bash
git add -A  # Stage all changes
git archive HEAD | ssh naspi "cd /tmp && rm -rf nix-config && mkdir nix-config && cd nix-config && tar xf -"
```

**Why git archive:**
- Only git-tracked files (respects .gitignore)
- Excludes .direnv, result*, .git/
- Clean transfer of actual config

### Step 2: Start Unattended Build
```bash
ssh naspi "nohup bash -c 'cd /tmp/nix-config && sudo nixos-rebuild switch --flake .#naspi > /tmp/naspi-rebuild.log 2>&1; echo \"Exit code: \$?\" >> /tmp/naspi-rebuild.log' > /dev/null 2>&1 &"
```

**Why nohup:**
- Detaches from SSH session
- Continues if SSH drops
- Redirects all output to log file

**Why background (&):**
- Returns immediately
- Build continues unattended
- Can close terminal

### Step 3: Build Process on Naspi

```
1. Download cached packages (5-15 min)
   └─ From: nixos-raspberrypi.cachix.org, cache.nixos.org

2. Compile kernel natively (1-2 hours)
   └─ RPi4 ARM cores compile for ARM (no emulation)
   └─ 4 cores, limited to 2 jobs (nix.settings.max-jobs = 2)

3. Build system configuration (5-10 min)
   └─ Assemble all packages into system closure

4. Activate configuration (1 min)
   └─ Switch bootloader, update services
```

## Monitoring Progress

### Watch Live Build
```bash
ssh naspi "tail -f /tmp/naspi-rebuild.log"
```

**What you'll see:**
- Package downloads: `copying path '/nix/store/...' from 'https://...'`
- Kernel compilation: `building '/nix/store/...-linux-6.12.34.drv'`
- Service updates: `reloading unit X, restarting unit Y`

### Check Build Status
```bash
# Is rebuild still running?
ssh naspi "ps aux | grep 'nixos-rebuild\|nix-daemon' | grep -v grep"

# CPU usage on naspi
ssh naspi "uptime"
# Load average during kernel compile: 3.0-4.0 (4 cores busy)

# Disk I/O
ssh naspi "iostat -x 2 3"
```

### Check Current Phase
```bash
ssh naspi "tail -20 /tmp/naspi-rebuild.log"
```

**Phase indicators:**
- `copying path` = Downloading from cache
- `building '/nix/store/.*-linux-.*'` = Compiling kernel
- `these 5 derivations will be built` = Shows what's left
- `updating GRUB 2 menu` = Almost done
- `Exit code: 0` = Success!

## When Build Completes

### Verify Success
```bash
# Check exit code
ssh naspi "tail -5 /tmp/naspi-rebuild.log"
# Should show: Exit code: 0

# Check active generation
ssh naspi "readlink /run/current-system | xargs basename"
# Should show new generation number

# Verify kernel version
ssh naspi "uname -r"
# Should match expected kernel
```

### Test Local SSH
```bash
# The main fix - local network SSH should work now
ssh noams@192.168.3.6
# Should connect without issues

# If it works, SSH IPv4 fix was successful!
```

### Check Services
```bash
ssh naspi "systemctl status sshd.socket nginx sonarr radarr"
# All should be active (running)

# Check web UI
curl http://192.168.3.6/
# Should show: NasPi Services: /radarr /sonarr...
```

## Troubleshooting

### Build Failed
```bash
# Check error
ssh naspi "tail -100 /tmp/naspi-rebuild.log | grep -i error"

# Get full log
ssh naspi "cat /tmp/naspi-rebuild.log" > naspi-build-error.log
```

### Build Stuck
```bash
# Check what's building
ssh naspi "tail -50 /tmp/naspi-rebuild.log | grep building"

# Check if process is frozen
ssh naspi "ps aux | grep nixos-rebuild"
# If CPU% is 0.0 for >10 minutes, might be stuck

# Kill and retry
ssh naspi "sudo pkill -f nixos-rebuild"
just naspi-build-remote  # Try again
```

### Build Too Slow
```bash
# Check why (probably kernel)
ssh naspi "tail -100 /tmp/naspi-rebuild.log | grep 'building.*-linux-'"

# Options:
# 1. Accept the wait (safest)
# 2. Cancel and use laptop build (thermal stress)
# 3. Use binary cache from different architecture (risky)
```

## Performance Tips

### Faster Rebuilds

**Option 1: Pin nixos-raspberrypi** (if compatible)
```nix
# flake.nix - Pin to commit with cached kernel
nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/c3eb2dd...";
```
**Warning:** May cause authentication issues (see incident 2025-11-12)

**Option 2: Build kernel on laptop, copy to naspi**
```bash
# On laptop (cross-compile)
nix build .#nixosConfigurations.naspi.config.system.build.kernel

# Copy to naspi
nix copy --to ssh://naspi ./result

# Then build rest on naspi (no kernel recompile)
```

**Option 3: Use distributed building**
```bash
# Configure laptop as builder for naspi
# See: https://nixos.wiki/wiki/Distributed_build
```

## Best Practices

1. **Stage changes before copying** - `git add -A` ensures latest config is used
2. **Use Tailscale for reliability** - More stable than local network during long builds
3. **Check completion before testing** - grep for "Exit code" in log
4. **Save logs on failure** - `cat /tmp/naspi-rebuild.log > failure.log` for debugging
5. **Monitor first time** - Watch the build the first time to estimate duration

## Example Workflow

```bash
# Make configuration changes
vim hosts/naspi/system.nix

# Stage changes
git add hosts/naspi/system.nix

# Start unattended build
just naspi-build-remote

# (Optional) Monitor for a bit
ssh naspi "tail -f /tmp/naspi-rebuild.log"
# Ctrl+C to exit (build continues)

# Go do something else for 1-3 hours

# Come back and check
ssh naspi "tail -20 /tmp/naspi-rebuild.log"

# If successful (Exit code: 0)
ssh noams@192.168.3.6  # Test local SSH
curl http://192.168.3.6/  # Test services
```

## When NOT to Use

**Don't use unattended build if:**
- ❌ Everything is cached (will be fast on laptop)
- ❌ Need immediate deployment
- ❌ Testing rapid iterations (compile-test-fix loop)
- ❌ Naspi is under heavy load (torrents, media serving)

Use regular deployment instead:
```bash
just naspi-switch naspi.local  # Fast if cached
```

## Related Documentation

- [NasPi Incident 2025-11-12](./naspi-incident-2025-11-12.md) - Why pinning can break auth
- [Main README](../CLAUDE.md) - General deployment commands
- [NasPi README](../hosts/naspi/README.md) - System-specific configuration

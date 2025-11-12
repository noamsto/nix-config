# NasPi System Failure - November 12, 2025

## Timeline

**Nov 11 22:41** - Generation 56 deployed successfully
- Kernel: 6.12.34
- nixos-raspberrypi: 09926a8 (October 2025)
- Status: ✅ Working (SSH, sudo, nix-daemon all functional)

**Nov 12 00:33** - Generation 57 deployed (BROKEN)
- Kernel: 6.12.25 (downgrade!)
- nixos-raspberrypi: 31a4d34 (July 2025 - pinned)
- Status: ❌ Multiple critical failures

## Root Cause

Pinned nixos-raspberrypi to July 2025 commit (31a4d34a966522578133a616333c5e431d22032b) to enable paperless-ngx compatibility. This older version has fundamental system issues.

## Symptoms

### Critical Service Failures
```bash
# SSH socket - inactive, trying to bind IPv6 when disabled
○ sshd.socket - SSH Socket
     Active: inactive (dead)
     Listen: [::]:22 (Stream)

# Nix daemon - not responding
○ nix-daemon.socket - Nix Daemon Socket
     Active: inactive (dead)

# Sudo - setuid bit not set
sudo: /run/current-system/sw/bin/sudo must be owned by uid 0 and have the setuid bit set

# Authentication - PAM/NSS broken
Authentication service cannot retrieve authentication info
```

### Impact
- ❌ SSH on local network (192.168.3.6:22) - connection refused
- ✅ Tailscale SSH works (non-interactive commands only)
- ❌ Can't deploy new configurations (nix-daemon down)
- ❌ Can't run sudo commands
- ❌ Can't reboot remotely
- ❌ Can't rollback remotely (requires sudo)

## Failed Attempts to Recover

1. **Rollback to generation 56** - Failed (requires sudo)
2. **Restart nix-daemon** - Failed (sudo broken)
3. **Remote reboot** - Failed (access denied)
4. **Deploy SSH fix** - Failed (nix-daemon down)

## Configuration State

### What Was Changed
```nix
# flake.nix - Pinned to July 2025
nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/31a4d34a966522578133a616333c5e431d22032b";

# hosts/naspi/paperless.nix - Enabled with older module
services.paperless.enable = true;
# Uses default package from pinned nixos-raspberrypi

# hosts/naspi/system.nix - SSH IPv4 fix (not deployed)
services.openssh.listenAddresses = [
  { addr = "0.0.0.0"; port = 22; }
];
```

### What Was NOT Deployed
- Paperless configuration (deployment failed)
- SSH IPv4 fix (deployment failed)
- Generation 57 partially activated but is broken

## Recovery Options

### Option 1: Physical Access + Rollback (Recommended)
**Steps:**
1. Physical power cycle (unplug/replug)
2. Connect keyboard/monitor OR wait for boot
3. Login locally with password: `nixos`
4. Rollback: `sudo /nix/var/nix/profiles/system-56-link/bin/switch-to-configuration switch`
5. System returns to working state (generation 56)

**Pros:**
- Guaranteed to work
- Returns to known-good state immediately
- Simple and fast

**Cons:**
- Requires physical access

### Option 2: Disable Paperless + Use Recent nixos-raspberrypi
**After rollback to generation 56:**

```nix
# flake.nix - Remove pin (use latest)
nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi";

# hosts/naspi/default.nix - Remove paperless
# Comment out: ./paperless.nix

# Keep SSH IPv4 fix
services.openssh.listenAddresses = [
  { addr = "0.0.0.0"; port = 22; }
];
```

**Pros:**
- Gets latest nixos-raspberrypi fixes
- Avoids paperless compatibility issues
- SSH fix prevents future IPv6 binding issues

**Cons:**
- Lose paperless functionality
- Paperless will need different solution later

### Option 3: Try Intermediate nixos-raspberrypi Commit
**After rollback to generation 56:**

Try commits between July and October:
- September: `09c214a30e5a27e0fa92a9975b91c82ba05d1f17`
- August: `41c8447c259c5869437b1f1e98439a148542cef7`

Test each to find one where:
- ✅ Paperless module works
- ✅ System services stable
- ✅ SSH/sudo/nix-daemon functional

**Pros:**
- Might find working middle ground
- Keep paperless functionality

**Cons:**
- Time-consuming trial and error
- No guarantee of success
- Risk of similar failures

## Recommendation

**Immediate: Option 1** - Physical rollback to generation 56
**Next: Option 2** - Disable paperless, use latest nixos-raspberrypi

**Rationale:**
1. Paperless isn't critical infrastructure (nice-to-have)
2. Stable NAS functionality > one additional service
3. Latest nixos-raspberrypi = security fixes + stability
4. Can revisit paperless later when:
   - Module compatibility improves
   - Can test in isolated environment first
   - Have better rollback strategy

## Lessons Learned

1. **Test pinned versions in isolated environment** before deploying to production
2. **Kernel downgrades are red flags** (6.12.34 → 6.12.25)
3. **Critical services breaking = abort deployment** immediately
4. **Keep recent working generation tested** for fast rollback
5. **Document why pins exist** and their risks

## Prevention

**Future Changes:**
```nix
# Add to hosts/naspi/system.nix
# Explicit IPv4 binding (prevents IPv6 issues)
services.openssh.listenAddresses = [
  { addr = "0.0.0.0"; port = 22; }
];

# Test strategy for major dependency pins:
# 1. Build in isolation: nix build .#nixosConfigurations.naspi
# 2. Deploy to test generation (not switch)
# 3. Verify critical services before switching
# 4. Keep console access available during testing
```

## Related Files

- `/home/noams/nix-config/flake.nix` - nixos-raspberrypi pin
- `/home/noams/nix-config/hosts/naspi/paperless.nix` - Paperless config
- `/home/noams/nix-config/hosts/naspi/system.nix` - SSH configuration
- `/home/noams/nix-config/flake-modules/nixos-systems.nix` - System definitions

## Status

- **Current:** System in broken state (generation 57)
- **Last working:** Generation 56 (Nov 11 22:41)
- **Awaiting:** Physical access for rollback

## Resolution (Nov 12, 2025)

### Implemented Solution: Kernel Lock + Latest nixos-raspberrypi

**Decision:** Disable paperless, lock kernel version, use latest nixos-raspberrypi

**Changes Made:**

1. **Removed nixos-raspberrypi pin** (`flake.nix`)
   ```nix
   # Before: Pinned to July 2025 (broken)
   nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/31a4d34...";

   # After: Use latest
   nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi";
   ```

2. **Added kernel version lock** (`hosts/naspi/system.nix`)
   ```nix
   # Lock to 6.12.34 - known working version from generation 56
   boot.kernelPackages = nixos-raspberrypi.packages.${pkgs.system}.linuxPackages_rpi4_6_12_34;
   ```

3. **Kept SSH IPv4 fix** (`hosts/naspi/system.nix`)
   ```nix
   services.openssh.listenAddresses = [
     { addr = "0.0.0.0"; port = 22; }
   ];
   ```

4. **Disabled paperless** (`hosts/naspi/default.nix`)
   - Removed `./paperless.nix` import
   - Removed paperless reverse-proxy configuration
   - Decision: Move paperless to separate RPi4 for isolation

### Why This Works

**✅ Best of both worlds:**
- Latest nixos-raspberrypi = security fixes + module updates
- Locked kernel = stability, no surprise downgrades
- System services stay current
- Paperless isolation prevents future incidents

**⚠️ Kernel lock prevents:**
- Automatic kernel downgrades (6.12.34 → 6.12.25)
- sudo/nix-daemon/SSH breakage from incompatible versions
- Production NAS instability from experimental changes

**📋 Future kernel upgrades:**
When ready to upgrade kernel:
```bash
# Check available versions
nix eval github:nvmd/nixos-raspberrypi#packages.aarch64-linux.linuxPackages_rpi4_6_12_44.kernel.version

# Update lock in hosts/naspi/system.nix
boot.kernelPackages = nixos-raspberrypi.packages.${pkgs.system}.linuxPackages_rpi4_6_12_44;
```

### Post-Rollback Deployment Steps

1. Physical power cycle naspi
2. Rollback to generation 56: `sudo /nix/var/nix/profiles/system-56-link/bin/switch-to-configuration switch`
3. Verify SSH works: `ssh noams@192.168.3.6`
4. Deploy new config: `./scripts/naspi-deploy.sh naspi.local switch`
5. Verify kernel: `ssh naspi "uname -r"` (should show 6.12.34)
6. Verify services: `ssh naspi "systemctl status sshd.socket nix-daemon.socket"`

### Lessons Applied

1. ✅ **Never pin entire flake** - Lock specific components instead
2. ✅ **Kernel downgrades = red flag** - Lock kernel versions explicitly
3. ✅ **Service isolation** - Move non-critical services to separate hardware
4. ✅ **IPv4/IPv6 compatibility** - Explicitly configure when disabling IPv6
5. ✅ **Test pins before deploying** - Especially for production systems

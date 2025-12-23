# NixOS Configuration Refactoring Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce duplication and improve maintainability by extracting shared ThinkPad hardware logic and splitting monolithic modules.

**Architecture:** Extract common ThinkPad configurations into reusable modules with generation-specific overrides. Split the 199-line `pc.nix` into focused, single-responsibility modules. Move work-specific packages to a dedicated profile module.

**Tech Stack:** NixOS, Home Manager, Nix flakes

---

## Task 1: Create Shared ThinkPad Hardware Module

**Files:**
- Create: `nixos/hardware/thinkpad-common.nix`
- Create: `nixos/hardware/default.nix`

**Step 1: Create hardware directory and default.nix**

```bash
mkdir -p /home/noams/nix-config/nixos/hardware
```

**Step 2: Write the default.nix entry point**

Create `nixos/hardware/default.nix`:
```nix
{
  imports = [
    ./thinkpad-common.nix
  ];
}
```

**Step 3: Write thinkpad-common.nix with shared configuration**

Create `nixos/hardware/thinkpad-common.nix`:
```nix
{
  pkgs,
  config,
  lib,
  ...
}: let
  isThinkpad = builtins.match "thinkpad-.*" config.hostname != null;
in {
  config = lib.mkIf isThinkpad {
    # Common boot settings for all ThinkPads
    boot = {
      initrd.availableKernelModules = ["nvme" "xhci_pci" "thunderbolt" "usb_storage" "sd_mod"];
      initrd.kernelModules = ["dm-snapshot"];
      kernelModules = ["kvm-amd" "amdgpu"];
      extraModulePackages = [];
      kernelParams = [
        "systemd.gpt_auto=0" # Solve annoying dmesg warning
      ];
      kernel.sysctl."kernel.sysrq" = 502;
    };

    # Common filesystem options
    fileSystems."/boot".options = ["fmask=0022" "dmask=0022"];

    # Common networking
    networking.useDHCP = lib.mkDefault true;

    # Common hardware settings
    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
```

**Step 4: Verify syntax**

Run: `nix-instantiate --parse /home/noams/nix-config/nixos/hardware/thinkpad-common.nix`
Expected: No errors, outputs parsed expression

**Step 5: Commit**

```bash
git add nixos/hardware/
git commit -m "$(cat <<'EOF'
feat(hardware): add shared ThinkPad hardware module

Extract common boot, filesystem, and hardware settings shared
between thinkpad-p14s and thinkpad-p14s-g5 configurations.
EOF
)"
```

---

## Task 2: Create Thinkfan Configuration Module

**Files:**
- Create: `nixos/hardware/thinkfan.nix`
- Modify: `nixos/hardware/default.nix`

**Step 1: Write thinkfan.nix with generation-specific options**

Create `nixos/hardware/thinkfan.nix`:
```nix
{
  config,
  lib,
  ...
}: let
  cfg = config.hardware.thinkpad.thinkfan;
in {
  options.hardware.thinkpad.thinkfan = {
    enable = lib.mkEnableOption "ThinkPad fan control via thinkfan";

    generation = lib.mkOption {
      type = lib.types.enum ["gen4" "gen5"];
      description = "ThinkPad P14s generation for sensor paths";
    };
  };

  config = lib.mkIf cfg.enable {
    # Enable thinkpad_acpi fan control
    boot.extraModprobeConfig = lib.mkDefault ''
      options thinkpad_acpi fan_control=1
    '';

    services.thinkfan = {
      enable = true;
      sensors =
        if cfg.generation == "gen5"
        then [
          # Gen5: Path-based sensor lookup (stable across reboots)
          {
            type = "hwmon";
            query = "/sys/devices/pci0000:00/0000:00:08.1/0000:c4:00.0/hwmon";
            indices = [1];
          }
          {
            type = "hwmon";
            query = "/sys/devices/pci0000:00/0000:00:18.3/hwmon";
            indices = [1];
          }
          {
            type = "hwmon";
            query = "/sys/devices/platform/thinkpad_hwmon/hwmon";
            indices = [1 3 6 7];
          }
          {
            type = "hwmon";
            query = "/sys/devices/pci0000:00/0000:00:02.4/0000:03:00.0/nvme/nvme0";
            indices = [1];
            correction = [(-5)];
          }
          {
            type = "hwmon";
            query = "/sys/devices/virtual/thermal/thermal_zone0";
            indices = [1];
          }
        ]
        else [
          # Gen4: Name-based sensor lookup
          {
            name = "amdgpu";
            type = "hwmon";
            indices = [1];
            query = "/sys/class/hwmon";
          }
          {
            name = "k10temp";
            type = "hwmon";
            indices = [1];
            query = "/sys/class/hwmon";
          }
          {
            name = "thinkpad";
            type = "hwmon";
            indices = [1 3 6 7];
            query = "/sys/class/hwmon";
            max_errors = 10;
          }
          {
            name = "nvme";
            type = "hwmon";
            indices = [1 2 3];
            correction = [(-5) 0 0];
            query = "/sys/class/hwmon";
          }
          {
            name = "acpitz";
            type = "hwmon";
            indices = [1];
            query = "/sys/class/hwmon";
          }
        ];
      fans = [
        {
          type = "tpacpi";
          query = "/proc/acpi/ibm/fan";
        }
      ];
      # Aggressive fan curve (starts at 55-60°C, full-speed at 75-79°C)
      levels =
        if cfg.generation == "gen5"
        then [
          [0 0 60]
          [1 58 63]
          [2 61 66]
          [3 64 69]
          [4 67 72]
          [5 70 75]
          [6 73 78]
          [7 76 81]
          ["level full-speed" 79 32767]
        ]
        else [
          [0 0 55]
          [1 53 58]
          [2 56 61]
          [3 59 64]
          [4 62 67]
          [5 65 70]
          [6 69 74]
          [7 72 77]
          ["level full-speed" 75 32767]
        ];
    };
  };
}
```

**Step 2: Update default.nix to import thinkfan**

Edit `nixos/hardware/default.nix`:
```nix
{
  imports = [
    ./thinkpad-common.nix
    ./thinkfan.nix
  ];
}
```

**Step 3: Verify syntax**

Run: `nix-instantiate --parse /home/noams/nix-config/nixos/hardware/thinkfan.nix`
Expected: No errors

**Step 4: Commit**

```bash
git add nixos/hardware/thinkfan.nix nixos/hardware/default.nix
git commit -m "$(cat <<'EOF'
feat(hardware): add thinkfan module with generation options

Configurable thinkfan service with gen4/gen5 sensor paths and
fan curves. Uses path-based lookup for gen5, name-based for gen4.
EOF
)"
```

---

## Task 3: Split pc.nix - Create Laptop Suspend Handling Module

**Files:**
- Create: `nixos/laptop/suspend-handling.nix`
- Create: `nixos/laptop/default.nix`

**Step 1: Create laptop directory**

```bash
mkdir -p /home/noams/nix-config/nixos/laptop
```

**Step 2: Write suspend-handling.nix**

Create `nixos/laptop/suspend-handling.nix`:
```nix
{
  pkgs,
  config,
  lib,
  ...
}: let
  isLaptop = config.machine.type == "laptop";
in {
  config = lib.mkIf isLaptop {
    # Suppress spurious wakes from AC plug/unplug events
    # With acpi.ec_no_wakeup removed (to allow dock wake), AC events can wake the laptop
    # This service detects if wake was from docking (external monitors) or just AC
    # If no dock detected and lid is closed, immediately re-suspend
    systemd.services.suppress-ac-wake = {
      description = "Re-suspend if woken by AC plug event (not dock)";
      after = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "suppress-ac-wake" ''
          # Wait for hardware to stabilize after wake
          sleep 3

          # Check if any external DisplayPort monitors are connected (indicates dock)
          for status_file in /sys/class/drm/card*-DP-*/status /sys/class/drm/card*-HDMI-*/status; do
            if [ -f "$status_file" ] && [ "$(cat "$status_file" 2>/dev/null)" = "connected" ]; then
              # External monitor connected - dock is attached, stay awake
              ${pkgs.systemd}/bin/logger -t suppress-ac-wake "External monitor detected - staying awake"
              exit 0
            fi
          done

          # Check USB4/Thunderbolt for connected devices (dock attached but monitors not yet detected)
          if ${pkgs.coreutils}/bin/ls /sys/bus/thunderbolt/devices/*/device 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q .; then
            ${pkgs.systemd}/bin/logger -t suppress-ac-wake "Thunderbolt device detected - staying awake"
            exit 0
          fi

          # No dock detected - check if this is a spurious wake (lid closed = user not active)
          if ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/LID/state 2>/dev/null; then
            ${pkgs.systemd}/bin/logger -t suppress-ac-wake "Spurious wake (no dock, lid closed) - re-suspending in 2s"
            sleep 2
            # Double-check lid is still closed before suspending
            if ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/LID/state 2>/dev/null; then
              ${pkgs.systemd}/bin/systemctl suspend
            fi
          else
            ${pkgs.systemd}/bin/logger -t suppress-ac-wake "Lid is open - staying awake"
          fi
        '';
      };
      wantedBy = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
    };

    # Restart hyprdynamicmonitors after resume to fix phantom monitor detection
    # When laptop is undocked while asleep, Hyprland keeps phantom monitors
    # Restarting HDM forces fresh monitor detection
    systemd.services.hyprdynamicmonitors-resume = {
      description = "Clear phantom monitors and restart hyprdynamicmonitors after system resume";
      after = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
      serviceConfig = {
        Type = "oneshot";
        # Clear phantom monitors by checking DRM status and disabling disconnected ones in Hyprland
        ExecStart = pkgs.writeShellScript "hdm-resume" ''
          export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr/ 2>/dev/null | head -1)

          # Disable monitors that DRM reports as disconnected (these are phantoms in Hyprland)
          for status_file in /sys/class/drm/card*/status; do
            if [ -f "$status_file" ]; then
              connector=$(basename $(dirname "$status_file"))
              connector_name=''${connector#card?-}
              status=$(cat "$status_file")

              # If DRM says disconnected, disable in Hyprland to clear phantom
              if [ "$status" = "disconnected" ] && [ "$connector_name" != "Writeback-1" ]; then
                ${pkgs.hyprland}/bin/hyprctl keyword monitor "$connector_name,disable" 2>/dev/null || true
              fi
            fi
          done

          sleep 1

          # Now restart HDM to re-detect actual monitors
          ${pkgs.systemd}/bin/systemctl --user --machine=${config.username}@.host restart hyprdynamicmonitors.service
        '';
      };
      wantedBy = ["suspend.target" "hibernate.target" "hybrid-sleep.target"];
    };
  };
}
```

**Step 3: Write laptop/default.nix**

Create `nixos/laptop/default.nix`:
```nix
{
  imports = [
    ./suspend-handling.nix
  ];
}
```

**Step 4: Verify syntax**

Run: `nix-instantiate --parse /home/noams/nix-config/nixos/laptop/suspend-handling.nix`
Expected: No errors

**Step 5: Commit**

```bash
git add nixos/laptop/
git commit -m "$(cat <<'EOF'
feat(laptop): extract suspend handling to dedicated module

Moves suppress-ac-wake and hyprdynamicmonitors-resume services
from monolithic pc.nix to focused suspend-handling.nix module.
EOF
)"
```

---

## Task 4: Split pc.nix - Create PAM Lid Check Module

**Files:**
- Create: `nixos/laptop/pam-lid-check.nix`
- Modify: `nixos/laptop/default.nix`

**Step 1: Write pam-lid-check.nix**

Create `nixos/laptop/pam-lid-check.nix`:
```nix
{
  pkgs,
  config,
  lib,
  ...
}: let
  isLaptop = config.machine.type == "laptop";

  # Script to check lid state for PAM - exits 0 if open, 1 if closed
  # Uses full paths since PAM context has minimal environment
  lidCheckScript = pkgs.writeShellScript "pam-lid-check" ''
    if ${pkgs.gnugrep}/bin/grep -q closed /proc/acpi/button/lid/LID/state 2>/dev/null; then
      exit 1
    fi
    exit 0
  '';

  # PAM rule to skip fprintd when lid is closed
  # Control: success=ignore (continue to fprintd), all errors skip 1 rule (skip fprintd)
  # pam_exec returns various error codes on script failure, so we handle them all
  fprintdLidRule = {
    enable = true;
    control = "[success=ignore default=1 perm_denied=1 auth_err=1]";
    modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
    args = ["quiet" "seteuid" (toString lidCheckScript)];
    order = 11300; # Before fprintd (11400)
  };
in {
  config = lib.mkIf isLaptop {
    # PAM rule to skip fprintd when lid is closed (clamshell mode)
    # Applied to common auth services where fingerprint timeout is annoying
    security.pam.services = lib.genAttrs
      ["sudo" "su" "polkit-1" "login" "hyprlock" "swaylock"]
      (_: {rules.auth.fprintd-lid-check = fprintdLidRule;});
  };
}
```

**Step 2: Update laptop/default.nix**

Edit `nixos/laptop/default.nix`:
```nix
{
  imports = [
    ./suspend-handling.nix
    ./pam-lid-check.nix
  ];
}
```

**Step 3: Verify syntax**

Run: `nix-instantiate --parse /home/noams/nix-config/nixos/laptop/pam-lid-check.nix`
Expected: No errors

**Step 4: Commit**

```bash
git add nixos/laptop/pam-lid-check.nix nixos/laptop/default.nix
git commit -m "$(cat <<'EOF'
feat(laptop): extract PAM lid check to dedicated module

Moves fprintd lid-closed bypass logic from pc.nix to focused module.
Skips fingerprint auth when lid is closed (clamshell mode).
EOF
)"
```

---

## Task 5: Refactor pc.nix to Use New Modules

**Files:**
- Modify: `nixos/core/pc.nix`
- Modify: `nixos/default.nix`

**Step 1: Update nixos/default.nix to import new modules**

Read current `nixos/default.nix` first, then add imports for `./laptop` and `./hardware`.

**Step 2: Simplify pc.nix**

Reduce `nixos/core/pc.nix` to only contain:
- Audio (pipewire)
- Bluetooth
- Printing (CUPS)
- profile-sync-daemon
- fprintd service enable
- power-profiles-daemon
- coolercontrol
- OBS virtual camera
- Logitech wireless

Remove:
- PAM lid check (now in `nixos/laptop/pam-lid-check.nix`)
- suppress-ac-wake service (now in `nixos/laptop/suspend-handling.nix`)
- hyprdynamicmonitors-resume service (now in `nixos/laptop/suspend-handling.nix`)

**Step 3: Verify flake builds**

Run: `nix flake check --no-build`
Expected: No errors

**Step 4: Test rebuild**

Run: `nh home switch .`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add nixos/core/pc.nix nixos/default.nix
git commit -m "$(cat <<'EOF'
refactor(pc): simplify by delegating to laptop and hardware modules

pc.nix now focuses on audio, bluetooth, printing, and peripherals.
Laptop-specific services moved to nixos/laptop/*.
Hardware configs moved to nixos/hardware/*.
EOF
)"
```

---

## Task 6: Update Host Configs to Use New Hardware Module

**Files:**
- Modify: `hosts/thinkpad-p14s/default.nix`
- Modify: `hosts/thinkpad-p14s-g5/default.nix`

**Step 1: Update thinkpad-p14s/default.nix**

Add thinkfan configuration (disabled, matching current behavior):
```nix
# After imports, add:
hardware.thinkpad.thinkfan = {
  enable = false;  # Currently disabled for gen4
  generation = "gen4";
};
```

**Step 2: Update thinkpad-p14s-g5/default.nix**

Add thinkfan configuration (enabled, matching current behavior):
```nix
# After imports, add:
hardware.thinkpad.thinkfan = {
  enable = true;
  generation = "gen5";
};
```

**Step 3: Verify flake check**

Run: `nix flake check --no-build`
Expected: No errors

**Step 4: Commit**

```bash
git add hosts/thinkpad-p14s/default.nix hosts/thinkpad-p14s-g5/default.nix
git commit -m "$(cat <<'EOF'
feat(hosts): use new thinkfan module options

Configure thinkfan via hardware.thinkpad.thinkfan options
instead of inline configuration in hardware-configuration.nix.
EOF
)"
```

---

## Task 7: Clean Up hardware-configuration.nix Files

**Files:**
- Modify: `hosts/thinkpad-p14s/hardware-configuration.nix`
- Modify: `hosts/thinkpad-p14s-g5/hardware-configuration.nix`

**Step 1: Remove thinkfan config from thinkpad-p14s/hardware-configuration.nix**

Remove lines 26-85 (services.thinkfan block).

**Step 2: Remove thinkfan config from thinkpad-p14s-g5/hardware-configuration.nix**

Remove lines 48-107 (services.thinkfan block).

**Step 3: Remove duplicated boot settings covered by thinkpad-common.nix**

From both files, remove:
- `boot.initrd.availableKernelModules` (now in thinkpad-common.nix)
- `boot.initrd.kernelModules` (now in thinkpad-common.nix)
- `boot.kernelModules` (now in thinkpad-common.nix)
- `boot.extraModulePackages` (now in thinkpad-common.nix)
- `nixpkgs.hostPlatform` (now in thinkpad-common.nix)
- `hardware.cpu.amd.updateMicrocode` (now in thinkpad-common.nix)
- `networking.useDHCP` (now in thinkpad-common.nix)

Keep host-specific items:
- LUKS device UUIDs
- Filesystem UUIDs
- kernelParams (especially gen5's amdgpu.dcdebugmask)
- kernelPackages
- kernel.sysctl
- GPU hardware.graphics (gen5 only)

**Step 4: Verify build**

Run: `nh os build .`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add hosts/thinkpad-p14s/hardware-configuration.nix hosts/thinkpad-p14s-g5/hardware-configuration.nix
git commit -m "$(cat <<'EOF'
refactor(hosts): remove duplicated settings from hardware-configuration

Common ThinkPad settings now provided by nixos/hardware/thinkpad-common.nix.
Thinkfan configuration now via hardware.thinkpad.thinkfan options.
EOF
)"
```

---

## Task 8: Create Work Profile Module

**Files:**
- Create: `home/work/default.nix`
- Modify: `home/noams.nix`
- Modify: `home/packages.nix`

**Step 1: Create work directory**

```bash
mkdir -p /home/noams/nix-config/home/work
```

**Step 2: Write home/work/default.nix**

Create `home/work/default.nix`:
```nix
{
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    slack

    stable.awscli2
    stable.aws-sam-cli
    ssm-session-manager-plugin

    crush
    stable.postman
    ngrok
    dbeaver-bin
  ];
}
```

**Step 3: Update home/noams.nix to import work module**

Add to imports section (it should already have the kubernetes conditional):
```nix
++ lib.optionals (osConfig.profile == "work") [./work]
```

**Step 4: Remove work-packages from home/packages.nix**

Remove the `work-packages` let binding and the `++ lib.optionals (osConfig.profile == "work") work-packages` line.

**Step 5: Verify build**

Run: `nh home switch .`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add home/work/ home/noams.nix home/packages.nix
git commit -m "$(cat <<'EOF'
refactor(home): extract work packages to dedicated profile module

Work-specific packages (slack, aws, postman, etc.) now in home/work/.
Cleaner separation matches the profile-based architecture.
EOF
)"
```

---

## Task 9: Final Verification and Cleanup

**Files:**
- All modified files

**Step 1: Run full flake check**

Run: `nix flake check`
Expected: All checks pass

**Step 2: Test full NixOS rebuild**

Run: `nh os switch .`
Expected: Build and switch succeeds

**Step 3: Verify services are running correctly**

Run:
```bash
systemctl status suppress-ac-wake
systemctl status thinkfan
```
Expected: Services configured correctly (may not be active if conditions not met)

**Step 4: Clean up any leftover commented code**

Review pc.nix for any remaining dead code (like the commented ath11k services).

**Step 5: Final commit if any cleanup needed**

```bash
git add -A
git commit -m "chore: final cleanup after refactoring"
```

---

## Summary

```toon
tasks[9]{id,scope,impact}:
 1,Create thinkpad-common.nix,high
 2,Create thinkfan module,high
 3,Extract suspend handling,medium
 4,Extract PAM lid check,medium
 5,Refactor pc.nix,medium
 6,Update host configs,medium
 7,Clean hardware-config,high
 8,Create work profile,low
 9,Final verification,required
```

**Total estimated time:** 45-60 minutes for careful execution

**Risk mitigation:** Each task has its own commit, allowing easy rollback if something breaks.

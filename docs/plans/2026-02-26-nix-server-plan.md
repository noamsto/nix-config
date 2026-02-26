# nix-server Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create `factify-inc/nix-server` — a minimal NixOS flake for a Dell XPS 13 9340 headless dev server with LUKS+TPM, btrfs, and Tailscale SSH.

**Architecture:** Single-host NixOS flake with 4 files: `flake.nix` (inputs + system definition), `disko.nix` (LUKS + btrfs partitioning), `configuration.nix` (all system config), `hardware-configuration.nix` (placeholder). No Home Manager, no multi-host abstractions.

**Tech Stack:** NixOS (unstable), disko, lanzaboote, nixos-hardware, Tailscale, btrfs, LUKS+TPM2

**Design doc:** `docs/plans/2026-02-26-nix-server-design.md` (in nix-config repo)

---

### Task 1: Create Linear ticket and GitHub repo

**Step 1: Create Linear ticket**

Create a ticket on factify-inc Linear:
- Title: "Set up nix-server NixOS config for office Dell XPS 13"
- Description: Link to design doc, summarize scope

**Step 2: Create GitHub repo**

```bash
gh repo create factify-inc/nix-server --private --description "NixOS configuration for office Dell XPS 13 9340 dev server"
```

**Step 3: Clone and initialize**

```bash
cd /tmp
git clone git@github.com:factify-inc/nix-server.git
cd nix-server
```

**Step 4: Commit**

```bash
git commit --allow-empty -m "chore: initialize nix-server repo"
```

---

### Task 2: Create `.gitignore`

**Files:**
- Create: `.gitignore`

**Step 1: Write .gitignore**

```gitignore
result
result-*
.direnv
```

**Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: add gitignore"
```

---

### Task 3: Create `flake.nix`

**Files:**
- Create: `flake.nix`

**Step 1: Write flake.nix**

```nix
{
  description = "NixOS configuration for office Dell XPS 13 9340 dev server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
  };

  outputs = {
    nixpkgs,
    disko,
    lanzaboote,
    nixos-hardware,
    ...
  }: {
    nixosConfigurations.xps-server = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        disko.nixosModules.disko
        lanzaboote.nixosModules.lanzaboote
        nixos-hardware.nixosModules.common-cpu-intel
        nixos-hardware.nixosModules.common-pc-laptop
        nixos-hardware.nixosModules.common-pc-laptop-ssd
        ./disko.nix
        ./hardware-configuration.nix
        ./configuration.nix
      ];
    };
  };
}
```

**Step 2: Commit**

```bash
git add flake.nix
git commit -m "feat: add flake.nix with nixpkgs, disko, lanzaboote, nixos-hardware inputs"
```

---

### Task 4: Create `disko.nix`

**Files:**
- Create: `disko.nix`

Reference: naspi's `disko.nix` for pattern, but simplified for single-disk btrfs instead of ZFS RAID1.

**Step 1: Write disko.nix**

```nix
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/nvme0n1";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            priority = 1;
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["umask=0077"];
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              settings.allowDiscards = true;
              content = {
                type = "btrfs";
                extraArgs = ["-f"];
                subvolumes = {
                  "@" = {
                    mountpoint = "/";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "@home" = {
                    mountpoint = "/home";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "@nix" = {
                    mountpoint = "/nix";
                    mountOptions = ["compress=zstd" "noatime"];
                  };
                  "@swap" = {
                    mountpoint = "/.swap";
                    swap.swapfile.size = "8G";
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
```

**Step 2: Commit**

```bash
git add disko.nix
git commit -m "feat: add disko.nix with LUKS + btrfs + zstd compression"
```

---

### Task 5: Create `hardware-configuration.nix` placeholder

**Files:**
- Create: `hardware-configuration.nix`

This is a placeholder that will be replaced by `nixos-generate-config --show-hardware-config` on the actual machine. It provides enough to pass `nix flake check`.

**Step 1: Write hardware-configuration.nix**

```nix
# This file will be replaced by nixos-generate-config on the target machine.
# It provides a minimal placeholder for flake evaluation.
{
  lib,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = ["xhci_pci" "thunderbolt" "nvme" "usb_storage" "sd_mod"];
  boot.kernelModules = ["kvm-intel"];

  # The actual hardware-configuration.nix will be generated on the target.
  # Run: nixos-generate-config --show-hardware-config > hardware-configuration.nix
}
```

**Step 2: Commit**

```bash
git add hardware-configuration.nix
git commit -m "feat: add hardware-configuration.nix placeholder for XPS 13 9340"
```

---

### Task 6: Create `configuration.nix`

**Files:**
- Create: `configuration.nix`

This is the main config file. Reference patterns from naspi's `system.nix` and `tailscale.nix`, plus thinkpad-p14s-g5's Lanzaboote setup.

**Step 1: Write configuration.nix**

```nix
{
  pkgs,
  lib,
  ...
}: {
  # ── Boot ──────────────────────────────────────────────────────────
  boot = {
    initrd = {
      systemd.enable = true; # Required for TPM unlock
      luks.devices.cryptroot.crypttabExtraOpts = ["tpm2-device=auto"];
    };
    loader.systemd-boot.enable = lib.mkForce false; # Lanzaboote replaces systemd-boot
    lanzaboote = {
      enable = true;
      pkiBundle = "/etc/secureboot";
      autoGenerateKeys.enable = true;
      autoEnrollKeys.enable = true;
    };
  };

  # ── Nix ───────────────────────────────────────────────────────────
  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    auto-optimise-store = true;
    trusted-users = ["root" "platypus"];
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # ── Networking ────────────────────────────────────────────────────
  networking = {
    hostName = "xps-server";
    useNetworkd = true;
    useDHCP = false;
    firewall = {
      enable = true;
      trustedInterfaces = ["tailscale0"];
      allowedTCPPorts = [22];
      allowedUDPPorts = [41641]; # Tailscale
    };
  };

  systemd.network = {
    enable = true;
    networks."10-ethernet" = {
      matchConfig.Name = "en*";
      networkConfig.DHCP = "yes";
    };
    wait-online = {
      enable = true;
      anyInterface = true;
      timeout = 30;
    };
  };

  # ── Tailscale ─────────────────────────────────────────────────────
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "client";
    extraUpFlags = ["--accept-routes" "--ssh"];
  };

  # ── SSH ───────────────────────────────────────────────────────────
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  # ── User ──────────────────────────────────────────────────────────
  users.users.platypus = {
    isNormalUser = true;
    extraGroups = ["wheel" "networkmanager"];
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKXagBGbjJ7dHNZWKvkCqd3FNshl4conuFDO03OXnNvC noamstolero@gmail.com"
    ];
    initialPassword = "changeme"; # Change on first login, or enroll with passwd
  };

  security.sudo.wheelNeedsPassword = false;

  # ── Programs ──────────────────────────────────────────────────────
  programs.fish.enable = true;

  # ── Power management (server mode) ───────────────────────────────
  services.logind = {
    lidSwitch = "ignore";
    lidSwitchDocked = "ignore";
    lidSwitchExternalPower = "ignore";
  };

  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # ── SSD maintenance ──────────────────────────────────────────────
  services.fstrim.enable = true;

  # ── Locale ────────────────────────────────────────────────────────
  time.timeZone = "Asia/Jerusalem";
  i18n.defaultLocale = "en_US.UTF-8";

  # ── Packages ──────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # Secure boot + TPM
    sbctl
    tpm2-tools

    # Dev tools
    git
    neovim
    tmux
    nodejs_22 # For claude-code

    # Build essentials
    gcc
    gnumake

    # Nix dev
    nil
    alejandra

    # CLI tools
    ripgrep
    fd
    jq
    htop
    curl
    wget
    fish
    bat
    eza
  ];

  # ── System ────────────────────────────────────────────────────────
  system.stateVersion = "25.05";
}
```

**Step 2: Commit**

```bash
git add configuration.nix
git commit -m "feat: add configuration.nix with full server config"
```

---

### Task 7: Validate flake and generate lock file

**Step 1: Generate flake.lock**

```bash
nix flake update
```

**Step 2: Validate flake**

```bash
nix flake check
```

Expected: no errors.

**Step 3: Test build (dry-run)**

```bash
nix build .#nixosConfigurations.xps-server.config.system.build.toplevel --dry-run
```

Expected: shows derivations to be built, no errors.

**Step 4: Commit lock file**

```bash
git add flake.lock
git commit -m "chore: add flake.lock"
```

---

### Task 8: Add install instructions to README

**Files:**
- Create: `README.md`

**Step 1: Write README.md**

````markdown
# nix-server

NixOS configuration for the office Dell XPS 13 9340 dev server.

## What's configured

- **Boot:** Lanzaboote Secure Boot + LUKS with TPM2 auto-unlock
- **Filesystem:** btrfs with zstd compression (subvolumes: @, @home, @nix)
- **Networking:** systemd-networkd + Tailscale SSH
- **User:** `platypus` with fish shell
- **Dev tools:** tmux, git, neovim, nodejs (for claude-code), gcc, ripgrep, fd, jq

## Install

### Prerequisites

- NixOS USB installer (download from nixos.org)
- Wired network connection

### Steps

1. **Boot NixOS USB installer** on the XPS 13
   - Press F12 at Dell logo for boot menu
   - Select USB drive

2. **Connect to network** (wired should auto-connect)

3. **Clone this repo**
   ```bash
   nix-shell -p git
   git clone https://github.com/factify-inc/nix-server.git
   cd nix-server
   ```

4. **Partition and format with disko**
   ```bash
   sudo nix --experimental-features 'nix-command flakes' run github:nix-community/disko -- --mode disko ./disko.nix
   ```

5. **Generate hardware config** (replaces placeholder)
   ```bash
   nixos-generate-config --no-filesystems --show-hardware-config > hardware-configuration.nix
   ```

6. **Install NixOS**
   ```bash
   sudo nixos-install --flake .#xps-server
   ```

7. **Reboot** and remove USB drive

### Post-install

1. **Log in** as `platypus` (initial password: `changeme`)

2. **Change password**
   ```bash
   passwd
   ```

3. **Enroll TPM for LUKS auto-unlock**
   ```bash
   sudo systemd-cryptenroll --tpm2-device=auto /dev/nvme0n1p2
   ```

4. **Verify Secure Boot**
   ```bash
   sbctl status
   ```

5. **Authenticate Tailscale**
   ```bash
   sudo tailscale up --ssh --accept-routes
   ```

6. **Install claude-code**
   ```bash
   npm install -g @anthropic-ai/claude-code
   ```

7. **Reboot** to verify TPM unlock works
   ```bash
   sudo reboot
   ```

## Day-to-day

### Remote access
SSH via Tailscale: `ssh platypus@xps-server`

### Update system
```bash
cd /etc/nixos  # or wherever the repo is cloned
git pull
sudo nixos-rebuild switch --flake .#xps-server
```

### Update flake inputs
```bash
nix flake update
sudo nixos-rebuild switch --flake .#xps-server
```
````

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with install and usage instructions"
```

---

### Task 9: Push to GitHub

**Step 1: Push all commits**

```bash
git push -u origin main
```

---

### Summary of deliverables

```
factify-inc/nix-server/
├── .gitignore                  # result, .direnv
├── flake.nix                   # Inputs: nixpkgs, disko, lanzaboote, nixos-hardware
├── flake.lock                  # Generated lock file
├── disko.nix                   # LUKS + btrfs (3 subvols + swap)
├── hardware-configuration.nix  # Placeholder (replace on target)
├── configuration.nix           # Boot, networking, tailscale, user, packages
└── README.md                   # Install + usage instructions
```

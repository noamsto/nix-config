# RPi Configuration Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract all Raspberry Pi NixOS configurations from nix-config into a standalone `nix-rpi` repository with GitHub Actions ARM CI and FlakeHub caching.

**Architecture:** Standalone flake with flake-parts, owning complete nixosConfigurations for 3 RPi hosts. No Home Manager. Deployment scripts exposed as flake apps. GitHub Actions on native ARM runners builds and pushes to FlakeHub cache.

**Tech Stack:** NixOS, flake-parts, nixos-raspberrypi, disko, agenix, GitHub Actions (ubuntu-24.04-arm), FlakeHub

**Spec:** `docs/superpowers/specs/2026-03-26-rpi-extraction-design.md`

---

## File Structure

### New Repository: `nix-rpi`

```
nix-rpi/
├── flake.nix                          # Flake entry point with all inputs
├── flake-modules/
│   ├── nixos-systems.nix              # nixosConfigurations for naspi, argon-rpi4, rpi4-installer
│   ├── apps.nix                       # Flake apps wrapping deployment scripts
│   └── development.nix                # devShell, treefmt, pre-commit
├── lib/
│   ├── options.nix                    # Simplified server-only NixOS options
│   ├── caches.nix                     # Binary cache configuration (subset of nix-config's)
│   ├── rpi-hosts.nix                  # Deployment metadata (copied from nix-config)
│   └── rpi-common.sh                  # Shared bash deployment library (copied)
├── modules/
│   ├── common.nix                     # Base server config (locale, SSH, users, nix, fish, git)
│   ├── nix.nix                        # Nix/FlakeHub settings (from nixos/core/nix.nix)
│   ├── console.nix                    # Nice-looking console (from nixos/core/nice-looking-console.nix)
│   └── secrets.nix                    # Agenix secret declarations
├── hosts/
│   ├── naspi/                         # Copied from nix-config, imports adjusted
│   │   ├── default.nix
│   │   ├── hardware.nix
│   │   ├── system.nix
│   │   ├── disko.nix
│   │   ├── configtxt.nix
│   │   ├── media-services.nix
│   │   ├── reverse-proxy.nix
│   │   ├── monitoring.nix
│   │   ├── tailscale.nix
│   │   ├── network-resilience.nix
│   │   ├── go-bills.nix
│   │   ├── paperless.nix
│   │   ├── xscript.nix
│   │   ├── arr-setup.sh
│   │   ├── recyclarr.yml
│   │   └── pwm-2chan.dts
│   ├── argon-rpi4/                    # Copied from nix-config, imports adjusted
│   │   ├── default.nix
│   │   ├── hardware.nix
│   │   ├── system.nix
│   │   ├── disko.nix
│   │   └── btrfs-config.nix
│   └── rpi4-installer/
│       └── default.nix
├── scripts/
│   ├── rpi                            # Main CLI (copied, paths adjusted)
│   ├── operations/
│   │   ├── deploy.sh
│   │   ├── install.sh
│   │   └── build-image.sh
│   └── generate-zfs-key.sh
├── justfile
├── pre-commit-hooks.nix               # Pre-commit hook config
├── .github/
│   └── workflows/
│       └── build.yml
├── CLAUDE.md
└── .gitignore
```

### Modified in nix-config (cleanup phase)

- `flake.nix` — remove RPi-only inputs
- `flake-modules/nixos-systems.nix` — remove 3 RPi configs
- `flake-modules/home-manager.nix` — remove ARM helper + RPi HM configs
- `lib/host-configs.nix` — remove naspi, argon-rpi4 entries
- `lib/caches.nix` — remove nixos-raspberrypi.cachix.org
- `secrets/default.nix` — remove RPi-only secrets
- `justfile` — remove RPi recipes
- `CLAUDE.md` — remove RPi documentation

---

## Task 1: Create repository and flake.nix

**Files:**
- Create: `nix-rpi/flake.nix`
- Create: `nix-rpi/.gitignore`

- [ ] **Step 1: Create GitHub repo**

```bash
gh repo create noams/nix-rpi --private --clone
cd ~/Data/git/nix-rpi
```

- [ ] **Step 2: Create .gitignore**

```gitignore
result
result-*
.direnv
```

- [ ] **Step 3: Create flake.nix**

```nix
{
  description = "NixOS configurations for Raspberry Pi hosts";

  outputs = {flake-parts, ...} @ inputs:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = [
        ./flake-modules/development.nix
        ./flake-modules/nixos-systems.nix
        ./flake-modules/apps.nix
      ];

      flake = {
        rpiHosts = import ./lib/rpi-hosts.nix;
      };
    };

  nixConfig = {
    substituters = [
      "https://cache.nixos.org"
      "https://cache.flakehub.com"
      "https://nixos-raspberrypi.cachix.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
      "cache.flakehub.com-4:Asi8qIv291s0aYLyH6IOnr5Kf6+OF14WVjkE6t3xMio="
      "cache.flakehub.com-5:zB96CRlL7tiPtzA9/WKyPkp3A2vqxqgdgyTVNGShPDU="
      "cache.flakehub.com-6:W4EGFwAGgBj3he7c5fNh9NkOXw0PUVaxygCVKeuvaqU="
      "cache.flakehub.com-7:mvxJ2DZVHn/kRxlIaxYNMuDG1OvMckZu32um1TadOR8="
      "cache.flakehub.com-8:moO+OVS0mnTjBTcOUh2kYLQEd59ExzyoW1QgQ8XAARQ="
      "cache.flakehub.com-9:wChaSeTI6TeCuV/Sg2513ZIM9i0qJaYsF+lZCXg0J6o="
      "cache.flakehub.com-10:2GqeNlIp6AKp4EF2MVbE1kBOp9iBSyo0UPR9KoR0o1Y="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
    trusted-substituters = ["https://cache.flakehub.com"];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # RPi hardware support — pinned for kernel/auth stability
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/d0e2a7a36b08e2049e3024bc23ab391ca9de454c";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    mysecrets = {
      url = "git+ssh://git@github.com/noamsto/nix-secrets.git";
      flake = false;
    };

    go-bills.url = "https://flakehub.com/f/noamsto/go-bills/*";
  };
}
```

- [ ] **Step 4: Stage and commit**

```bash
git add flake.nix .gitignore
git commit -m "feat: initial flake.nix with RPi inputs"
```

---

## Task 2: Create lib/ — options, caches, deployment metadata

**Files:**
- Create: `nix-rpi/lib/options.nix`
- Create: `nix-rpi/lib/caches.nix`
- Copy: `nix-rpi/lib/rpi-hosts.nix` (from `nix-config/lib/rpi-hosts.nix` — no changes)
- Copy: `nix-rpi/lib/rpi-common.sh` (from `nix-config/lib/rpi-common.sh` — no changes)

- [ ] **Step 1: Create lib/options.nix**

Simplified from `nix-config/options.nix`. Removes desktop/laptop machinery. All hosts are headless servers.

```nix
{
  config,
  lib,
  ...
}: {
  options = {
    username = lib.mkOption {
      type = lib.types.str;
      default = "noams";
    };
    user-full-name = lib.mkOption {
      type = lib.types.str;
      default = "Noam Stolero";
      readOnly = true;
    };
    email = lib.mkOption {
      type = lib.types.str;
      default = "noamstolero@gmail.com";
    };
    hostname = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
    };
    profile = lib.mkOption {
      type = lib.types.enum ["personal" "work"];
      default = "personal";
    };
    flakePath = lib.mkOption {
      type = lib.types.str;
      default = "/home/${config.username}/nix-rpi";
      readOnly = true;
    };
    # Kept for compatibility — all hosts are servers with no desktop
    desktop = {
      mode = lib.mkOption {
        type = lib.types.enum ["none" "kde" "hyprland"];
        default = "none";
        readOnly = true;
      };
      isEnabled = lib.mkOption {
        type = lib.types.bool;
        default = false;
        readOnly = true;
      };
      isHyprland = lib.mkOption {
        type = lib.types.bool;
        default = false;
        readOnly = true;
      };
    };
    machine = {
      type = lib.mkOption {
        type = lib.types.enum ["server" "desktop" "laptop"];
        default = "server";
        readOnly = true;
      };
      isLaptop = lib.mkOption {
        type = lib.types.bool;
        default = false;
        readOnly = true;
      };
      isPC = lib.mkOption {
        type = lib.types.bool;
        default = false;
        readOnly = true;
      };
    };
  };
}
```

This includes all options from the original `options.nix` so any transitive module that references `config.desktop.mode` or `config.machine.isLaptop` won't fail. All values are hardcoded `readOnly` to server/none defaults.

- [ ] **Step 2: Create lib/caches.nix**

Server-focused subset — drops hyprland, vicinae, claude-code, yazi caches.

```nix
{
  substituters = [
    "https://cache.nixos.org"
    "https://cache.flakehub.com"
  ];

  extraSubstituters = [
    "https://nixos-raspberrypi.cachix.org"
    "https://nix-community.cachix.org"
  ];

  trustedPublicKeys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
    "cache.flakehub.com-4:Asi8qIv291s0aYLyH6IOnr5Kf6+OF14WVjkE6t3xMio="
    "cache.flakehub.com-5:zB96CRlL7tiPtzA9/WKyPkp3A2vqxqgdgyTVNGShPDU="
    "cache.flakehub.com-6:W4EGFwAGgBj3he7c5fNh9NkOXw0PUVaxygCVKeuvaqU="
    "cache.flakehub.com-7:mvxJ2DZVHn/kRxlIaxYNMuDG1OvMckZu32um1TadOR8="
    "cache.flakehub.com-8:moO+OVS0mnTjBTcOUh2kYLQEd59ExzyoW1QgQ8XAARQ="
    "cache.flakehub.com-9:wChaSeTI6TeCuV/Sg2513ZIM9i0qJaYsF+lZCXg0J6o="
    "cache.flakehub.com-10:2GqeNlIp6AKp4EF2MVbE1kBOp9iBSyo0UPR9KoR0o1Y="
  ];

  extraTrustedPublicKeys = [
    "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  ];

  trustedSubstituters = ["https://cache.flakehub.com"];
}
```

- [ ] **Step 3: Copy rpi-hosts.nix and rpi-common.sh**

```bash
cp ~/nix-config/lib/rpi-hosts.nix lib/rpi-hosts.nix
cp ~/nix-config/lib/rpi-common.sh lib/rpi-common.sh
```

No modifications needed — these are self-contained.

- [ ] **Step 4: Commit**

```bash
git add lib/
git commit -m "feat: add lib/ — options, caches, deployment metadata"
```

---

## Task 3: Create shared modules (common, nix, console, secrets)

**Files:**
- Create: `nix-rpi/modules/common.nix`
- Create: `nix-rpi/modules/nix.nix`
- Create: `nix-rpi/modules/console.nix`
- Create: `nix-rpi/modules/secrets.nix`

- [ ] **Step 1: Create modules/common.nix**

Consolidates locale, user account, SSH, fish, git, neovim. Replaces what naspi got from `nixos/core/locale.nix` + user setup + Home Manager.

```nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  sshPublicKeys = {
    noams = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKXagBGbjJ7dHNZWKvkCqd3FNshl4conuFDO03OXnNvC noamstolero@gmail.com";
  };
in {
  # Locale
  time.timeZone = "Asia/Jerusalem";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    LC_CTYPE = "en_US.UTF-8";
    LC_ADDRESS = "en_IL";
    LC_IDENTIFICATION = "en_IL";
    LC_MEASUREMENT = "en_IL";
    LC_MONETARY = "en_IL";
    LC_NAME = "en_IL";
    LC_NUMERIC = "en_IL";
    LC_PAPER = "en_IL";
    LC_TELEPHONE = "en_IL";
    LC_TIME = "en_IL";
  };

  # User account — use mkDefault so host system.nix can override groups
  users.users.${config.username} = {
    isNormalUser = true;
    extraGroups = lib.mkDefault ["wheel"];
    openssh.authorizedKeys.keys = [sshPublicKeys.noams];
  };

  # SSH server — use mkDefault so hosts can override (naspi needs PermitRootLogin for ZFS recovery)
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = lib.mkDefault false;
      PermitRootLogin = lib.mkDefault "no";
    };
  };

  # Fish shell
  programs.fish.enable = true;
  users.users.${config.username}.shell = pkgs.fish;

  # Git (system-level, replaces Home Manager git module)
  programs.git = {
    enable = true;
    config = {
      user.name = config.user-full-name;
      user.email = config.email;
      init.defaultBranch = "main";
    };
  };

  # Neovim (replaces home/nvim/minimal.nix)
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  # Essential packages
  environment.systemPackages = with pkgs; [
    curl
    wget
    htop
    btop
    fd
    ripgrep
    jq
    tree
    usbutils
    pciutils
    nh
    nix-output-monitor
  ];

  # Security
  security.sudo.wheelNeedsPassword = false;
}
```

- [ ] **Step 2: Create modules/nix.nix**

Adapted from `nix-config/nixos/core/nix.nix`. Same determinate module + FlakeHub cache push hook.

```nix
{
  pkgs,
  lib,
  inputs,
  ...
}: let
  caches = import ../lib/caches.nix;

  flakehubPushHook = pkgs.writeShellScript "flakehub-push-hook" ''
    set -f
    AUTH_FILE="''${HOME:-/root}/.config/flakehub/auth"
    if [ -f "$AUTH_FILE" ] || [ -L "$AUTH_FILE" ]; then
      ${pkgs.fh}/bin/fh cache push $OUT_PATHS >/dev/null 2>&1 || true
    fi
    exit 0
  '';
in {
  imports = [
    inputs.determinate.nixosModules.default
  ];

  nixpkgs.config.allowUnfree = true;

  nix = {
    settings = {
      keep-outputs = true;
      keep-derivations = true;
      auto-optimise-store = true;
      builders-use-substitutes = true;
      experimental-features = lib.mkDefault ["nix-command" "flakes"];
      accept-flake-config = true;
      allowed-users = ["@wheel"];
      trusted-users = ["@wheel"];
      download-buffer-size = 128 * 1024 * 1024;
      post-build-hook = flakehubPushHook;

      inherit (caches) substituters;
      trusted-public-keys = caches.trustedPublicKeys;
      trusted-substituters = caches.trustedSubstituters;
      extra-substituters = caches.extraSubstituters;
      extra-trusted-public-keys = caches.extraTrustedPublicKeys;
    };
  };
}
```

- [ ] **Step 3: Create modules/console.nix**

Copied from `nix-config/nixos/core/nice-looking-console.nix` — no changes.

```nix
{
  lib,
  pkgs,
  ...
}: {
  console = {
    earlySetup = true;
    font = lib.mkDefault "${pkgs.terminus_font}/share/consolefonts/ter-u16n.psf.gz";
    colors = lib.mkDefault [
      "000000" "CC0000" "4E9A06" "C4A000"
      "3465A4" "75507B" "06989A" "D3D7CF"
      "555753" "EF2929" "8AE234" "FCE94F"
      "739FCF" "AD7FA8" "34E2E2" "EEEEEC"
    ];
  };
}
```

- [ ] **Step 4: Create modules/secrets.nix**

Adapted from `nix-config/secrets/default.nix`. Hardcodes server identity path. Only declares naspi-specific secrets when hostname matches.

**Important:** Before building argon-rpi4 with secrets, verify that `mysecrets/secrets.nix` lists argon-rpi4's SSH host public key as a recipient for `noams_password.age`. If not, either enroll the key or skip secrets for argon-rpi4 (see argon-rpi4/default.nix below).

```nix
{
  pkgs,
  inputs,
  config,
  lib,
  ...
}: {
  imports = [
    inputs.agenix.nixosModules.default
  ];

  environment.systemPackages = [
    inputs.agenix.packages."${pkgs.stdenv.hostPlatform.system}".default
  ];

  age = {
    identityPaths = ["/etc/ssh/ssh_host_ed25519_key"];

    secrets = {
      noams_password.file = "${inputs.mysecrets}/noams_password.age";
      # naspi-only secrets
      paperless-naspi-password = lib.mkIf (config.hostname == "naspi") {
        file = "${inputs.mysecrets}/paperless-naspi-admin-password.age";
      };
      go-bills-gemini-key = lib.mkIf (config.hostname == "naspi") {
        file = "${inputs.mysecrets}/bills_gemini_key.age";
      };
    };
  };
}
```

- [ ] **Step 5: Commit**

```bash
git add modules/
git commit -m "feat: add shared modules (common, nix, console, secrets)"
```

---

## Task 4: Copy and adapt host configurations

**Files:**
- Copy+modify: `nix-rpi/hosts/naspi/` (all files from `nix-config/hosts/naspi/`, adjust imports)
- Copy+modify: `nix-rpi/hosts/argon-rpi4/` (all files, adjust imports)
- Copy+modify: `nix-rpi/hosts/rpi4-installer/default.nix` (adjust imports)

- [ ] **Step 1: Copy naspi host files**

```bash
cp -r ~/nix-config/hosts/naspi hosts/naspi
```

Remove `home.nix` (dropping HM) and `README.md` (optional, can keep for reference):

```bash
rm hosts/naspi/home.nix
```

- [ ] **Step 2: Rewrite hosts/naspi/default.nix**

Replace relative imports to `../../options.nix`, `../../overlays`, `../../nixos/core/*`, `../../secrets` with the new module paths. Remove `hostConfig` pattern — set options directly.

```nix
_: {
  imports = [
    ../../lib/options.nix
    ../../modules/common.nix
    ../../modules/nix.nix
    ../../modules/console.nix
    ../../modules/secrets.nix
    ./hardware.nix
    ./system.nix
    ./xscript.nix
    ./media-services.nix
    # ./paperless.nix  # Disabled - will run on separate RPi4
    ./monitoring.nix
    ./tailscale.nix
    ./network-resilience.nix
    ./reverse-proxy.nix
    ./go-bills.nix
  ];

  hostname = "naspi";
  email = "noamstolero@gmail.com";
  profile = "personal";

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
      hinfo = true;
      userServices = true;
      workstation = true;
    };
    extraServiceFiles = {
      nfs = ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h NFS</name>
          <service>
            <type>_nfs._tcp</type>
            <port>2049</port>
          </service>
        </service-group>
      '';
      smb = ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h SMB</name>
          <service>
            <type>_smb._tcp</type>
            <port>445</port>
          </service>
        </service-group>
      '';
    };
  };

  systemd.sockets.avahi-daemon = {
    unitConfig.DefaultDependencies = "no";
    socketConfig.After = "-.mount";
  };
}
```

- [ ] **Step 3: Clean up hosts/naspi/system.nix — remove config now in common.nix**

After copying, edit `hosts/naspi/system.nix` to remove sections that now live in `modules/common.nix`:
- Remove user account definition (`users.users.noams`) — common.nix handles base config. Keep only the `extraGroups` override if naspi needs groups beyond `["wheel"]` (e.g., `["wheel" "gpio"]`).
- Remove SSH server settings if they match common.nix defaults, OR override them explicitly (naspi needs `PermitRootLogin = "yes"` for ZFS recovery — keep that override).
- Remove any duplicate `programs.fish.enable`, `programs.git`, or locale settings.
- Keep all naspi-specific config (ZFS, kernel modules, networking, services, etc.).

Also add to `naspi/system.nix`:
```nix
# Override common.nix user with naspi-specific groups and password
users.users.noams = {
  extraGroups = ["wheel" "gpio"];
  hashedPasswordFile = config.age.secrets.noams_password.path;
};
```

- [ ] **Step 4: Verify no overlay-dependent packages in naspi/argon modules**

```bash
grep -r 'pkgs\.stable' hosts/naspi/ hosts/argon-rpi4/ || echo "No stable overlay references"
grep -r 'pkgs\.claude-code\|pkgs\.nix-search-tv\|pkgs\.amp' hosts/naspi/ hosts/argon-rpi4/ || echo "No overlay package references"
```

If any are found, either add those overlays or replace with direct package references.

- [ ] **Step 5: Copy argon-rpi4 host files**

```bash
cp -r ~/nix-config/hosts/argon-rpi4 hosts/argon-rpi4
```

- [ ] **Step 6: Clean up hosts/argon-rpi4/system.nix — remove config now in common.nix**

Same as naspi: remove user account definition, SSH server settings, etc. that duplicate `common.nix`. argon-rpi4 needs `extraGroups = ["wheel" "gpio" "i2c"]` — keep that as an override.

The original argon-rpi4 uses `initialPassword = "nixos"` instead of agenix. If argon-rpi4's host key is NOT in `mysecrets/secrets.nix`, override the password in `hosts/argon-rpi4/system.nix`:
```nix
users.users.noams = {
  extraGroups = ["wheel" "gpio" "i2c"];
  initialPassword = "nixos";  # No agenix on this host yet
};
```

- [ ] **Step 7: Rewrite hosts/argon-rpi4/default.nix**

```nix
_: {
  imports = [
    ../../lib/options.nix
    ../../modules/common.nix
    ../../modules/nix.nix
    ../../modules/console.nix
    ../../modules/secrets.nix
    ./hardware.nix
    ./system.nix
  ];

  hostname = "argon-rpi4";
  email = "noamstolero@gmail.com";
  profile = "personal";

  boot.tmp.useTmpfs = true;
}
```

- [ ] **Step 5: Create hosts/rpi4-installer/default.nix**

Adjust SSH key import path. The installer is minimal — no common module, no secrets.

```nix
_: {
  networking = {
    hostName = "rpi4-installer";
    wireless = {
      enable = true;
      iwd.enable = false;
      networks = {
        "Gal&Noam" = {
          pskRaw = "4b9d8676eba84131b06630f8ed035a09f386ffddb5c72104d9d9f3565858483c";
        };
      };
    };
  };

  users.users.nixos.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKXagBGbjJ7dHNZWKvkCqd3FNshl4conuFDO03OXnNvC noamstolero@gmail.com"
  ];
}
```

- [ ] **Step 6: Commit**

```bash
git add hosts/
git commit -m "feat: add host configurations (naspi, argon-rpi4, rpi4-installer)"
```

---

## Task 5: Create flake-modules (nixos-systems, apps, development)

**Files:**
- Create: `nix-rpi/flake-modules/nixos-systems.nix`
- Create: `nix-rpi/flake-modules/apps.nix`
- Create: `nix-rpi/flake-modules/development.nix`
- Create: `nix-rpi/pre-commit-hooks.nix`

- [ ] **Step 1: Create flake-modules/nixos-systems.nix**

Uses `nixos-raspberrypi.lib.nixosSystem` and `nixos-raspberrypi.lib.nixosInstaller` — the custom builders, NOT `nixpkgs.lib.nixosSystem`.

```nix
{inputs, ...}: let
  inherit (inputs) nixos-raspberrypi;
in {
  flake = {
    nixosConfigurations = {
      naspi = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = {
          inherit inputs nixos-raspberrypi;
          inherit (inputs) self;
        };
        system = "aarch64-linux";
        modules = [
          ../hosts/naspi
          inputs.disko.nixosModules.disko
          ../hosts/naspi/disko.nix
          inputs.go-bills.nixosModules.default
        ];
      };

      argon-rpi4 = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = {
          inherit inputs nixos-raspberrypi;
          inherit (inputs) self;
        };
        system = "aarch64-linux";
        modules = [
          ../hosts/argon-rpi4
          inputs.disko.nixosModules.disko
          ../hosts/argon-rpi4/disko.nix
        ];
      };

      rpi4-installer = nixos-raspberrypi.lib.nixosInstaller {
        specialArgs = inputs // {inherit nixos-raspberrypi;};
        modules = [
          nixos-raspberrypi.nixosModules.raspberry-pi-4.base
          nixos-raspberrypi.nixosModules.trusted-nix-caches
          ../hosts/rpi4-installer
        ];
      };
    };

    rpi4-installer = inputs.self.nixosConfigurations.rpi4-installer.config.system.build.sdImage;
  };
}
```

- [ ] **Step 2: Create flake-modules/apps.nix**

Wraps deployment scripts as flake apps. The scripts need the flake source path to run `nixos-rebuild --flake`. We pass the nix store path of the flake source as `FLAKE_DIR`.

```nix
{inputs, ...}: {
  perSystem = {pkgs, ...}: let
    flakeSrc = inputs.self;
    mkApp = name: host: action: {
      type = "app";
      program = toString (pkgs.writeShellScript name ''
        export FLAKE_DIR="${flakeSrc}"
        exec "${flakeSrc}/scripts/rpi" ${host} ${action} "$@"
      '');
    };
  in {
    apps = {
      deploy-naspi = mkApp "deploy-naspi" "naspi" "deploy";
      deploy-argon = mkApp "deploy-argon" "argon-rpi4" "deploy";
      install-naspi = mkApp "install-naspi" "naspi" "install";
      install-argon = mkApp "install-argon" "argon-rpi4" "install";
      build-installer = mkApp "build-installer" "rpi4-installer" "build";
    };
  };
}
```

**Important:** The deploy scripts currently use `$FLAKE_DIR` or auto-detect the repo root. When invoked as a flake app, `FLAKE_DIR` will be a nix store path (read-only). The scripts need to be patched to accept `FLAKE_DIR` as the flake reference for `nixos-rebuild --flake "$FLAKE_DIR#$FLAKE"`. This is addressed in Task 6, Step 2.

- [ ] **Step 3: Create pre-commit-hooks.nix**

```nix
{inputs, ...}: {
  imports = [
    inputs.pre-commit-hooks.flakeModule
  ];
}
```

- [ ] **Step 4: Create flake-modules/development.nix**

Simplified from nix-config's version — no home-manager, no fish aliases, just essentials.

```nix
{inputs, ...}: {
  imports = [
    inputs.treefmt-nix.flakeModule
    ../pre-commit-hooks.nix
  ];

  perSystem = {
    config,
    pkgs,
    ...
  }: {
    devShells.default = pkgs.mkShell {
      packages = [
        inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
        config.treefmt.build.wrapper
        pkgs.git
        pkgs.nh
        pkgs.nix-output-monitor
        pkgs.just
        pkgs.shellcheck
        pkgs.jq
      ];
      name = "nix-rpi";
      shellHook = ''
        ${config.pre-commit.installationScript}
        export EDITOR=nvim
      '';
    };

    treefmt = {
      projectRootFile = "flake.nix";
      programs = {
        alejandra.enable = true;
        shellcheck.enable = true;
        shfmt = {
          enable = true;
          indent_size = 2;
        };
      };
    };

    formatter = pkgs.alejandra;

    pre-commit.settings.hooks.treefmt.enable = true;
  };
}
```

- [ ] **Step 5: Commit**

```bash
git add flake-modules/ pre-commit-hooks.nix
git commit -m "feat: add flake-modules (nixos-systems, apps, development)"
```

---

## Task 6: Copy deployment scripts and create justfile

**Files:**
- Copy: `nix-rpi/scripts/` (from `nix-config/scripts/rpi/` + `scripts/generate-zfs-key.sh`)
- Create: `nix-rpi/justfile`

- [ ] **Step 1: Copy scripts**

```bash
cp -r ~/nix-config/scripts/rpi scripts/rpi
cp ~/nix-config/scripts/generate-zfs-key.sh scripts/generate-zfs-key.sh
```

Rename the entry point for cleaner paths:

```bash
cp scripts/rpi/rpi scripts/rpi
```

Wait — the structure should be:

```bash
mkdir -p scripts/operations
cp ~/nix-config/scripts/rpi/rpi scripts/rpi
cp ~/nix-config/scripts/rpi/operations/* scripts/operations/
cp ~/nix-config/scripts/generate-zfs-key.sh scripts/generate-zfs-key.sh
```

- [ ] **Step 2: Fix script paths for new directory layout**

The original `scripts/rpi/rpi` resolves `lib/rpi-common.sh` relative to itself (`$SCRIPT_DIR/../../lib/rpi-common.sh` from `scripts/rpi/`). In the new layout, `scripts/rpi` is a file at `scripts/rpi`, so `$SCRIPT_DIR` = `scripts/` and the path needs to be `$SCRIPT_DIR/../lib/rpi-common.sh`.

Fix in `scripts/rpi`:
```bash
# Old (from scripts/rpi/ directory):
# COMMON_LIB="$SCRIPT_DIR/../../lib/rpi-common.sh"
# New (from scripts/ directory):
COMMON_LIB="$SCRIPT_DIR/../lib/rpi-common.sh"
```

Fix operation dispatch paths:
```bash
# Old: $SCRIPT_DIR/operations/deploy.sh
# New: $SCRIPT_DIR/operations/deploy.sh  (same — operations/ is alongside rpi)
```

Fix `FLAKE_DIR` detection to support the environment variable from flake apps:
```bash
# At the top of scripts/rpi, add:
FLAKE_DIR="${FLAKE_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
```

Fix `operations/install.sh` reference to `generate-zfs-key.sh`:
```bash
# Old: $FLAKE_DIR/scripts/generate-zfs-key.sh
# New: $SCRIPT_DIR/generate-zfs-key.sh  (or $FLAKE_DIR/scripts/generate-zfs-key.sh)
```

Fix `lib/rpi-common.sh` `FLAKE_DIR` detection similarly.

Run `shellcheck` on all scripts after changes:
```bash
shellcheck scripts/rpi scripts/operations/*.sh scripts/generate-zfs-key.sh
```

- [ ] **Step 3: Create justfile**

```just
# nix-rpi — Raspberry Pi Configuration Management

default:
    @just --list

# =============================================================================
# Development & Validation
# =============================================================================

fmt:
    nix fmt

check:
    nix flake check

update:
    nix flake update

dev:
    nix develop

# =============================================================================
# Deployment
# =============================================================================

# Deploy configuration update to naspi
deploy-naspi STRATEGY="auto":
    @echo "Deploying configuration update to naspi..."
    ./scripts/rpi naspi deploy {{STRATEGY}}

# Quick naspi deploy (alias)
naspi:
    @just deploy-naspi

# Deploy configuration update to argon-rpi4
deploy-argon STRATEGY="auto":
    @echo "Deploying configuration update to argon-rpi4..."
    ./scripts/rpi argon-rpi4 deploy {{STRATEGY}}

# =============================================================================
# Installation (DESTRUCTIVE)
# =============================================================================

# Fresh installation of naspi
install-naspi:
    @echo "This will WIPE and REPARTITION naspi!"
    ./scripts/rpi naspi install

# Fresh installation of argon-rpi4
install-argon:
    @echo "This will WIPE and REPARTITION argon-rpi4!"
    ./scripts/rpi argon-rpi4 install

# =============================================================================
# Images
# =============================================================================

# Build Raspberry Pi installer image
build-installer:
    @echo "Building RPI4 installer SD card image..."
    ./scripts/rpi rpi4-installer build

# =============================================================================
# Utilities
# =============================================================================

# List all available configurations
list:
    ./scripts/rpi list

# SSH into a Raspberry Pi
ssh HOST USER="noams":
    ssh {{USER}}@{{HOST}}.local

# Reboot a Raspberry Pi
reboot HOST USER="noams":
    @echo "Rebooting {{HOST}}..."
    ssh {{USER}}@{{HOST}}.local sudo reboot || echo "Reboot initiated"

# Check Raspberry Pi status
status HOST USER="noams":
    @echo "Status of {{HOST}}:"
    ssh {{USER}}@{{HOST}}.local "echo 'Hostname:' \$(hostname) && echo 'Uptime:' \$(uptime -p) && echo 'Memory:' && free -h | head -2 && echo 'Disk:' && df -h | head -2"

# =============================================================================
# Help
# =============================================================================

# Show detailed help
help:
    @echo "Raspberry Pi Deployment Guide"
    @echo "=============================="
    @echo ""
    @echo "Workflow: SD Installer -> Install -> Deploy (config updates)"
    @echo ""
    @echo "Initial Installation:"
    @echo "1. just build-installer          # Build installer SD image"
    @echo "2. Flash to SD card"
    @echo "3. Boot Pi from SD card"
    @echo "4. just install-naspi            # Fresh install with ZFS RAID1"
    @echo "   just install-argon            # Fresh install with Btrfs on SSD"
    @echo "5. Remove SD card and reboot"
    @echo ""
    @echo "Configuration Updates:"
    @echo "just deploy-naspi                # Update naspi (auto build strategy)"
    @echo "just deploy-naspi local          # Update naspi (build locally)"
    @echo "just deploy-naspi remote         # Update naspi (build on target)"
    @echo "just deploy-argon                # Update argon-rpi4"
    @echo ""
    @echo "Management:"
    @echo "just list                        # List all configurations"
    @echo "just status naspi                # Check system status"
    @echo "just ssh naspi                   # SSH into system"
    @echo "just reboot naspi                # Reboot system"
```

- [ ] **Step 4: Make scripts executable**

```bash
chmod +x scripts/rpi scripts/operations/*.sh scripts/generate-zfs-key.sh
```

- [ ] **Step 5: Commit**

```bash
git add scripts/ justfile
git commit -m "feat: add deployment scripts and justfile"
```

---

## Task 7: Verify builds

**Files:** None (verification only)

- [ ] **Step 1: Stage all files for nix visibility**

```bash
git add -A
```

- [ ] **Step 2: Check flake evaluation**

```bash
nix flake check
```

Expected: No errors. If there are import path issues, fix them.

- [ ] **Step 3: Build naspi configuration**

```bash
nix build .#nixosConfigurations.naspi.config.system.build.toplevel
```

This is the critical test. If it evaluates successfully, the extraction is correct. It will take a while (downloads from caches).

- [ ] **Step 4: Build argon-rpi4 configuration**

```bash
nix build .#nixosConfigurations.argon-rpi4.config.system.build.toplevel
```

- [ ] **Step 5: Build rpi4-installer**

```bash
nix build .#rpi4-installer
```

- [ ] **Step 6: Fix any issues and commit**

```bash
git add -A
git commit -m "fix: resolve build issues from extraction"
```

---

## Task 8: Test deployment from new repo

**Files:** None (testing only)

- [ ] **Step 1: Deploy to naspi**

```bash
just deploy-naspi
```

Verify the Pi applies the configuration successfully. SSH in and check services are running.

- [ ] **Step 2: Verify services on naspi**

```bash
ssh noams@naspi.local "systemctl status sonarr radarr transmission"
```

- [ ] **Step 3: Deploy to argon-rpi4 (if accessible)**

```bash
just deploy-argon
```

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: deployment script adjustments"
```

---

## Task 9: Set up GitHub Actions CI

**Files:**
- Create: `nix-rpi/.github/workflows/build.yml`

- [ ] **Step 1: Create .github/workflows/build.yml**

**Prerequisites:** Before the first CI run:
1. Generate deploy key: `ssh-keygen -t ed25519 -C "nix-rpi-ci" -f /tmp/nix-rpi-deploy`
2. Add **public** key as deploy key to `noamsto/nix-secrets` repo (read-only)
3. Add **private** key as GitHub Actions secret `SECRETS_DEPLOY_KEY` in `nix-rpi`

```yaml
name: Build RPi Configurations

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    strategy:
      matrix:
        host: [naspi, argon-rpi4]
    runs-on: ubuntu-24.04-arm
    steps:
      - uses: actions/checkout@v4

      - name: Configure SSH for mysecrets
        env:
          DEPLOY_KEY: ${{ secrets.SECRETS_DEPLOY_KEY }}
        run: |
          mkdir -p ~/.ssh
          echo "$DEPLOY_KEY" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan github.com >> ~/.ssh/known_hosts

      - uses: DeterminateSystems/nix-installer-action@main

      - uses: DeterminateSystems/flakehub-cache-action@main
        with:
          visibility: private

      - name: Build ${{ matrix.host }}
        run: nix build .#nixosConfigurations.${{ matrix.host }}.config.system.build.toplevel

  build-installer:
    runs-on: ubuntu-24.04-arm
    steps:
      - uses: actions/checkout@v4

      - name: Configure SSH for mysecrets
        env:
          DEPLOY_KEY: ${{ secrets.SECRETS_DEPLOY_KEY }}
        run: |
          mkdir -p ~/.ssh
          echo "$DEPLOY_KEY" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519
          ssh-keyscan github.com >> ~/.ssh/known_hosts

      - uses: DeterminateSystems/nix-installer-action@main

      - uses: DeterminateSystems/flakehub-cache-action@main
        with:
          visibility: private

      - name: Build installer image
        run: nix build .#rpi4-installer
```

- [ ] **Step 2: Commit and push**

```bash
git add .github/
git commit -m "feat: add GitHub Actions CI with ARM builds and FlakeHub cache"
git push -u origin main
```

- [ ] **Step 3: Verify CI runs**

```bash
gh run list --limit 1
gh run watch
```

Wait for the build to complete. First run will be slow (populating cache). Subsequent runs should be fast.

- [ ] **Step 4: Verify FlakeHub cache**

After CI succeeds, deploy to a Pi and check that it pulls from FlakeHub cache:

```bash
just deploy-naspi
```

Watch the output — you should see cache hits from `cache.flakehub.com`.

---

## Task 10: Clean up nix-config

**Files:**
- Modify: `nix-config/flake.nix`
- Modify: `nix-config/flake-modules/nixos-systems.nix`
- Modify: `nix-config/flake-modules/home-manager.nix`
- Modify: `nix-config/lib/host-configs.nix`
- Modify: `nix-config/lib/caches.nix`
- Modify: `nix-config/secrets/default.nix`
- Modify: `nix-config/justfile`
- Remove: `nix-config/hosts/naspi/`
- Remove: `nix-config/hosts/argon-rpi4/`
- Remove: `nix-config/hosts/rpi4-installer/`
- Remove: `nix-config/scripts/rpi/`
- Remove: `nix-config/scripts/generate-zfs-key.sh`
- Remove: `nix-config/lib/rpi-hosts.nix`
- Remove: `nix-config/lib/rpi-common.sh`

- [ ] **Step 1: Remove RPi host directories**

```bash
cd ~/nix-config
gtrash put hosts/naspi hosts/argon-rpi4 hosts/rpi4-installer
```

- [ ] **Step 2: Remove RPi scripts and lib files**

```bash
gtrash put scripts/rpi scripts/generate-zfs-key.sh lib/rpi-hosts.nix lib/rpi-common.sh
```

- [ ] **Step 3: Remove RPi configs from flake-modules/nixos-systems.nix**

Remove the naspi, argon-rpi4, rpi4-installer blocks and the `rpi4-installer` output. Keep only ThinkPad configs.

Expected result (only ThinkPad configs remain):

```nix
{inputs, ...}: let
  inherit (inputs) nixpkgs;
in {
  flake = {
    nixosConfigurations = {
      thinkpad-p14s = nixpkgs.lib.nixosSystem {
        modules = [../hosts/thinkpad-p14s];
        specialArgs = {
          inherit inputs;
          inherit (inputs) self;
        };
      };

      thinkpad-p14s-g5 = nixpkgs.lib.nixosSystem {
        modules = [../hosts/thinkpad-p14s-g5];
        specialArgs = {
          inherit inputs;
          inherit (inputs) self;
        };
      };
    };
  };
}
```

- [ ] **Step 4: Remove ARM HM configs from flake-modules/home-manager.nix**

Remove `mkArmHomeConfig`, `"noams@naspi"`, and `naspi-raspbian` entries.

- [ ] **Step 5: Remove RPi entries from lib/host-configs.nix**

Remove `naspi` and `argon-rpi4` entries. Keep `sshPublicKeys`, `thinkpad-p14s`, `thinkpad-p14s-g5`.

- [ ] **Step 6: Clean up flake.nix inputs**

Remove `nixos-raspberrypi` input (line 129). Remove `go-bills` input (line 194). Check if `disko` is still used by ThinkPads — if not, remove it too. Remove `rpiHosts` from flake outputs (line 23).

- [ ] **Step 7: Remove RPi-only secrets from secrets/default.nix**

Remove `paperless-naspi-password` and `go-bills-gemini-key`. Keep `noams_password` (used by ThinkPads too).

- [ ] **Step 8: Remove nixos-raspberrypi cache from lib/caches.nix**

Remove `"https://nixos-raspberrypi.cachix.org"` from extraSubstituters and its key from extraTrustedPublicKeys. Also remove from `flake.nix` nixConfig.

- [ ] **Step 9: Remove RPi recipes from justfile**

Remove lines 64-229 (everything from "# Raspberry Pi Management" through "help-rpi" recipe). Update the `help` recipe to remove RPi references.

- [ ] **Step 10: Verify nix-config still builds**

```bash
nix flake check
nh os build .
```

- [ ] **Step 11: Commit cleanup**

```bash
git add -A
git commit -m "chore: remove RPi configs (extracted to nix-rpi repo)"
```

---

## Task 11: Update documentation

**Files:**
- Modify: `nix-config/CLAUDE.md` — remove RPi sections
- Create: `nix-rpi/CLAUDE.md` — add RPi-focused docs

- [ ] **Step 1: Create nix-rpi/CLAUDE.md**

Write a CLAUDE.md for the new repo covering:
- Overview (standalone RPi NixOS config repo)
- Available hosts and their purpose
- Development commands (just recipes)
- Deployment workflow
- CI/CD setup
- Directory structure
- How to add a new RPi host

- [ ] **Step 2: Remove RPi sections from nix-config/CLAUDE.md**

Remove:
- "Raspberry Pi Configurations" subsection
- "NasPi Boot Troubleshooting" subsection
- RPi entries from "Available Hosts"
- RPi commands from "System Rebuilds"
- RPi entries from "Standalone Home Manager"
- "Hybrid Home Manager Approach" RPi references
- RPi-related justfile recipe documentation
- RPi sections from directory structure

- [ ] **Step 3: Commit**

In nix-rpi:
```bash
git add CLAUDE.md
git commit -m "docs: add CLAUDE.md"
```

In nix-config:
```bash
git add CLAUDE.md
git commit -m "docs: remove RPi sections from CLAUDE.md (moved to nix-rpi)"
```

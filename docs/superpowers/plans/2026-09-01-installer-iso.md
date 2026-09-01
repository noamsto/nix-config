# Installer ISO Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A generic NixOS live ISO that auto-joins home wifi and exposes sshd with Noam's key, so bare-metal installs are driven remotely with `nixos-anywhere`.

**Architecture:** One new `nixosConfigurations.installer` built from nixpkgs' `installation-cd-minimal.nix`, layering on a declarative NetworkManager wifi profile (credential read at *eval* time from the private `mysecrets` input), a root authorized key, the repo's binary caches, and a console banner that prints the box's live IP.

**Tech Stack:** NixOS (flake-parts), `installation-cd-minimal.nix`, `networking.networkmanager.ensureProfiles`, agenix-adjacent `mysecrets` input, `nixos-anywhere`, `just`.

**Spec:** `docs/superpowers/specs/2026-09-01-installer-iso-design.md`

---

## Critical repo gotchas

Read these before starting; they cause confusing failures otherwise.

1. **`git add` before evaluating.** Flake evaluation only sees git-tracked files. A newly created `hosts/installer/default.nix` that has not been `git add`ed produces `path does not exist` / `file not found`, *even though the file is right there*. Every task below adds files before running `nix eval`.
2. **Pre-commit hooks reformat and fail the first commit.** `alejandra`, `deadnix`, `statix`, and `prettier` run on commit. The first `git commit` touching `.nix` or `.md` will fail with "files were modified by this hook". This is expected: `git add` the reformatted files and re-run the *same* commit. Do not change the commit message.
3. **Never print the wifi profile attrset in full.** It contains the PMK. Verification commands below use `--apply builtins.attrNames` and `grep -c` deliberately. Do not "helpfully" dump the whole value.
4. **Do not drop `nixpkgs.hostPlatform`.** `mkSystem` in `flake-modules/nixos-systems.nix`
   passes no `system` argument, and the installer — unlike g5/g6 — has no generated
   `hardware-configuration.nix` to supply one. Removing that line fails evaluation with
   "Neither nixpkgs.hostPlatform nor the legacy option nixpkgs.system has been set".
   Tasks 3 and 4 quote the full file; keep the line when rewriting it.
5. **`ensureProfiles` runs values through `envsubst`.** A literal `$` in a profile value would be substituted away. The 64-hex PMK contains no `$`, which is one reason the spec stores the derived key rather than a passphrase.

---

## Task 1: Create the wifi credential (MANUAL — Noam only)

This task cannot be done by an agent: it needs the decrypted wifi passphrase and
push access to the private `nix-secrets` repo. **Tasks 2+ cannot be verified
until this is done**, because `hosts/installer/default.nix` reads the file at
evaluation time.

**Files:**
- Create: `installer-wifi.json` in the private `nix-secrets` repo
- Modify: `flake.lock` (in this repo, `mysecrets` node)

- [ ] **Step 1: Recover the passphrase**

`nix-secrets` already contains `wifi-home.age`, which holds the home wifi
**passphrase only** (no SSID). It is currently referenced nowhere in
`nix-config`. Decrypt it:

```bash
cd /path/to/nix-secrets
agenix -d wifi-home.age
```

- [ ] **Step 2: Derive the PMK**

Supply the SSID yourself (it is not in the secret). `wpa_passphrase` prints a
block containing `psk=<64 hex chars>`; that hex value is the PMK.

```bash
wpa_passphrase '<YOUR_SSID>' '<passphrase from step 1>'
```

Expected output shape:

```
network={
	ssid="<YOUR_SSID>"
	#psk="<passphrase>"
	psk=1f2e3d4c5b6a798877665544332211ffeeddccbbaa99887766554433221100ff
}
```

Take the **uncommented** `psk=` line — the 64 hex characters, no quotes.

- [ ] **Step 3: Write installer-wifi.json in nix-secrets**

A JSON list, even with one entry, so networks can be added later without any
Nix change:

```json
[
  {
    "ssid": "<YOUR_SSID>",
    "psk": "1f2e3d4c5b6a798877665544332211ffeeddccbbaa99887766554433221100ff"
  }
]
```

This file is **deliberately unencrypted** — it is read at Nix eval time, which
agenix cannot serve. It is the first plaintext file in `nix-secrets`; the
rationale lives in the spec's "Security properties" section.

- [ ] **Step 4: Commit and push nix-secrets**

```bash
git add installer-wifi.json
git commit -m "feat: add installer ISO wifi credential"
git push
```

- [ ] **Step 5: Pull the new revision into this repo**

```bash
cd ~/Data/git/.worktrees/noams/nix-config/feat-installer-iso
nix flake update mysecrets
```

- [ ] **Step 6: Verify the file is visible to Nix**

```bash
nix eval --raw --impure --expr '(builtins.getFlake (toString ./.)).inputs.mysecrets.outPath' \
  | xargs -I{} ls {}/installer-wifi.json
```

Expected: prints a `/nix/store/...-source/installer-wifi.json` path.
If it prints "No such file", the push or the lock update did not land.

- [ ] **Step 7: Commit the lock bump**

```bash
git add flake.lock
git commit -m "chore(deps): update mysecrets for installer wifi credential"
```

---

## Task 2: Installer host skeleton

Builds a working, credential-free ISO configuration first, so that any failure
here is unambiguously about the ISO plumbing rather than the secret.

**Files:**
- Create: `hosts/installer/default.nix`
- Modify: `flake-modules/nixos-systems.nix`

- [ ] **Step 1: Create the installer module**

Create `hosts/installer/default.nix`:

```nix
# Generic installer ISO. Boots, joins wifi unattended, exposes sshd — the real
# install is driven from another machine with nixos-anywhere. Deliberately does
# not import nixos/default.nix: the desktop/laptop module tree is irrelevant
# here and would bloat the image.
{
  lib,
  modulesPath,
  ...
}: let
  hostConfigs = import ../../lib/host-configs.nix;
in {
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  # Real hosts pick this up from their generated hardware-configuration.nix;
  # the installer has none, and mkSystem doesn't pass a `system` arg.
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  networking.hostName = "installer";

  # installation-device.nix leaves root with an empty password, which sshd
  # refuses. The authorized key is the only usable way in for nixos-anywhere.
  users.users.root.openssh.authorizedKeys.keys = [hostConfigs.sshPublicKeys.noams];
}
```

`system.stateVersion` is deliberately absent: `installation-cd-base.nix`
already sets it with `mkDefault`, and a second `mkDefault` of equal priority is
a *conflict*, not an override.

- [ ] **Step 2: Register the configuration**

In `flake-modules/nixos-systems.nix`, add the installer to the
`nixosConfigurations` attrset so it reads:

```nix
    nixosConfigurations = {
      thinkpad-p14s-g5 = mkSystem ../hosts/thinkpad-p14s-g5;
      thinkpad-p14s-g6 = mkSystem ../hosts/thinkpad-p14s-g6;
      installer = mkSystem ../hosts/installer;
    };
```

- [ ] **Step 3: Track the new file, then evaluate**

The `git add` is mandatory — flake eval cannot see untracked files.

```bash
git add hosts/installer/default.nix flake-modules/nixos-systems.nix
nix eval .#nixosConfigurations.installer.config.system.build.isoImage.drvPath
```

Expected: a `/nix/store/...-nixos-*.iso.drv` path. Any evaluation error here is
a real problem — fix before continuing.

- [ ] **Step 4: Verify sshd and the root key are actually set**

```bash
nix eval .#nixosConfigurations.installer.config.services.openssh.enable
nix eval --json .#nixosConfigurations.installer.config.users.users.root.openssh.authorizedKeys.keys
```

Expected: `true`, and a one-element list containing the `ssh-ed25519 AAAAC3...`
key from `lib/host-configs.nix`.

- [ ] **Step 5: Commit**

```bash
git add hosts/installer/default.nix flake-modules/nixos-systems.nix
git commit -m "feat(installer): add generic installer ISO host"
```

Remember gotcha 2: if the hooks reformat, `git add` again and re-run the same
commit.

---

## Task 3: Bake in the wifi credential

**Depends on Task 1.** Will fail to evaluate otherwise.

**Files:**
- Modify: `hosts/installer/default.nix`

- [ ] **Step 1: Add the wifi profile wiring**

Rewrite `hosts/installer/default.nix` to add `inputs` to the module arguments,
the `networks`/`mkWifiProfile` let-bindings, and the `networkmanager` block.
The full file after this step:

```nix
# Generic installer ISO. Boots, joins wifi unattended, exposes sshd — the real
# install is driven from another machine with nixos-anywhere. Deliberately does
# not import nixos/default.nix: the desktop/laptop module tree is irrelevant
# here and would bloat the image.
{
  lib,
  modulesPath,
  inputs,
  ...
}: let
  hostConfigs = import ../../lib/host-configs.nix;

  # mysecrets is `flake = false`, so its contents are readable at eval time.
  # agenix cannot serve this: it decrypts at activation, which would mean
  # shipping a decryption key inside the image it is meant to protect.
  networks = builtins.fromJSON (builtins.readFile "${inputs.mysecrets}/installer-wifi.json");

  # Keyed by index rather than SSID so the generated
  # /run/NetworkManager/system-connections/<key>.nmconnection filename stays
  # safe regardless of spaces or slashes in the SSID.
  mkWifiProfile = i: net: {
    name = "wifi-${toString i}";
    value = {
      connection = {
        id = net.ssid;
        type = "wifi";
        autoconnect = true;
      };
      wifi = {
        ssid = net.ssid;
        mode = "infrastructure";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = net.psk;
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  };
in {
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];


  # Real hosts pick this up from their generated hardware-configuration.nix;
  # the installer has none, and mkSystem doesn't pass a `system` arg.
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  networking = {
    hostName = "installer";
    networkmanager.ensureProfiles.profiles =
      builtins.listToAttrs (lib.imap0 mkWifiProfile networks);
  };

  # installation-device.nix leaves root with an empty password, which sshd
  # refuses. The authorized key is the only usable way in for nixos-anywhere.
  users.users.root.openssh.authorizedKeys.keys = [hostConfigs.sshPublicKeys.noams];
}
```

- [ ] **Step 2: Verify the profile exists — without printing the PMK**

```bash
git add hosts/installer/default.nix
nix eval --json .#nixosConfigurations.installer.config.networking.networkmanager.ensureProfiles.profiles --apply builtins.attrNames
```

Expected: `["wifi-0"]`.

Do **not** run this without `--apply builtins.attrNames`; the raw value contains
the PMK and would be written into the terminal scrollback and this transcript.

- [ ] **Step 3: Verify the SSID reached the profile**

```bash
nix eval --raw .#nixosConfigurations.installer.config.networking.networkmanager.ensureProfiles.profiles.wifi-0.connection.id
```

Expected: your SSID. (`connection.id` is the display name, not a secret.)

- [ ] **Step 4: Verify the ensure-profiles unit is enabled**

The unit is `mkIf (profiles != {})`, so its presence proves the profiles landed.

```bash
nix eval .#nixosConfigurations.installer.config.systemd.services.NetworkManager-ensure-profiles.enable
```

Expected: `true`.

- [ ] **Step 5: Commit**

```bash
git add hosts/installer/default.nix
git commit -m "feat(installer): bake wifi credential into ISO from mysecrets"
```

---

## Task 4: Caches and console banner

**Files:**
- Modify: `hosts/installer/default.nix`

- [ ] **Step 1: Add `pkgs` to the module arguments and caches to the let-block**

This task is the first to need `pkgs` (for `terminus_font`), so the argument set
becomes `{ lib, pkgs, modulesPath, inputs, ... }`.

In `hosts/installer/default.nix`, add below the `hostConfigs` binding:

```nix
  caches = import ../../lib/caches.nix;
```

- [ ] **Step 2: Add the console import**

Change the `imports` list to:

```nix
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    ../../nixos/core/nice-looking-console.nix
  ];
```

`nice-looking-console.nix` takes only `lib` and `pkgs`, so it is safe to import
outside the `nixos/default.nix` tree. It sets `console.font` with `mkDefault`,
which the next step overrides.

- [ ] **Step 3: Add caches, font, and banner to the config body**

Append inside the returned attrset, after the `users.users.root` block:

```nix
  nix.settings = {
    # cache.flakehub.com is omitted deliberately: it uses JWT auth the
    # installer has no credentials for, so every fetch would warn for nothing.
    substituters = lib.filter (s: s != "https://cache.flakehub.com") caches.substituters;
    trusted-public-keys = caches.trustedPublicKeys;
    extra-substituters = caches.extraSubstituters;
    extra-trusted-public-keys = caches.extraTrustedPublicKeys;
  };

  # nice-looking-console.nix picks ter-u16n; bump it for HiDPI panels.
  console.font = "${pkgs.terminus_font}/share/consolefonts/ter-u22n.psf.gz";

  # helpLine is types.lines, so a plain definition would append to the stock
  # installer text ("To set up a wireless connection, run nmtui") rather than
  # replace it — hence mkForce.
  #
  # \4 is an agetty issue escape, expanded when the login prompt is drawn: the
  # IPv4 address of the first configured interface. The person reading this
  # screen is standing at the wrong keyboard, so tell them what to type on the
  # right one.
  services.getty.helpLine = lib.mkForce ''

    Wifi connects automatically. This machine is at \4

    From the nix-config checkout on your laptop:
        just install-host <host> \4
  '';
```

- [ ] **Step 4: Verify the caches landed and flakehub was dropped**

```bash
git add hosts/installer/default.nix
nix eval --json .#nixosConfigurations.installer.config.nix.settings.substituters
```

Expected: the list from `lib/caches.nix` **without** `https://cache.flakehub.com`.

- [ ] **Step 5: Verify the banner replaced rather than appended**

```bash
nix eval --raw .#nixosConfigurations.installer.config.services.getty.helpLine | grep -c nmtui
```

Expected: `0`. A `1` means `mkForce` is missing and the stale nmtui hint is
still there.

- [ ] **Step 6: Commit**

```bash
git add hosts/installer/default.nix
git commit -m "feat(installer): add binary caches and IP-aware console banner"
```

---

## Task 5: justfile recipes

**Files:**
- Modify: `justfile`

- [ ] **Step 1: Add both recipes**

Append to `justfile`, following the existing recipe style:

```just
# Build the generic installer ISO (contains wifi credentials — keep private)
iso:
    nix build .#nixosConfigurations.installer.config.system.build.isoImage
    @echo "ISO: $(realpath result/iso/*.iso)"
    @echo "Write it with: sudo dd if=$(realpath result/iso/*.iso) of=/dev/sdX bs=4M status=progress oflag=sync"

# Install a host remotely over ssh from a booted installer ISO
install-host host ip:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f "hosts/{{host}}/disko.nix" ]; then
        echo "❌ hosts/{{host}}/disko.nix does not exist." >&2
        echo "   nixos-anywhere needs a disko layout to partition the target." >&2
        echo "   Hosts with one: $(ls -d hosts/*/disko.nix | xargs -n1 dirname | xargs -n1 basename | tr '\n' ' ')" >&2
        exit 1
    fi
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#{{host}} --target-host root@{{ip}}
```

The shebang form matches how `seed-host`, `keyring-seal`, and `check-staged`
already handle non-trivial recipes in this justfile; a backslash-chained
one-liner would have been the odd one out.

The `disko.nix` guard is load-bearing: only `thinkpad-p14s-g6` has one today.
Without it, `install-host thinkpad-p14s-g5` would run for minutes and then fail
deep in the partitioning phase instead of in the first second.

- [ ] **Step 2: Verify the recipes parse and are listed**

```bash
just --list | grep -E 'iso|install-host'
```

Expected: both `iso` and `install-host host ip` appear.

- [ ] **Step 3: Verify the guard rejects a host with no disko.nix**

```bash
just install-host thinkpad-p14s-g5 192.0.2.1
```

Expected: fails immediately with "hosts/thinkpad-p14s-g5/disko.nix does not
exist" and lists `thinkpad-p14s-g6`. It must **not** attempt to reach the
network — `192.0.2.1` is a reserved documentation address specifically so this
check is safe to run.

- [ ] **Step 4: Commit**

```bash
git add justfile
git commit -m "feat(installer): add iso and install-host just recipes"
```

---

## Task 6: Build and smoke-test the image

**Files:** none modified.

- [ ] **Step 1: Build the ISO**

```bash
just iso
```

Expected: a `result/iso/*.iso` path is printed. First build pulls a lot; this
takes a while.

- [ ] **Step 2: Confirm the credential is genuinely in the image**

This is a *verification of the documented security property*, not a leak — it
confirms the ISO really does carry what the spec says it carries.

```bash
nix eval --raw .#nixosConfigurations.installer.config.systemd.services.NetworkManager-ensure-profiles.script | grep -c wifi-0
```

Expected: `1` or more.

- [ ] **Step 3: Boot it in QEMU**

```bash
qemu-system-x86_64 -m 4096 -smp 2 -cdrom result/iso/*.iso -nographic
```

Expected: boots to a login prompt showing the banner. Under `-nographic` the
`\4` escape will show no address (QEMU's default user-mode NIC is not wifi and
may not be up); that is fine here — Step 4 is what proves the banner.

- [ ] **Step 4: Confirm the banner text rendered**

At the QEMU console, the text between the greeting and the prompt must read
"Wifi connects automatically" and must **not** mention `nmtui`. If `nmtui`
appears, `mkForce` in Task 4 did not take effect.

Exit QEMU with `Ctrl-a x`.

- [ ] **Step 5: No commit**

Nothing changed. Proceed to Task 7.

---

## Task 7: Hardware validation (MANUAL — requires physical hardware)

An agent cannot do this. It is the only step that proves the wifi credential
actually works, since QEMU has no wifi adapter.

- [ ] **Step 1: Write the stick**

```bash
sudo dd if=result/iso/<name>.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Double-check `/dev/sdX` — this destroys the target device.

- [ ] **Step 2: Boot the target machine from the stick**

Expected: reaches the login banner, and the banner shows a real IPv4 address —
which proves wifi associated and DHCP completed with no interaction.

- [ ] **Step 3: Confirm ssh from your laptop**

```bash
ssh root@<ip from the banner> 'nixos-version'
```

Expected: prints a NixOS version. No password prompt — the baked key is what
authenticates.

- [ ] **Step 4: End-to-end install (destructive)**

Only against a machine whose disk you are willing to lose.

```bash
just install-host thinkpad-p14s-g6 <ip from the banner>
```

Expected: disko partitions the disk, the system installs, the machine reboots
into the real configuration.

- [ ] **Step 5: Push the branch and open the PR**

```bash
git push -u origin feat/installer-iso
gh pr create --assignee @me \
  --title "feat(installer): generic nixos-anywhere installer ISO" \
  --body "Adds nixosConfigurations.installer: a generic live ISO that auto-joins
home wifi and exposes sshd with my key, so bare-metal installs are driven
remotely with nixos-anywhere.

The wifi PMK is read at eval time from the private mysecrets input (agenix
decrypts at activation, which would mean shipping a decryption key inside the
image it protects). The built .iso therefore contains the PMK in cleartext and
is a private artifact.

Also adds \`just iso\` and \`just install-host <host> <ip>\`, the latter
guarded on the target having a disko.nix.

Spec: docs/superpowers/specs/2026-09-01-installer-iso-design.md"
```

---

## Follow-up (not in scope)

`wifi-home.age` in `nix-secrets` is referenced nowhere in `nix-config` and, once
`installer-wifi.json` exists, is only useful as the encrypted record of the
passphrase the PMK was derived from. Decide separately whether to keep it as
that record or delete it.

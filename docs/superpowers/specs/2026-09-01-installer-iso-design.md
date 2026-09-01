# Custom NixOS Installer ISO

**Date:** 2026-09-01
**Status:** Approved design, not yet implemented

## Purpose

A single, generic NixOS live ISO that boots on a bare machine, joins wifi
unattended, and exposes sshd with Noam's key — so the whole install is driven
remotely from another machine with `nixos-anywhere`. The ISO carries no
host-specific configuration; the target host is chosen at install time via
`nixos-anywhere --flake .#<host>`.

Non-goals: rescue/recovery tooling, per-host images, graphical installer,
Tailscale enrolment, agenix inside the ISO.

## Architecture

One new NixOS configuration, `nixosConfigurations.installer`, defined in
`hosts/installer/default.nix` and registered in
`flake-modules/nixos-systems.nix` alongside the existing hosts.

It imports `installation-cd-minimal.nix` from the locked nixpkgs
(`${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix`).
That module chain already provides, via `profiles/installation-device.nix`:

- NetworkManager enabled
- `services.openssh.enable = true` with `PermitRootLogin = "yes"`
- root and `nixos` users with empty passwords, `nixos` autologin on tty1
- `hardware.enableAllHardware`, EFI + USB bootable image

The installer host therefore only layers on the four additions below. It does
**not** import `nixos/default.nix` — the desktop/laptop module tree is
irrelevant to an installer and would bloat the image.

## Components

### 1. Wifi credentials (eval-time injection)

The private `mysecrets` input is `flake = false`, so its file contents are
readable at **evaluation** time. This is the mechanism that makes baked-in
credentials possible without agenix: agenix decrypts at *activation* time and
would require shipping a decryption key inside the image, which grants no real
protection since the key travels with the image.

`nix-secrets` gains a new file `installer-wifi.json`:

```json
[
  { "ssid": "HomeNet", "psk": "a3f1…64 hex chars" }
]
```

A JSON **list** even though only one network is configured today. Adding a
second network (phone hotspot, office) is then a `nix-secrets` edit plus an ISO
rebuild, with no change to the Nix code.

`psk` holds the PBKDF2-derived 64-hex PMK, not the passphrase, generated with:

```
wpa_passphrase '<ssid>' '<passphrase>'
```

NetworkManager's `wifi-security.psk` accepts the hex PMK identically to a
passphrase. Storing the derived key means the image does not disclose a
passphrase that may be reused elsewhere.

The module reads and maps it:

```nix
networks = builtins.fromJSON (builtins.readFile "${inputs.mysecrets}/installer-wifi.json");
```

into `networking.networkmanager.ensureProfiles.profiles`, one profile per entry:

- `connection` — `id`, `type = "wifi"`, `autoconnect = true`
- `wifi` — `ssid`, `mode = "infrastructure"`
- `wifi-security` — `key-mgmt = "wpa-psk"`, `psk`
- `ipv4.method = "auto"`, `ipv6.method = "auto"`

`ensureProfiles.profiles` is a freeform-INI submodule (verified present in
nixpkgs `56c02bc`), written out at boot by the `NetworkManager-ensure-profiles`
systemd unit.

### 2. SSH access for nixos-anywhere

```nix
users.users.root.openssh.authorizedKeys.keys = [
  (import ../../lib/host-configs.nix).sshPublicKeys.noams
];
```

`nixos-anywhere --target-host root@<ip>` requires root SSH. The installer
profile's empty root password cannot be used over ssh, so the authorized key is
the only usable path in. Reusing `lib/host-configs.nix` keeps the key in one
place.

### 3. Binary caches

`nix.settings` populated from `lib/caches.nix`, mirroring `nixos/core/nix.nix`,
so that whichever side of the install builds, substitution works.

`https://cache.flakehub.com` is **excluded** from the ISO's substituter list: it
uses JWT auth the installer has no credentials for, so every fetch would emit a
warning for no benefit. Its public keys are harmless to keep in
`trusted-public-keys`.

### 4. Console usability

- Import `nixos/core/nice-looking-console.nix`
- `console.font` set to a terminus size legible on a HiDPI panel
- `services.getty.helpLine` overridden (with `lib.mkForce`, since the profile
  sets it) to print the machine's current IP addresses and the literal
  `nixos-anywhere` command to paste on the driving machine

The last point exists because the person reading that screen is standing at the
wrong keyboard; the banner tells them what to type on the right one.

## Commands

Two `justfile` recipes:

- `just iso` — builds
  `.#nixosConfigurations.installer.config.system.build.isoImage` and reports the
  resulting path.
- `just install-host <host> <ip>` — runs
  `nixos-anywhere --flake .#<host> --target-host root@<ip>`, but **first
  verifies `hosts/<host>/disko.nix` exists** and aborts with a clear message if
  not.

The disko guard is load-bearing: only `thinkpad-p14s-g6` has a `disko.nix`
today. `thinkpad-p14s-g5` is still declared with static `fileSystems`, so
pointing `nixos-anywhere` at it would run for some minutes and then fail deep in
the partitioning phase. Failing in the first second with an explanatory message
is the difference.

## Out-of-band setup (manual, once)

1. Generate the PMK: `wpa_passphrase '<ssid>' '<passphrase>'`
2. Add `installer-wifi.json` to the private `nix-secrets` repo and push
3. `nix flake update mysecrets` in this repo to pick it up

Nothing sensitive enters this public repository.

## Security properties

The built `.iso` contains the wifi PMK in cleartext in its Nix store, readable
by anyone holding the image. This is inherent to an unattended-connect installer
and is accepted deliberately:

- The image is a private artifact — written to a USB stick, not shared or
  uploaded.
- The stored value is the derived PMK, so a leaked image discloses network
  access but not a reusable passphrase.
- `result*` is already gitignored, so the image cannot be committed by accident.

If the ISO ever needs to be shareable, the upgrade path is to move the
credential onto a second partition of the USB stick and read it at boot, leaving
the image itself credential-free.

## Testing

The ISO cannot be meaningfully unit-tested; verification is staged:

1. `nix flake check` — evaluation of the new configuration
2. `just iso` — the image builds
3. Boot the image in a VM — `qemu-system-x86_64 -cdrom result/iso/*.iso -m 4096`
   — and confirm the banner renders and sshd is listening. Wifi cannot be
   exercised under QEMU without a passed-through adapter.
4. Boot on real hardware, confirm it joins the network unattended and accepts
   `ssh root@<ip>` with the baked key.
5. End-to-end: `just install-host thinkpad-p14s-g6 <ip>` against a spare disk.

Steps 4 and 5 are manual and require physical hardware.

## Files

| File | Change | Purpose |
|------|--------|---------|
| `hosts/installer/default.nix` | Create | The installer NixOS module |
| `flake-modules/nixos-systems.nix` | Modify | Register `installer` |
| `justfile` | Modify | `iso` and `install-host` recipes |
| `nix-secrets:installer-wifi.json` | Create (private repo) | Wifi credential |

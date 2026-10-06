# Btrfs-on-LUKS Reinstall — tp-g5

Wipe g5 and reinstall it from g6 with `nixos-anywhere`, onto g6's btrfs-on-LUKS
layout (`disko.nix`). **The whole disk is wiped — Windows included.** The install
carries Secure Boot keys, the host key, and `~/.ssh`. `restore.sh` brings back
only the git roots and home-state paths in the table; anything else on the disk
is destroyed.

## Current vs target

| Component | Current | Target |
|-----------|---------|--------|
| Disk | Windows + LVM-on-LUKS (ext4 root, ext4 `~/Data`, swap LV) | ESP 1G + LUKS → btrfs, whole disk |
| Root FS | ext4 | btrfs subvolumes, `compress=zstd` |
| `~/Data` | own LV | a plain directory in `@home` |
| Swap | 72G LV | 16G swapfile in `@swap` (no hibernate — `SleepOperation = "suspend"`) |
| Boot | Lanzaboote | unchanged — same Secure Boot keys |
| Unlock | LUKS + TPM2 | unchanged — re-enrolled after install |

```
@      → /         @nix  → /nix       @swap → /swap (swapfile)
@home  → /home     @log  → /var/log
```

## What survives, and how

| State | Carried by | Why |
|-------|------------|-----|
| `/etc/ssh/ssh_host_ed25519_key` | `--extra-files` | agenix identity for host secrets, needed at first activation |
| `~/.ssh` | `--extra-files` | agenix identity for `noams_password` — no login without it |
| `/etc/secureboot` | `--extra-files` | the firmware already trusts these keys; fresh ones would fail Secure Boot |
| Keyrings, `~/.claude/projects`, fish/zoxide history, `~/.aws`, `~/.kube`, `~/.mozilla`, `~/.gnupg` | `restore.sh` | not needed to boot |
| Every git repo: all branches, every stash, uncommitted files, `.git/crew`, pruned worktrees | `restore.sh` | see `scripts/reinstall/backup.sh` header |

Full backup is ~12 GB.

## 1. Pre-flight (on g5)

1. **`main` must build.** The install builds `.#tp-g5` from g6; a red
   build fails mid-install, after the wipe. Check it on the branch you will
   install from:
   ```fish
   nix build --no-link .#nixosConfigurations.tp-g5.config.system.build.toplevel
   ```
2. **Network: ethernet.** nixos-anywhere's kexec installer has no Wi-Fi. Plug a
   cable (or a USB-ethernet adapter) into g5 and note its IP. Kexec also keeps
   Secure Boot on — the unsigned installer ISO would need it off.
3. **Let g6 in as root** — g5 declares no authorized keys, and kexec needs root:
   ```fish
   # g6's public key, e.g. scp'd over; /root/.ssh is wiped with the disk anyway
   sudo install -Dm600 g6.pub /root/.ssh/authorized_keys
   ```
4. **Back up** to the USB stick (asks for sudo once, for the root state):
   ```fish
   bash scripts/reinstall/backup.sh /run/media/noams/KINGSTONE/g5
   ```
   Then copy it to g6 as well — `reinstall-host` reads it from there:
   ```fish
   rsync -a /run/media/noams/KINGSTONE/g5/ g6:g5-backup/
   ```
5. **Push** every branch you care about that is not in the backup. Nothing
   outside `~/Data/git`, `~/nix-config`, `~/Documents`, `~/code`,
   `~/Downloads`, `~/data`, `~/tmux-config` and `~/.config/lzvim` is scanned.

## 2. Install (on g6)

```fish
set -l key (mktemp)
read -s -P 'New LUKS passphrase for g5: ' p
printf %s $p > $key
set -e p
just reinstall-host tp-g5 <g5-ip> ~/g5-backup $key
gtrash put $key
```

nixos-anywhere kexecs g5 into a RAM installer, runs disko (**the wipe**),
copies the staged files, installs, and reboots. If it fails after the kexec, g5
cannot boot until a rerun succeeds — the backup on g6 and the USB is the only
copy of your data from that point.

## 3. Post-install (on g5)

1. Boot, type the LUKS passphrase. Lanzaboote signed the bootloader with the
   restored keys, so Secure Boot passes without Setup Mode.
2. **On a TTY, before any graphical login**, pull the backup and restore:
   ```fish
   rsync -a g6:g5-backup/ ~/g5-backup/      # or copy from the USB stick
   bash ~/g5-backup/restore.sh ~/g5-backup
   ```
   It never overwrites an existing path, so a rerun is safe.

   Checkouts land in g6's layout: `~/Data/git/<rest>` is restored to
   `~/git/<rest>` (repos, linked worktrees, submodules, orphaned worktrees), and
   `~/.claude/projects/-home-<user>-Data-git-*` dirs are renamed to
   `-home-<user>-git-*` unless the target already exists. `~/nix-config` and the
   other backup roots keep their paths.
3. **Recovery key, then TPM** (`just tpm-enroll` finds the LUKS device itself):
   ```fish
   sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-root --recovery-key   # → password manager
   cd ~/nix-config; just tpm-enroll
   ```
4. **Delete the backups** — they hold your private keys unencrypted:
   ```fish
   gtrash put ~/g5-backup; ssh g6 gtrash put g5-backup
   ```
   and reformat the USB stick.

## Success criteria

- [ ] `sbctl status` — Secure Boot enabled, everything signed
- [ ] Reboot unlocks without a passphrase (TPM)
- [ ] `sudo systemd-cryptenroll /dev/disk/by-partlabel/disk-main-root` — password, recovery, tpm2
- [ ] `sudo btrfs subvolume list /` — `@ @home @nix @log @swap`; `swapon` shows `/swap/swapfile`
- [ ] `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` matches the old fingerprint
- [ ] `git -C <repo> branch` / `stash list` look like before for a few repos

## Rollback

There is no in-place rollback: the old disk is gone once disko runs. Recovery
is "make the install succeed" — fix the config on g6 and rerun
`just reinstall-host`; the backup stays valid across reruns.

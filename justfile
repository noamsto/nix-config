# NixOS Configuration Management
# Improved deployment and management commands

# Default recipe - show available commands
default:
    @just --list

# =============================================================================
# Development & Validation
# =============================================================================

# Format all code using alejandra and other formatters
fmt:
    nix fmt

# Check flake configuration
check:
    nix flake check

# Update all flake inputs
update:
    nix flake update

# Enter development shell
dev:
    nix develop

# =============================================================================
# Local System Management
# =============================================================================

# Build NixOS system (dry-run)
build HOST="$(hostname)":
    nh os build .#{{HOST}}

# Switch NixOS system configuration
switch HOST="$(hostname)":
    nh os switch .#{{HOST}}
    @just restart-noctalia

# Switch NixOS system configuration with staged changes only
switch-staged HOST="$(hostname)":
    nh os switch -S .#{{HOST}}
    @just restart-noctalia

# Boot NixOS configuration (apply on next reboot)
boot HOST="$(hostname)":
    nh os boot .#{{HOST}}

# Build specific derivation with nom output
build-with-nom DERIVATION:
    nom build ".#{{DERIVATION}}"

# Push paths a remote host would otherwise build or download for itself
seed-host SSH_HOST CONFIG:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    # Both trees must be identical, not just same-commit: a dirty tree changes
    # the derivation hashes, and the remote's .drv paths then don't resolve here
    if ! git diff --quiet HEAD || [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        echo "❌ local tree is dirty - commit first, or derivations won't match" >&2
        exit 1
    fi
    localRev=$(git rev-parse HEAD)
    remoteRev=$(ssh "{{SSH_HOST}}" 'git -C ~/nix-config status --porcelain --untracked-files=no | grep -q . && echo dirty || git -C ~/nix-config rev-parse HEAD')
    if [ "$remoteRev" = "dirty" ]; then
        echo "❌ {{SSH_HOST}}:~/nix-config has uncommitted changes" >&2
        exit 1
    fi
    if [ "$localRev" != "$remoteRev" ]; then
        echo "❌ rev mismatch: local ${localRev:0:8} vs {{SSH_HOST}} ${remoteRev:0:8}" >&2
        echo "   Both hosts must be on the same commit to share derivations." >&2
        exit 1
    fi

    echo "🔍 Asking {{SSH_HOST}} what it needs..."
    ssh "{{SSH_HOST}}" "cd ~/nix-config && nix build --dry-run .#nixosConfigurations.{{CONFIG}}.config.system.build.toplevel" 2>&1 \
        | tr -d ' ' > "$tmp/dry"
    awk '/willbebuilt:/{f=1;next} /willbefetched/{f=0} f' "$tmp/dry" | grep '^/nix/store' > "$tmp/tobuild" || true
    awk '/willbefetched/{f=1;next} f' "$tmp/dry" | grep '^/nix/store' > "$tmp/tofetch" || true
    if [ ! -s "$tmp/tobuild" ] && [ ! -s "$tmp/tofetch" ]; then
        echo "✅ {{SSH_HOST}} has everything already"
        exit 0
    fi
    echo "   $(wc -l < "$tmp/tobuild") to build, $(wc -l < "$tmp/tofetch") to fetch"

    # Instantiate locally so the remote's .drv paths resolve here
    nix path-info --derivation ".#nixosConfigurations.{{CONFIG}}.config.system.build.toplevel" >/dev/null

    # stdin: store paths -> stdout: only those already realised on this host
    keepLocal() {
        sort -u > "$tmp/cand"
        [ -s "$tmp/cand" ] || return 0
        xargs -r -a "$tmp/cand" nix-store --check-validity --print-invalid > "$tmp/bad"
        grep -Fxv -f "$tmp/bad" "$tmp/cand" || true
    }

    xargs -r -a "$tmp/tobuild" nix-store -q --outputs | keepLocal > "$tmp/seeds"
    keepLocal < "$tmp/tofetch" > "$tmp/direct"
    if [ ! -s "$tmp/seeds" ] && [ ! -s "$tmp/direct" ]; then
        echo "ℹ️  Nothing here that {{SSH_HOST}} needs"
        exit 0
    fi

    # Paths it would BUILD: no cache has them, so they must come from us. Their
    # deps usually are cacheable, hence --substitute-on-destination.
    if [ -s "$tmp/seeds" ]; then
        echo "🚀 $(wc -l < "$tmp/seeds") built outputs → {{SSH_HOST}}"
        xargs -r -a "$tmp/seeds" nix copy --to "ssh://{{SSH_HOST}}" --no-check-sigs --substitute-on-destination
    fi

    # Paths it would FETCH: it *can* substitute these, so -s is deliberately
    # omitted - when the remote's downlink is slower than this link, taking them
    # from us is the whole point.
    if [ -s "$tmp/direct" ]; then
        echo "🚀 $(wc -l < "$tmp/direct") fetchable paths → {{SSH_HOST}}"
        xargs -r -a "$tmp/direct" nix copy --to "ssh://{{SSH_HOST}}" --no-check-sigs
    fi
    echo "✅ Seeded {{SSH_HOST}}"

# =============================================================================
# Bare-Metal Provisioning
# =============================================================================

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

# First install of a host that has never booted (see install-host to reinstall)
bootstrap-host host ip key luks:
    #!/usr/bin/env bash
    set -euo pipefail
    # key:  pre-seeded /etc/ssh/ssh_host_ed25519_key (private) for this host
    # luks: file containing the LUKS passphrase — never commit this
    if [ ! -f "hosts/{{host}}/disko.nix" ]; then
        echo "❌ hosts/{{host}}/disko.nix does not exist." >&2
        echo "   nixos-anywhere needs a disko layout to partition the target." >&2
        echo "   Hosts with one: $(ls -d hosts/*/disko.nix | xargs -n1 dirname | xargs -n1 basename | tr '\n' ' ')" >&2
        exit 1
    fi
    for f in "{{key}}" "{{luks}}"; do
        if [ ! -f "$f" ]; then echo "❌ no such file: $f" >&2; exit 1; fi
    done
    # agenix decrypts with the host key at activation, so it must already be in
    # place the first time the system activates — hence --extra-files rather
    # than copying it afterwards. nixos-anywhere makes copied files root-owned;
    # the 0600 mode has to come from the staging tree.
    staging=$(mktemp -d)
    trap 'rm -rf "$staging"' EXIT
    install -Dm600 "{{key}}" "$staging/etc/ssh/ssh_host_ed25519_key"
    ssh-keygen -y -f "{{key}}" > "$staging/etc/ssh/ssh_host_ed25519_key.pub"
    chmod 644 "$staging/etc/ssh/ssh_host_ed25519_key.pub"
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#{{host}} \
        --target-host root@{{ip}} \
        --extra-files "$staging" \
        --disk-encryption-keys /tmp/disk.key "{{luks}}" \
        --generate-hardware-config nixos-generate-config hosts/{{host}}/hardware-configuration.nix

# Wipe and reinstall a host that already runs, carrying over its boot state
reinstall-host host ip backup luks:
    #!/usr/bin/env bash
    set -euo pipefail
    # backup: dir written by scripts/reinstall/backup.sh on the old install
    # luks:   file containing the new LUKS passphrase — never commit this
    if [ ! -f "hosts/{{host}}/disko.nix" ]; then
        echo "❌ hosts/{{host}}/disko.nix does not exist." >&2
        echo "   nixos-anywhere needs a disko layout to partition the target." >&2
        echo "   Hosts with one: $(ls -d hosts/*/disko.nix | xargs -n1 dirname | xargs -n1 basename | tr '\n' ' ')" >&2
        exit 1
    fi
    for f in "{{backup}}/root-state.tar" "{{backup}}/home-state.tar" "{{luks}}"; do
        if [ ! -f "$f" ]; then echo "❌ no such file: $f" >&2; exit 1; fi
    done
    for f in "{{backup}}/root-state.tar" "{{backup}}/home-state.tar"; do
        if ! tar -tf "$f" >/dev/null; then
            echo "❌ unreadable archive: $f" >&2
            exit 1
        fi
    done
    user=$(nix eval --raw .#nixosConfigurations.{{host}}.config.username)
    # A null uid is "not declared"; --raw cannot print null, so coerce it to empty.
    uid=$(nix eval --raw --apply 'u: if u == null then "" else toString u' \
        ".#nixosConfigurations.{{host}}.config.users.users.${user}.uid")
    gid=$(nix eval --raw --apply toString ".#nixosConfigurations.{{host}}.config.users.groups.users.gid")
    if [ -z "$uid" ]; then
        echo "❌ {{host}} must declare a uid for $user" >&2
        exit 1
    fi
    # Needed at first activation, so --extra-files rather than restore.sh:
    # the host key and ~/.ssh are agenix identities (host secrets, login
    # password), and lanzaboote signs the bootloader at install with the keys
    # the firmware already trusts — fresh ones would fail Secure Boot.
    staging=$(mktemp -d)
    trap 'rm -rf "$staging"' EXIT
    tar -C "$staging" -xpf "{{backup}}/root-state.tar"
    mkdir -p "$staging/home/$user"
    tar -C "$staging/home/$user" -xpf "{{backup}}/home-state.tar" .ssh
    nix run github:nix-community/nixos-anywhere -- \
        --flake .#{{host}} \
        --target-host root@{{ip}} \
        --extra-files "$staging" \
        --chown "/home/$user" "$uid:$gid" \
        --disk-encryption-keys /tmp/disk.key "{{luks}}"

# =============================================================================
# Home Manager
# =============================================================================

# Home Manager is embedded in each host's system config, so its activation
# package hangs off nixosConfigurations / darwinConfigurations rather than off a
# standalone homeConfigurations entry. See flake-modules/home-manager.nix.
hm-attr := if os() == "macos" { "darwinConfigurations" } else { "nixosConfigurations" }
hm-path := ".config.home-manager.users.noams.home.activationPackage"

# Activate Home Manager only - no system rebuild, no sudo
hm HOST=`hostname`:
    "$(nom build --no-link --print-out-paths '.#{{hm-attr}}.{{HOST}}{{hm-path}}')/activate"
    @just restart-noctalia
    @echo "ℹ️  packages live in the system profile — adding or removing one needs a full switch"

# Build Home Manager configuration without activating it
home-build HOST=`hostname`:
    nom build '.#{{hm-attr}}.{{HOST}}{{hm-path}}'

# =============================================================================
# Secret Management
# =============================================================================

# Edit encrypted secret
secret-edit SECRET:
    agenix -e secrets/{{SECRET}}.age

# Rekey all secrets
secret-rekey:
    agenix -r

# List available secrets
secret-list:
    @find secrets -name "*.age" -exec basename {} .age \;

# Seal the login password into the TPM for keyring auto-unlock on fingerprint
# login (TPM2 hosts: g5, g6). Re-run after password changes or Secure Boot db
# updates (PCR 7). Deliberately NOT committed: only this TPM in a trusted boot
# state can unseal it, so it is machine state rather than configuration, and
# losing it costs one keyring prompt per session until this is re-run.
keyring-seal:
    #!/usr/bin/env bash
    set -euo pipefail
    cred_name=noams-login-keyring
    out="/var/lib/gnome-keyring-tpm/${cred_name}.cred"
    read -rsp "🔑 Login password: " pw; echo
    sudo install -d -m 0755 "$(dirname "$out")"
    printf %s "$pw" | sudo systemd-creds encrypt --with-key=tpm2 --tpm2-device=auto --tpm2-pcrs=7 --name="$cred_name" - "$out"
    # Root-only: PID 1 reads it, the unlock unit never sees the ciphertext
    sudo chmod 0400 "$out"
    echo "✅ Sealed to $out — relogin to activate"

# (Re-)enroll the TPM2 LUKS auto-unlock on the root volume (TPM2 hosts: g5, g6,
# halo). Run after a firmware update or TPM clear drops boot to the password
# prompt. Binds PCR 7 only: Secure Boot with our own keys already gates what
# boots, and PCR 0 changes on every BIOS update.
tpm-enroll:
    #!/usr/bin/env bash
    set -euo pipefail
    dev=$(lsblk -lnpso NAME,FSTYPE "$(findmnt -no SOURCE --nofsroot /)" | awk '$2 == "crypto_LUKS" {print $1}')
    echo "🔐 LUKS root: $dev"
    # A TPM-only volume is locked out by the next PCR 7 change
    fallback=$(sudo cryptsetup luksDump --dump-json-metadata "$dev" | jq '(.keyslots | keys) - [.tokens[] | select(.type == "systemd-tpm2") | .keyslots[]] | length')
    if [ "$fallback" -eq 0 ]; then
        echo "❌ No password or recovery slot on $dev — add one first: sudo systemd-cryptenroll --recovery-key $dev" >&2
        exit 1
    fi
    sudo systemd-cryptenroll "$dev" --tpm2-device=auto --tpm2-pcrs=7 --wipe-slot=tpm2
    cred=/var/lib/gnome-keyring-tpm/noams-login-keyring.cred
    if sudo test -f "$cred" && ! sudo systemd-creds decrypt --name=noams-login-keyring "$cred" - >/dev/null 2>&1; then
        echo "🔑 Keyring credential no longer unseals — resealing"
        just keyring-seal
    fi
    echo "✅ TPM enrolled on $dev (PCR 7)"

# =============================================================================
# Utility Commands
# =============================================================================

# Show system information
info:
    @echo "🖥️  System Information:"
    @echo "Hostname: $(hostname)"
    @echo "NixOS Version: $(nixos-version)"
    @echo "Architecture: $(uname -m)"
    @echo ""
    @echo "🔧 Available NixOS Configurations:"
    @nix flake show --json | jq -r '.nixosConfigurations | keys[]' | sort
    @echo ""
    @echo "🏠 Available Home Manager Configurations:"
    @nix flake show --json | jq -r '.homeConfigurations | keys[]' 2>/dev/null | sort || echo "None found"

# Clean up build artifacts
clean:
    @echo "🧹 Cleaning up build artifacts..."
    rm -rf result*
    nix-collect-garbage

# Clean up aggressively (including generations)
clean-all:
    @echo "🧹 Aggressive cleanup (including generations)..."
    rm -rf result*
    sudo nix-collect-garbage -d
    nix-collect-garbage -d

# Show flake inputs and their status
status:
    @echo "📦 Flake Input Status:"
    nix flake metadata

# Restart noctalia.service after a rebuild.
#
# `nh os switch` flips /run/current-system, leaving the running shell with
# stale references (icon themes, fontconfig, /etc/os-release). Symptom: the
# Nix distro logo on ControlCenter (useDistroLogo=true) and other
# dynamically-resolved icons disappear until restart. v5 switched to a
# systemd user unit (programs.noctalia.systemd.enable) instead of the old
# exec-once/quickshell process, so restart that unit directly.
#
# Wired here rather than a Nix-level hook: NixOS activation runs as root with
# no graphical session env, and HM activation misses `nh os switch` entirely.
restart-noctalia:
    #!/usr/bin/env bash
    set -euo pipefail
    # LoadState (not is-active) so this stays a no-op on a machine where
    # noctalia isn't enabled, rather than erroring on an unknown unit.
    if [ "$(systemctl --user show -p LoadState --value noctalia.service)" != "loaded" ]; then
        exit 0
    fi
    echo "♻️  Restarting noctalia.service to refresh runtime state..."
    systemctl --user restart noctalia.service

# Allow charging to 100% until next reboot / `sudo systemctl restart tlp`
# (g5 only — fresh-battery fuel-gauge calibration).
battery-calibrate:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "$(hostname)" != "thinkpad-p14s-g5" ]; then
        echo "❌ battery-calibrate is gated to thinkpad-p14s-g5 (current: $(hostname))" >&2
        exit 1
    fi
    bat=/sys/class/power_supply/BAT0
    echo "🔋 Current: $(cat $bat/capacity)% — start=$(cat $bat/charge_start_threshold) stop=$(cat $bat/charge_stop_threshold)"
    echo "→ Raising stop threshold to 100 (runtime only; TLP restores 60/80 on reboot or 'sudo systemctl restart tlp')"
    echo 100 | sudo tee $bat/charge_stop_threshold > /dev/null
    echo "✅ stop=$(cat $bat/charge_stop_threshold)"
    echo ""
    echo "Calibration cycle:"
    echo "  1. Charge to 100% (plugged in)."
    echo "  2. Unplug, use until battery hits ~5% and the laptop warns / suspends."
    echo "  3. Plug in, charge back to 100%."
    echo "  4. Restore thresholds: sudo systemctl restart tlp"

# Rebind hid-multitouch to recover a touchpad that has gone silent (common on AMD ThinkPads post-suspend)
touchpad-rebind:
    #!/usr/bin/env bash
    set -euo pipefail
    drv=/sys/bus/hid/drivers/hid-multitouch
    id=$(find "$drv" -mindepth 1 -maxdepth 1 -regextype posix-extended \
        -regex '.*/[0-9A-F]{4}:[0-9A-F]{4}:[0-9A-F]{4}\.[0-9A-F]+' -printf '%f\n' | head -n1)
    if [ -z "$id" ]; then
        echo "❌ No HID device bound to hid-multitouch" >&2
        exit 1
    fi
    echo "♻️  Rebinding $id on hid-multitouch..."
    sudo sh -c "echo '$id' > '$drv/unbind' && sleep 1 && echo '$id' > '$drv/bind'"
    echo "✅ Done. Touch the touchpad to verify."

# Check if any staged git changes exist
check-staged:
    #!/usr/bin/env bash
    if ! git diff --cached --quiet; then
        echo "✅ Staged changes detected - builds will include them"
        echo "📝 Staged files:"
        git diff --cached --name-only | sed 's/^/  /'
    else
        echo "ℹ️  No staged changes - builds will use committed files only"
        echo "💡 Tip: Use 'git add <files>' to stage changes before building"
    fi

# =============================================================================
# Help & Documentation
# =============================================================================

# Show general help
help:
    @echo "🔧 NixOS Configuration Management"
    @echo "================================="
    @echo ""
    @echo "📚 Quick Start:"
    @echo "just dev              # Enter development shell"
    @echo "just check            # Validate configuration"
    @echo "just switch           # Apply configuration"
    @echo ""
    @echo "🔧 Maintenance:"
    @echo "just fmt              # Format code"
    @echo "just clean            # Clean build artifacts"
    @echo "just update           # Update flake inputs"
    @echo ""
    @echo "📖 Run 'just --list' for all available commands"

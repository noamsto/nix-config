# NixOS Configuration Management
# Improved deployment and management commands

# Default recipe - show available commands
default:
    @just --list

# =============================================================================
# Development & Validation
# =============================================================================

# Format all code with treefmt (alejandra, ruff, statix, deadnix, shellcheck, shfmt, prettier)
fmt:
    nix fmt

# Check flake configuration
check:
    nix flake check

# Dispatches .github/workflows/update.yml on main, follows the run, then
# fast-forwards a local main. Exits non-zero if the run failed.
# Run the update bot on demand (takes tens of minutes)
update:
    #!/usr/bin/env bash
    set -euo pipefail
    branch=$(git branch --show-current)
    dispatched_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    out=$(gh workflow run update.yml --ref main 2>&1) || { echo "$out" >&2; exit 1; }
    echo "$out"
    id=$(grep -oE 'actions/runs/[0-9]+' <<<"$out" | head -n1 | grep -oE '[0-9]+' || true)
    # Fallback: the newest dispatch run of update.yml on main created since we dispatched
    for _ in 1 2 3 4 5 6; do
        [ -n "$id" ] && break
        sleep 5
        id=$(gh run list --workflow update.yml --event workflow_dispatch --branch main --limit 10 \
            --json databaseId,createdAt \
            --jq "[.[] | select(.createdAt >= \"$dispatched_at\")] | sort_by(.createdAt) | .[0].databaseId // empty")
    done
    if [ -z "$id" ]; then
        echo "❌ Could not find the dispatched run; see: gh run list --workflow update.yml" >&2
        exit 1
    fi
    run_url=$(gh run view "$id" --json url --jq .url)
    echo "🔗 Update run: $run_url"
    status=0
    gh run watch "$id" --exit-status || status=$?
    if [ "$status" -ne 0 ]; then
        echo "❌ Update run failed: $run_url" >&2
        echo "🚧 Open update-blocked issues:" >&2
        gh issue list --label update-blocked || true
        exit "$status"
    fi
    echo "✅ Update run succeeded: $run_url"
    if [ "$branch" = main ]; then
        git pull --ff-only
    else
        echo "ℹ️  You are on '$branch', not main, and main has moved."
        echo "   To pick up the bump: git switch main && git pull --ff-only"
    fi

# Bypasses the bot (no build, cache push, fallback pins or lock commit): for testing
# a specific bump on a branch or offline. Pass input names to bump only those.
# Bump flake inputs locally, skipping the update bot
update-local *inputs:
    nix flake update {{inputs}}

# Enter development shell
dev:
    nix develop

# Seal the login password into the TPM for keyring auto-unlock on fingerprint
# login (TPM2 hosts: g5, g6). Re-run after password changes or Secure Boot db
# updates (PCR 7). Deliberately NOT committed: only this TPM in a trusted boot
# state can unseal it, so it is machine state rather than configuration, and
# losing it costs one keyring prompt per session until this is re-run.
keyring-seal:
    #!/usr/bin/env bash
    set -euo pipefail
    cred_name="${SUDO_USER:-$(id -un)}-login-keyring"
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
    cred_name="${SUDO_USER:-$(id -un)}-login-keyring"
    cred="/var/lib/gnome-keyring-tpm/${cred_name}.cred"
    if sudo test -f "$cred" && ! sudo systemd-creds decrypt --name="$cred_name" "$cred" - >/dev/null 2>&1; then
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
    @echo ""
    @echo "🔧 Maintenance:"
    @echo "just fmt              # Format code"
    @echo "just clean            # Clean build artifacts"
    @echo "just update           # Run the update bot on demand (tens of minutes)"
    @echo "just update-local     # Bump flake inputs locally, skipping the bot"
    @echo ""
    @echo "📖 Run 'just --list' for all available commands"

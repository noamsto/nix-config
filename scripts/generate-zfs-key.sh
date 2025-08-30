#!/usr/bin/env bash

# Generate ZFS encryption key for nixos-anywhere deployment
# This creates a temporary key file that will be deployed with the system

set -euo pipefail

# Configuration
KEY_FILE="/tmp/zfs-rpool-key"
POOL_NAME="rpool"

print_step() {
  echo "🔑 [ZFS-KEY] $1"
}

generate_key() {
  print_step "Generating 256-bit encryption key for ZFS pool '$POOL_NAME'"

  # Generate 32-byte (256-bit) random key
  dd if=/dev/urandom of="$KEY_FILE" bs=32 count=1 2>/dev/null
  chmod 600 "$KEY_FILE"

  print_step "Key generated: $KEY_FILE"
  print_step "This key will be deployed to /boot/zfs-keys/$POOL_NAME on the target system"
}

main() {
  if [[ -f $KEY_FILE ]]; then
    print_step "Key file already exists: $KEY_FILE"
    read -p "Regenerate? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      print_step "Using existing key file"
      exit 0
    fi
  fi

  generate_key

  print_step "Key ready for nixos-anywhere deployment"
  echo "Next: Run naspi-deploy.sh which will use this key automatically"
}

main "$@"

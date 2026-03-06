#!/usr/bin/env bash
# Shared library for Raspberry Pi deployment operations
# Provides metadata queries, validation, and common utilities

# shellcheck disable=SC2155  # Declare and assign separately - acceptable for simple getters
set -euo pipefail

# Color codes for output formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# =============================================================================
# Output Formatting Functions
# =============================================================================

print_info() {
  echo -e "${BLUE}ℹ${NC} $1" >&2
}

print_success() {
  echo -e "${GREEN}✓${NC} $1" >&2
}

print_error() {
  echo -e "${RED}✗${NC} $1" >&2
}

print_warn() {
  echo -e "${YELLOW}⚠${NC} $1" >&2
}

print_step() {
  echo -e "${BLUE}▸${NC} $1" >&2
}

# =============================================================================
# Metadata Query Functions
# =============================================================================

# Cached host config JSON — avoids repeated nix eval calls
declare -A _host_config_cache

# Get full configuration for a host (cached)
# Usage: get_host_config "naspi"
# Returns: JSON string with all host configuration
get_host_config() {
  local host=$1
  if [[ -z ${_host_config_cache[$host]+x} ]]; then
    _host_config_cache[$host]=$(nix eval --json ".#rpiHosts.${host}" 2>/dev/null)
  fi
  echo "${_host_config_cache[$host]}"
}

# Get hostname for a host configuration
get_hostname() {
  get_host_config "$1" | jq -r '.hostname'
}

# Get username for a host configuration
get_user() {
  get_host_config "$1" | jq -r '.user'
}

# Get flake name for a host configuration
get_flake() {
  get_host_config "$1" | jq -r '.flake'
}

# Get installer user for a host configuration
get_installer_user() {
  get_host_config "$1" | jq -r '.installer_user // "nixos"'
}

# Get filesystem type for a host configuration
get_filesystem() {
  get_host_config "$1" | jq -r '.filesystem // "ext4"'
}

# Get default build strategy for a host configuration
get_default_build_strategy() {
  get_host_config "$1" | jq -r '.build_strategy // "remote"'
}

# Check if host is an installer configuration
is_installer() {
  get_host_config "$1" | jq -r '.is_installer // false'
}

# =============================================================================
# Build Strategy Resolution
# =============================================================================

# Resolve build strategy based on user input and host defaults
# Usage: resolve_build_strategy "naspi" "auto|local|remote|custom"
# Returns: "local" or "remote:user@host" or custom value
resolve_build_strategy() {
  local host=$1
  local strategy=${2:-auto}

  case "$strategy" in
  local)
    echo "local"
    ;;
  remote)
    local user=$(get_user "$host")
    local hostname=$(get_hostname "$host")
    echo "remote:${user}@${hostname}"
    ;;
  auto)
    local default_strategy=$(get_default_build_strategy "$host")
    if [[ $default_strategy == "local" ]]; then
      echo "local"
    else
      local user=$(get_user "$host")
      local hostname=$(get_hostname "$host")
      echo "remote:${user}@${hostname}"
    fi
    ;;
  *)
    # Custom build host string
    echo "$strategy"
    ;;
  esac
}

# =============================================================================
# Validation Functions
# =============================================================================

# Validate that a host configuration exists
# Usage: validate_host_exists "naspi"
# Returns: 0 if exists, exits with error if not
validate_host_exists() {
  local host=$1

  if ! nix eval --json ".#rpiHosts.${host}" >/dev/null 2>&1; then
    print_error "Unknown host: $host"
    print_info "Available hosts:"
    nix eval --json ".#rpiHosts" 2>/dev/null | jq -r 'keys[]' | sed 's/^/  - /' >&2
    exit 1
  fi
}

# Check SSH connectivity to a host
# Usage: check_ssh "noams" "naspi.local"
# Returns: 0 if connectable, 1 if not
check_ssh() {
  local user=$1
  local host=$2

  ssh -o ConnectTimeout=5 \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    "$user@$host" exit 2>/dev/null
}

# Validate SSH connectivity with helpful error message
# Usage: validate_ssh "noams" "naspi.local"
# Returns: 0 if connectable, exits with error if not
validate_ssh() {
  local user=$1
  local host=$2

  print_step "Checking SSH connectivity to $user@$host..."

  if ! check_ssh "$user" "$host"; then
    print_error "Cannot connect to $user@$host via SSH"
    print_info "Troubleshooting:"
    print_info "  1. Check that the system is powered on and connected to network"
    print_info "  2. Verify hostname resolves: ping $host"
    print_info "  3. Test SSH manually: ssh $user@$host"
    print_info "  4. Check SSH key authentication is configured"
    exit 1
  fi

  print_success "SSH connection successful"
}

# =============================================================================
# Image Discovery Functions
# =============================================================================

# Find image file from build result
# Usage: find_image "result-rpi4-installer"
# Returns: path to image file (*.img, *.img.zst, or *.raw)
find_image() {
  local result_link=$1

  if [[ ! -e $result_link ]]; then
    print_error "Result link not found: $result_link"
    print_info "Did you run the build command first?"
    return 1
  fi

  local img_path
  img_path=$(readlink -f "$result_link")

  local img_file
  img_file=$(find "$img_path" -name "*.img*" -o -name "*.raw" 2>/dev/null | head -1)

  if [[ -z $img_file ]]; then
    print_error "No image file found in $img_path"
    print_info "Contents:"
    ls -lh "$img_path" >&2
    return 1
  fi

  echo "$img_file"
}

# =============================================================================
# Utility Functions
# =============================================================================

# Confirm destructive operation
# Usage: confirm_destructive "install" "naspi.local"
# Returns: 0 if confirmed, exits if not
confirm_destructive() {
  local operation=$1
  local target=$2

  print_warn "DESTRUCTIVE OPERATION: $operation on $target"
  print_warn "This will WIPE and REPARTITION the target disk!"
  echo ""
  read -p "Type 'yes' to continue, or anything else to abort: " -r
  echo ""

  if [[ $REPLY != "yes" ]]; then
    print_info "Aborted by user"
    exit 0
  fi
}

# List all available RPi hosts
# Usage: list_hosts
list_hosts() {
  print_info "Available Raspberry Pi configurations:"
  echo ""

  local hosts
  hosts=$(nix eval --json ".#rpiHosts" 2>/dev/null | jq -r 'keys[]')

  while IFS= read -r host; do
    local desc
    desc=$(nix eval --json ".#rpiHosts.${host}" 2>/dev/null | jq -r '.description // "No description"')
    printf "  %-18s %s\n" "$host" "$desc"
  done <<<"$hosts"
}

# Check required commands are available
# Usage: require_command nix ssh jq
# Returns: 0 if all available, exits with error if any missing
require_command() {
  local missing=()

  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    print_error "Missing required commands: ${missing[*]}"
    print_info "Please install the missing commands and try again"
    exit 1
  fi
}

# =============================================================================
# Initialization
# =============================================================================

# Ensure required commands are available
require_command nix jq

# Functions are available to sourcing scripts
# No need to export since they're defined in the same shell environment when sourced

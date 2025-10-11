#!/usr/bin/env bash

# Radarr and Sonarr Initial Configuration Script
# Configures root folders and download clients via API
# This script is idempotent and safe to run multiple times

set -euo pipefail

# Configuration
RADARR_URL="http://localhost:7878"
SONARR_URL="http://localhost:8989"
RADARR_CONFIG="/var/lib/radarr/.config/Radarr/config.xml"
SONARR_CONFIG="/var/lib/sonarr/.config/NzbDrone/config.xml"
TRANSMISSION_HOST="localhost"
TRANSMISSION_PORT="9091"

# Logging
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Wait for service to be ready
wait_for_service() {
  local url=$1
  local service_name=$2
  local max_attempts=30
  local attempt=0

  log "Waiting for $service_name to be ready..."
  while [ $attempt -lt $max_attempts ]; do
    if curl -s -f "$url/api/v3/system/status" -H "X-Api-Key: dummy" &>/dev/null ||
      curl -s -f "$url/ping" &>/dev/null; then
      log "$service_name is ready"
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 2
  done
  log "ERROR: $service_name failed to start after $max_attempts attempts"
  return 1
}

# Extract API key from config.xml
get_api_key() {
  local config_file=$1
  if [ ! -f "$config_file" ]; then
    log "ERROR: Config file not found: $config_file"
    return 1
  fi
  grep -oP '(?<=<ApiKey>)[^<]+' "$config_file" || true
}

# Check if root folder exists
check_root_folder() {
  local url=$1
  local api_key=$2
  local path=$3

  local response
  response=$(curl -s -H "X-Api-Key: $api_key" "$url/api/v3/rootfolder")
  echo "$response" | jq -e ".[] | select(.path == \"$path\")" &>/dev/null
}

# Add root folder
add_root_folder() {
  local url=$1
  local api_key=$2
  local path=$3
  local name=$4

  if check_root_folder "$url" "$api_key" "$path"; then
    log "Root folder already exists: $path"
    return 0
  fi

  log "Adding root folder: $path"
  if curl -s -X POST "$url/api/v3/rootfolder" \
    -H "Content-Type: application/json" \
    -H "X-Api-Key: $api_key" \
    -d "{\"path\": \"$path\", \"name\": \"$name\"}" >/dev/null; then
    log "Successfully added root folder: $path"
  else
    log "ERROR: Failed to add root folder: $path"
    return 1
  fi
}

# Check if download client exists
check_download_client() {
  local url=$1
  local api_key=$2
  local name=$3

  local response
  response=$(curl -s -H "X-Api-Key: $api_key" "$url/api/v3/downloadclient")
  echo "$response" | jq -e ".[] | select(.name == \"$name\")" &>/dev/null
}

# Add Transmission download client for Sonarr
add_transmission_client_sonarr() {
  local url=$1
  local api_key=$2
  local name=$3
  local category=$4

  if check_download_client "$url" "$api_key" "$name"; then
    log "Download client already exists: $name"
    return 0
  fi

  log "Adding Transmission download client for Sonarr: $name"

  # Transmission client configuration for Sonarr
  local client_config
  client_config=$(
    cat <<EOF
{
  "enable": true,
  "protocol": "torrent",
  "priority": 1,
  "removeCompletedDownloads": true,
  "removeFailedDownloads": true,
  "name": "$name",
  "fields": [
    {"name": "host", "value": "$TRANSMISSION_HOST"},
    {"name": "port", "value": $TRANSMISSION_PORT},
    {"name": "useSsl", "value": false},
    {"name": "urlBase", "value": "/transmission/"},
    {"name": "username", "value": "transmission"},
    {"name": "password", "value": "transmission"},
    {"name": "tvCategory", "value": "$category"},
    {"name": "tvImportedCategory", "value": ""},
    {"name": "tvDirectory", "value": ""},
    {"name": "recentTvPriority", "value": 0},
    {"name": "olderTvPriority", "value": 0},
    {"name": "addPaused", "value": false}
  ],
  "implementationName": "Transmission",
  "implementation": "Transmission",
  "configContract": "TransmissionSettings",
  "infoLink": "https://wiki.servarr.com/sonarr/supported#transmission",
  "tags": []
}
EOF
  )

  if curl -s -X POST "$url/api/v3/downloadclient" \
    -H "Content-Type: application/json" \
    -H "X-Api-Key: $api_key" \
    -d "$client_config" >/dev/null; then
    log "Successfully added download client: $name"
  else
    log "ERROR: Failed to add download client: $name"
    return 1
  fi
}

# Add Transmission download client for Radarr
add_transmission_client_radarr() {
  local url=$1
  local api_key=$2
  local name=$3
  local category=$4

  if check_download_client "$url" "$api_key" "$name"; then
    log "Download client already exists: $name"
    return 0
  fi

  log "Adding Transmission download client for Radarr: $name"

  # Transmission client configuration for Radarr
  local client_config
  client_config=$(
    cat <<EOF
{
  "enable": true,
  "protocol": "torrent",
  "priority": 1,
  "removeCompletedDownloads": true,
  "removeFailedDownloads": true,
  "name": "$name",
  "fields": [
    {"name": "host", "value": "$TRANSMISSION_HOST"},
    {"name": "port", "value": $TRANSMISSION_PORT},
    {"name": "useSsl", "value": false},
    {"name": "urlBase", "value": "/transmission/"},
    {"name": "username", "value": "transmission"},
    {"name": "password", "value": "transmission"},
    {"name": "movieCategory", "value": "$category"},
    {"name": "movieImportedCategory", "value": ""},
    {"name": "movieDirectory", "value": ""},
    {"name": "recentMoviePriority", "value": 0},
    {"name": "olderMoviePriority", "value": 0},
    {"name": "addPaused", "value": false}
  ],
  "implementationName": "Transmission",
  "implementation": "Transmission",
  "configContract": "TransmissionSettings",
  "infoLink": "https://wiki.servarr.com/radarr/supported#transmission",
  "tags": []
}
EOF
  )

  if curl -s -X POST "$url/api/v3/downloadclient" \
    -H "Content-Type: application/json" \
    -H "X-Api-Key: $api_key" \
    -d "$client_config" >/dev/null; then
    log "Successfully added download client: $name"
  else
    log "ERROR: Failed to add download client: $name"
    return 1
  fi
}

# Main configuration
main() {
  log "Starting Radarr and Sonarr configuration..."

  # Wait for services
  wait_for_service "$RADARR_URL" "Radarr" || exit 1
  wait_for_service "$SONARR_URL" "Sonarr" || exit 1

  # Get API keys
  log "Retrieving API keys..."
  RADARR_API_KEY=$(get_api_key "$RADARR_CONFIG")
  SONARR_API_KEY=$(get_api_key "$SONARR_CONFIG")

  if [ -z "$RADARR_API_KEY" ]; then
    log "ERROR: Failed to retrieve Radarr API key"
    exit 1
  fi

  if [ -z "$SONARR_API_KEY" ]; then
    log "ERROR: Failed to retrieve Sonarr API key"
    exit 1
  fi

  log "API keys retrieved successfully"

  # Configure Radarr
  log "Configuring Radarr..."
  add_root_folder "$RADARR_URL" "$RADARR_API_KEY" "/media/storage/movies" "Movies"
  add_transmission_client_radarr "$RADARR_URL" "$RADARR_API_KEY" "Transmission" "movies"

  # Configure Sonarr
  log "Configuring Sonarr..."
  add_root_folder "$SONARR_URL" "$SONARR_API_KEY" "/media/storage/tv" "TV Shows"
  add_transmission_client_sonarr "$SONARR_URL" "$SONARR_API_KEY" "Transmission" "tv"

  # Export API keys for recyclarr (separate files for secret substitution)
  echo -n "$RADARR_API_KEY" >/var/lib/recyclarr/.env-radarr-api-key
  echo -n "$SONARR_API_KEY" >/var/lib/recyclarr/.env-sonarr-api-key
  chown recyclarr:media /var/lib/recyclarr/.env-radarr-api-key /var/lib/recyclarr/.env-sonarr-api-key
  chmod 600 /var/lib/recyclarr/.env-radarr-api-key /var/lib/recyclarr/.env-sonarr-api-key

  log "Configuration completed successfully!"
  log "You can now:"
  log "  1. Run 'systemctl start recyclarr-sync' to sync quality profiles"
  log "  2. Configure indexers in Prowlarr UI (http://localhost:9696)"
  log "  3. Add content to Radarr and Sonarr"
}

main "$@"

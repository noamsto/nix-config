# Converges Jellyfin plugins, library subtitle options and Open Subtitles credentials
# through the HTTP API, restarting Jellyfin once when a plugin waits for a restart.
# Usage: jellyfin-declarative-apply <config.json>
{pkgs}:
pkgs.writeShellApplication {
  name = "jellyfin-declarative-apply";
  # systemctl comes from the caller's PATH so a test can stub it; a runtimeInput would shadow the stub.
  runtimeInputs = [pkgs.curl pkgs.jq pkgs.coreutils];
  text = ''
    cfg=$1

    base=$(jq -r .baseUrl "$cfg")
    apiKeyFile=$(jq -r .apiKeyFile "$cfg")
    jellyfinUnit=$(jq -r .jellyfinUnit "$cfg")
    jellarrUnit=$(jq -r .jellarrUnit "$cfg")
    readyTimeout=$(jq -r .readyTimeout "$cfg")

    key=$(tr -d '[:space:]' < "$apiKeyFile")

    # The key travels through a builtin printf into a pipe, so it never lands on an argv.
    api() {
      curl -fsS -H @<(printf 'Authorization: MediaBrowser Token="%s", Client="jellarr-post", Device="nixos", DeviceId="jellarr-post", Version="1"\n' "$key") "$@"
    }

    post() {
      api -X POST -H 'Content-Type: application/json' --data-binary @- "$1"
    }

    failed=0
    fail() {
      printf '%s\n' "$*" >&2
      failed=1
    }

    wait_ready() {
      local i
      for ((i = 0; i < readyTimeout; i++)); do
        if curl -fsS --max-time 5 -o /dev/null "$base/System/Info/Public" 2>/dev/null; then
          return 0
        fi
        sleep 1
      done
      printf 'jellyfin not ready after %s seconds\n' "$readyTimeout" >&2
      exit 1
    }

    wait_ready

    restarted=0
    openSubtitlesActive=0
    if jq -e '.plugins | length > 0' "$cfg" > /dev/null; then
      plugins_json=$(api "$base/Plugins")
      if printf '%s' "$plugins_json" | jq -e 'any(.[]; .Status == "Restart")' > /dev/null; then
        echo "restarting $jellyfinUnit to load pending plugins"
        systemctl restart "$jellyfinUnit"
        wait_ready
        plugins_json=$(api "$base/Plugins")
        restarted=1
      fi

      mapfile -t plugins < <(jq -r '.plugins[]' "$cfg")
      for name in "''${plugins[@]}"; do
        if printf '%s' "$plugins_json" | jq -e --arg n "$name" 'any(.[]; .Name == $n and .Status == "Active")' > /dev/null; then
          echo "plugin $name: active"
          if [ "$name" = "Open Subtitles" ]; then
            openSubtitlesActive=1
          fi
        else
          statuses=$(printf '%s' "$plugins_json" | jq -r --arg n "$name" '[.[] | select(.Name == $n) | .Status] | if length == 0 then "not installed" else join(", ") end')
          fail "plugin $name: $statuses"
        fi
      done
    fi

    if jq -e '.libraries | length > 0' "$cfg" > /dev/null; then
      folders=$(api "$base/Library/VirtualFolders")
      mapfile -t libraries < <(jq -c '.libraries[]' "$cfg")
      for lib in "''${libraries[@]}"; do
        name=$(printf '%s' "$lib" | jq -r .name)
        folder=$(printf '%s' "$folders" | jq -c --argjson lib "$lib" 'first(.[] | select(.Name == $lib.name)) // empty')
        if [ -z "$folder" ]; then
          fail "library $name: not found"
          continue
        fi
        if printf '%s' "$folder" | jq -e --argjson lib "$lib" '.LibraryOptions == (.LibraryOptions + $lib.options)' > /dev/null; then
          echo "library $name: up to date"
        elif printf '%s' "$folder" | jq -c --argjson lib "$lib" '{Id: .ItemId, LibraryOptions: (.LibraryOptions + $lib.options)}' | post "$base/Library/VirtualFolders/LibraryOptions"; then
          echo "library $name: updated subtitle options"
        else
          fail "library $name: update failed"
        fi
      done
    fi

    if jq -e '.openSubtitles != null' "$cfg" > /dev/null && [ "$openSubtitlesActive" = 1 ]; then
      pluginId=$(jq -r .openSubtitles.pluginId "$cfg")
      usernameFile=$(jq -r .openSubtitles.usernameFile "$cfg")
      passwordFile=$(jq -r .openSubtitles.passwordFile "$cfg")
      configUrl="$base/Plugins/$pluginId/Configuration"
      # Credential values reach jq only via --rawfile and curl only via stdin; never echo $current.
      if ! current=$(api "$configUrl"); then
        fail "Open Subtitles: reading configuration failed"
      elif printf '%s' "$current" | jq -e --rawfile u "$usernameFile" --rawfile p "$passwordFile" '.Username == ($u | trim) and .Password == ($p | trim) and (.CredentialsInvalid | not)' > /dev/null; then
        echo "Open Subtitles: credentials up to date"
      elif printf '%s' "$current" | jq -c --rawfile u "$usernameFile" --rawfile p "$passwordFile" '. + {Username: ($u | trim), Password: ($p | trim), CredentialsInvalid: false}' | post "$configUrl"; then
        echo "Open Subtitles: credentials updated"
      else
        fail "Open Subtitles: updating credentials failed"
      fi
    fi

    if [ "$restarted" = 1 ] && [ "$failed" = 0 ]; then
      echo "starting $jellarrUnit after the plugin restart"
      systemctl start --no-block "$jellarrUnit"
    fi

    exit "$failed"
  '';
}

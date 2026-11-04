# Sets KnownProxies in Jellyfin's network.xml, leaving every other key alone.
# Usage: jellyfin-known-proxies <network.xml> [proxy...]
{pkgs}:
pkgs.writeShellApplication {
  name = "jellyfin-known-proxies";
  runtimeInputs = [pkgs.xmlstarlet pkgs.coreutils];
  text = ''
    file=$1
    shift

    if [ ! -e "$file" ]; then
      printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>' '<NetworkConfiguration/>' > "$file"
    fi

    # Same-directory temp file so the mv is an atomic rename.
    tmp=$(mktemp "$file.XXXXXX")
    trap 'rm -f "$tmp"' EXIT

    args=(ed -d /NetworkConfiguration/KnownProxies -s /NetworkConfiguration -t elem -n KnownProxies)
    for proxy in "$@"; do
      args+=(-s /NetworkConfiguration/KnownProxies -t elem -n string -v "$proxy")
    done

    xmlstarlet "''${args[@]}" "$file" > "$tmp"
    chmod --reference="$file" "$tmp"
    mv "$tmp" "$file"
  '';
}

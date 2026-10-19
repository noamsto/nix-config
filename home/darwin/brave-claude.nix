{
  lib,
  pkgs,
  config,
  ...
}: let
  support = "${config.home.homeDirectory}/Library/Application Support";
  dataDir = "${support}/BraveSoftware/Brave-Claude";

  # Claude in Chrome and 1Password, installed from the Chrome Web Store into
  # this data dir only (Chromium's per-user external-extension mechanism).
  extensionIds = [
    "fcoeoabgfenejglbffodgkkbkcdhcgfn" # Claude
    "aeblfdkhhhdcdjpifhhbdiojplfjncoa" # 1Password
  ];

  # Separate Brave instance for Claude Code's browser integration. The
  # --user-data-dir flag is what isolates it (own cookies, extensions, singleton
  # lock, so it runs next to the personal Brave), and it can't be set any other
  # way, so this wrapper is the entry point.
  #
  # Chromium reads native messaging hosts from <user-data-dir>/NativeMessagingHosts,
  # but Claude Code only writes its manifest into Brave's default dir, and
  # 1Password writes its own there (or into Chrome's) when its browser
  # integration is on. Both files are owned by those tools, so they are linked at
  # every launch rather than frozen at activation: updates keep working, and an
  # absent source (e.g. before `claude --chrome` first ran) is just skipped.
  brave-claude = pkgs.writeShellApplication {
    name = "brave-claude";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      data_dir=${lib.escapeShellArg dataDir}
      brave_hosts=${lib.escapeShellArg "${support}/BraveSoftware/Brave-Browser/NativeMessagingHosts"}
      chrome_hosts=${lib.escapeShellArg "${support}/Google/Chrome/NativeMessagingHosts"}
      hosts="$data_dir/NativeMessagingHosts"

      mkdir -p "$hosts"

      # link_manifest <file> <dir>...: link the first existing source, drop a stale link.
      link_manifest() {
        file=$1
        shift
        for dir in "$@"; do
          if [ -e "$dir/$file" ]; then
            ln -sfn "$dir/$file" "$hosts/$file"
            return
          fi
        done
        rm -f "$hosts/$file"
      }

      link_manifest com.anthropic.claude_code_browser_extension.json "$brave_hosts"
      # allowed_origins are Web Store extension ids, so Chrome's copy works for Brave too.
      link_manifest com.1password.1password.json "$brave_hosts" "$chrome_hosts"

      exec "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
        --user-data-dir="$data_dir" "$@"
    '';
  };
in
  lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    home.packages = [brave-claude];

    home.file = lib.listToAttrs (map (id:
      lib.nameValuePair "${lib.removePrefix "${config.home.homeDirectory}/" dataDir}/External Extensions/${id}.json" {
        text = builtins.toJSON {external_update_url = "https://clients2.google.com/service/update2/crx";};
      })
    extensionIds);
  }

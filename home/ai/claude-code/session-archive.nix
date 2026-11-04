{
  pkgs,
  lib,
  config,
  ...
}: let
  # Both paths derive from $HOME inside the script, not from Nix, so the whole
  # job can be exercised against a throwaway HOME.
  claude-session-archive = pkgs.writeShellApplication {
    name = "claude-session-archive";
    runtimeInputs = [pkgs.rsync pkgs.zstd pkgs.findutils];
    text = ''
      src="$HOME/.claude/projects"
      dst="$HOME/.local/state/claude-session-archive/projects"

      [ -d "$src" ] || exit 0
      mkdir -p "$dst"

      # No --delete: Claude Code prunes its own tree at ~30 days, the archive
      # never does. Sessions are append-only, so -a picks up in-place growth.
      rsync -a "$src/" "$dst/"

      # Compress only what upstream has already dropped. Compressing a file
      # that still exists in $src would just be re-inflated by the next rsync.
      cd "$dst"
      find . -name '*.jsonl' -type f -print0 | while IFS= read -r -d "" f; do
        [ -e "$src/$f" ] || zstd -q --rm -- "$f"
      done
    '';
  };
in
  lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
    home.packages = [claude-session-archive];

    # Daily, in the "user" domain — no Aqua session needed. launchd coalesces
    # runs missed while the laptop was asleep to the next wake, unlike cron.
    launchd.agents.claude-session-archive = {
      enable = true;
      domain = "user";
      config = {
        ProgramArguments = ["${claude-session-archive}/bin/claude-session-archive"];
        StartCalendarInterval = [
          {
            Hour = 4;
            Minute = 15;
          }
        ];
        StandardOutPath = "${config.home.homeDirectory}/.local/state/claude-session-archive.log";
        StandardErrorPath = "${config.home.homeDirectory}/.local/state/claude-session-archive.log";
      };
    };
  }

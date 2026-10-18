# priors' user side, gated by `osConfig.priors.enable` (nixos/core/priors.nix,
# which also owns the binary and the trust file).
#
# The manifest only contributes a path to `programs.hookyard.manifests`:
# ../hookyard owns the single install pass. `exec` is the store path because
# `hookyard install` stats every exec.
{
  lib,
  osConfig,
  pkgs,
  ...
}: let
  cfg = osConfig.priors;
  priors = lib.getExe cfg.package;
  inherit (cfg.personalStore) path remote;

  # cmd/priors/hookyard.json at the locked hookyard rev, exec swapped for the store path.
  manifest = pkgs.writeText "priors-hookyard.json" (builtins.toJSON {
    handlers = [
      {
        id = "priors-index";
        exec = priors;
        events = ["session_start"];
        engines = ["claude-code" "codex" "pi"];
        timeout_ms = 1000;
      }
      {
        id = "priors-record";
        exec = priors;
        events = ["post_tool"];
        engines = ["claude-code" "codex" "cursor" "pi"];
        lane = "fire_and_forget";
      }
      {
        id = "priors-provenance";
        exec = priors;
        events = ["pre_tool"];
        engines = ["claude-code" "codex" "cursor" "pi"];
        match = ["Bash"];
        timeout_ms = 1000;
      }
    ];
  });
in {
  config = lib.mkIf cfg.enable {
    programs.hookyard.manifests = [manifest];

    xdg.configFile."priors/config.toml".text = ''
      push = true
    '';

    home.activation.priorsPersonalStore = lib.hm.dag.entryAfter ["writeBoundary"] ''
      store=${lib.escapeShellArg path}
      remote=${lib.escapeShellArg remote}
      if [ -e "$store" ] || [ -L "$store" ]; then
        verboseEcho "priors: $store exists, leaving it as is"
      elif [[ -v DRY_RUN ]]; then
        echo "priors: would clone $remote into $store"
      else
        # Activation runs under `set -eu`, so every step that can fail sits in
        # the condition and warns instead of aborting the switch. The temp dir
        # and `mv -T` keep a half or nested checkout from landing at $store.
        # The keepalives override the user's `ServerAliveInterval 0`, so a dead
        # connection fails the clone instead of hanging it. The 180s cap on the
        # clone stays well under HM's 5m start timeout, which would otherwise
        # fail the switch; timeout signals its whole process group, ssh included.
        parent=$(dirname "$store")
        tmp=""
        if ! { mkdir -p "$parent" \
          && tmp=$(mktemp -d "$parent/.priors-clone.XXXXXX") \
          && GIT_TERMINAL_PROMPT=0 \
            GIT_SSH_COMMAND="${pkgs.openssh}/bin/ssh -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3" \
            ${pkgs.coreutils}/bin/timeout --kill-after=10 180 \
            ${pkgs.git}/bin/git clone --quiet --origin origin -- "$remote" "$tmp/repo" \
          && mv -T "$tmp/repo" "$store"; }; then
          warnEcho "priors: could not clone $remote; the personal store stays empty until: git clone $remote $store"
        fi
        [ -z "$tmp" ] || rm -rf "$tmp"
      fi
    '';
  };
}

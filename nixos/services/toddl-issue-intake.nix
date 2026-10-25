# Minutely toddl issue-intake pass. It runs from a dedicated clone, never the
# owner's ~/git/toddl, so the checkout can be force-reset to origin/main
# without touching their work.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.toddlIssueIntake;

  intake = pkgs.writeShellApplication {
    name = "toddl-issue-intake";
    runtimeInputs = [
      pkgs.bash
      pkgs.git
      pkgs.openssh
      pkgs.just
      pkgs.direnv
      config.nix.package
      pkgs.bubblewrap
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      # pi, claude, gh and tmux come from the user's profile (tmux must match the
      # owner's running server, whose socket TMUX_TMPDIR points at); op is the
      # setgid wrapper.
      export PATH="$PATH:/etc/profiles/per-user/${cfg.user}/bin:/run/wrappers/bin"

      checkout="$HOME/.local/state/toddl-issue-intake-checkout"
      if [ ! -e "$checkout/.git" ]; then
        rm -rf "$checkout"
        git clone --quiet git@github.com:noamsto/toddl.git "$checkout"
      fi

      # The consumer fetches too when it triages, so a stale origin/main is tolerable.
      stamp="$checkout/.git/intake-fetched"
      if [ ! -e "$stamp" ] || [ -z "$(find "$stamp" -mmin -10)" ]; then
        if git -C "$checkout" fetch --quiet origin +refs/heads/main:refs/remotes/origin/main; then
          touch "$stamp"
        else
          echo "toddl-issue-intake: fetch failed, using the last fetched origin/main" >&2
        fi
      fi

      git -C "$checkout" -c core.hooksPath=/dev/null checkout --quiet --detach --force origin/main
      git -C "$checkout" clean -ffdq

      # Allow is keyed on .envrc content; re-allowing keeps an upstream edit from blocking the timer.
      direnv allow "$checkout"
      exec direnv exec "$checkout" just --justfile "$checkout/justfile" --working-directory "$checkout" issue-intake --once
    '';
  };
in {
  options.services.toddlIssueIntake = {
    enable = lib.mkEnableOption "the toddl Telegram issue-intake timer";
    user = lib.mkOption {
      type = lib.types.str;
      default = config.username;
      description = "Owner of the intake checkout and the pi, claude and gh credentials.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = intake;
      description = "Refreshes the checkout and runs one intake pass.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user = {
      services.toddl-issue-intake = {
        description = "toddl: file GitHub issues queued from Telegram";
        unitConfig.ConditionUser = cfg.user;
        # Matches tmux-startup.service's TMUX_TMPDIR=%t, so the slot count reaches
        # the owner's tmux server instead of an empty /tmp socket.
        environment.TMUX_TMPDIR = "%t";
        # A restart mid-switch races the network restart and fails `op read`;
        # the minutely timer runs the new unit anyway.
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${intake}/bin/toddl-issue-intake";
          TimeoutStartSec = "30min";
        };
      };

      timers.toddl-issue-intake = {
        description = "Poll for queued toddl issue requests";
        unitConfig.ConditionUser = cfg.user;
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "minutely";
          Persistent = false;
        };
      };
    };
  };
}

{inputs, ...}: {
  imports = [inputs.pre-commit-hooks.flakeModule];

  perSystem = {pkgs, ...}: {
    pre-commit = {
      settings.package = pkgs.prek;
      settings.excludes = ["flake.lock"];

      settings.hooks = {
        treefmt.enable = true;
        # A mangled claude-code/settings.json is live the moment it lands on disk
        # (mkOutOfStoreSymlink), so these only stop it spreading to other hosts.
        check-json.enable = true;
        check-merge-conflicts.enable = true;
        # git-hooks.nix ships no betterleaks hook, hence the literal entry.
        # `git --pre-commit --staged` scans what is about to be committed
        # rather than the whole history, so it stays fast on every commit.
        betterleaks = {
          enable = true;
          name = "betterleaks";
          entry = "${pkgs.betterleaks}/bin/betterleaks git --pre-commit --staged --redact --no-banner";
          language = "system";
          pass_filenames = false;
          # The global flake.lock exclude would otherwise skip a commit that stages only flake.lock.
          always_run = true;
        };
        # Scans every local branch and tag not yet on the remote, plus the pushed
        # sha (prek sets TO to it and leaves FROM unset on a root-commit first
        # push). A leak on any unpushed ref therefore blocks the push.
        # `stages` is only pre-push, so `prek run --all-files` (the flake check)
        # never runs it.
        betterleaks-pre-push = {
          enable = true;
          name = "betterleaks-pre-push";
          entry = let
            wrapper = pkgs.writeShellApplication {
              name = "pre-push-leak-check";
              runtimeInputs = [pkgs.betterleaks pkgs.git pkgs.coreutils];
              text = ''exec ${./scripts/pre-push-leak-check.sh} "$@"'';
            };
          in "${wrapper}/bin/pre-push-leak-check";
          language = "system";
          stages = ["pre-push"];
          pass_filenames = false;
          always_run = true;
        };
      };
    };
  };
}

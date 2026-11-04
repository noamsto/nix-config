{inputs, ...}: {
  imports = [inputs.pre-commit-hooks.flakeModule];

  perSystem = {pkgs, ...}: {
    pre-commit = {
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
      };
    };
  };
}

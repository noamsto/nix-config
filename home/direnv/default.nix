{inputs, ...}: {
  pkgs,
  config,
  ...
}: {
  programs = {
    direnv = {
      enable = true;
      nix-direnv = {
        enable = true;
        # nix-direnv pins NIX_DIRENV_FALLBACK_NIX to its bundled upstream nixpkgs
        # Nix, which doesn't know Determinate's eval-cores/lazy-trees settings and
        # warns "unknown setting" on every flake load. Point it at Determinate's
        # own Nix (its nix-src fork, substituted from cache.flakehub.com).
        package = pkgs.nix-direnv.override {
          nix = inputs.determinate.inputs.nix.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };
      };
      config = {
        global = {
          hide_env_diff = true;
        };
        # Auto-trust every .envrc under these trees so each new git worktree
        # loads the devshell without a manual `direnv allow` — otherwise the
        # shared but path-keyed approval is missing and tools like semgrep that
        # only live in the devshell vanish from PATH. Covers the consolidated
        # worktree root (worktrunk.worktreePath).
        whitelist = {
          prefix = [
            "${config.home.homeDirectory}/git/.worktrees"
            # Legacy prefixes below stay until no host has worktrees left under the old location.
            "${config.home.homeDirectory}/Data/git/.worktrees"
          ];
        };
      };
    };
  };
}

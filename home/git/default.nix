{
  lib,
  osConfig,
  pkgs,
  ...
}: let
  agent = osConfig.nix-config.ssh.onePasswordAgent;
in {
  imports = [
    ./lazygit.nix
    ./repos.nix
  ];

  # NOTE: ~/.config/git/theme-override is managed by theme-toggle script at runtime
  # It's NOT managed by Home Manager since we need to write to it dynamically
  # The include.path directive in git settings below references this mutable file

  assertions = [
    {
      assertion = agent.enable && pkgs.stdenv.hostPlatform.isLinux -> osConfig.programs._1password-gui.enable;
      message = "nix-config.ssh.onePasswordAgent needs programs._1password-gui (nixos/desktop/1password): it runs the agent and ships op-ssh-sign.";
    }
  ];

  xdg.configFile."git/allowed_signers".text = lib.concatMapStrings (line: line + "\n") osConfig.nix-config.git.allowedSigners;
  # basic configuration of git, please change to your own
  programs.git = {
    enable = true;
    lfs.enable = true;

    signing = {
      format = "ssh";
      signByDefault = true;
      # 1Password's signer; on darwin only the app bundle ships it.
      signer = lib.mkIf agent.enable (
        if pkgs.stdenv.hostPlatform.isDarwin
        then "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
        else lib.getExe' osConfig.programs._1password-gui.package "op-ssh-sign"
      );
    };
    settings = {
      user = {
        name = osConfig.user-full-name;
        inherit (osConfig) email;
        signingkey = osConfig.nix-config.git.signingKey;
      };
      init = {
        defaultBranch = "main";
      };
      # Include mutable theme override file AFTER catppuccin sets defaults
      # This allows theme-toggle to override delta theme at runtime
      include = {
        path = "~/.config/git/theme-override";
      };
      gpg.ssh.allowedSignersFile = "~/.config/git/allowed_signers";
      merge = {
        conflictstyle = "diff3";
      };

      # Enhanced workflow configuration
      branch = {
        autosetupmerge = "true";
        autosetuprebase = "always";
      };

      push = {
        default = "current";
        autoSetupRemote = true;
      };

      pull = {
        rebase = true;
      };

      rebase = {
        autoStash = true;
        autoSquash = true;
      };

      # Better diff algorithms
      diff = {
        algorithm = "patience";
        colorMoved = "default";
      };

      # Better blame
      blame = {
        coloring = "repeatedLines";
      };

      color = {
        diff-highlight = {
          oldNormal = "red bold";
          oldHighlight = "red bold 52";
          newNormal = "green bold";
          newHighlight = "green bold 22";
        };
        diff = {
          meta = "11";
          frag = "magenta bold";
          func = "146 bold";
          commit = "yellow bold";
          old = "red bold";
          new = "green bold";
          whitespace = "red reverse";
        };
      };
      url = {
        "git@github.com:" = {
          pushInsteadOf = "https://github.com";
        };
      };
    };
    ignores = [
      "**/.direnv"
      "**/.devenv"
      "**/.venv"
      ".icon"
      "**/CLAUDE.local.md"
    ];
  };

  programs.delta = {
    enable = true;
    options = {
      line-numbers = true;
      side-by-side = false;
      navigate = true;
      # Theme colors set dynamically by theme-toggle via ~/.config/git/theme-override
    };
  };
}

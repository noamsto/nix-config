{
  lib,
  osConfig,
  ...
}: let
  isServer = osConfig.machine.type == "server";
in {
  imports = [
    ./foot
    ./fish # Migrating from zsh to fish
    ./zsh # Keep temporarily during migration
    ./tmux
    ./process_compose

    ./tui.nix
  ];
  programs = {
    yazi = {
      enable = true;
      enableZshIntegration = true;
    };
    btop = {
      enable = true;
      settings = {
        vim_keys = true;
      };
    };

    starship = {
      enable = true;
      settings = lib.mkMerge [
        {
          add_newline = false;
        }
        (lib.mkIf
          isServer
          {
            format = lib.concatStrings [
              "$username"
              "$hostname"
              "$directory"
              "$git_branch"
              "$git_state"
              "$git_status"
              "$cmd_duration"
              "$line_break"
              "$python"
              "$character"
            ];
          })
      ];
    };

    bat.enable = true;
  };
}

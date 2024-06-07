{
  lib,
  pkgs,
  ...
}: {
  # starship - an customizable prompt for any shell
  programs.starship = let
    flavour = "mocha"; # One of `latte`, `frappe`, `macchiato`, or `mocha`
  in {
    enable = true;
    # custom settings
    settings =
      {
        add_newline = false;
        aws.disabled = true;
        gcloud.disabled = true;
        format = lib.concatStrings [
          "$username"
          "$memory_usage"
          "$hostname"
          "$directory"
          "$git_branch"
          "$git_commit"
          "$git_state"
          "$git_status"
          "$package"
          "$nix_shell"
          "$env_var"
          "$line_break"
          "$cmd_duration"
          "$jobs"
          "$time"
          "$character"
        ];

        palette = "catppuccin_${flavour}";
      }
      // builtins.fromTOML (builtins.readFile
        (pkgs.fetchFromGitHub
          {
            owner = "catppuccin";
            repo = "starship";
            rev = "5629d23"; # Replace with the latest commit hash
            sha256 = "sha256-nsRuxQFKbQkyEI4TXgvAjcroVdG+heKX5Pauq/4Ota0=";
          }
          + /palettes/${flavour}.toml));
  };
}

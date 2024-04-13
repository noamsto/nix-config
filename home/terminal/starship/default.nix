{
  config,
  pkgs,
  ...
}: {
  # starship - an customizable prompt for any shell
  programs.starship = let
    flavour = "frappe"; # One of `latte`, `frappe`, `macchiato`, or `mocha`
  in {
    enable = true;
    # custom settings
    settings =
      {
        add_newline = false;
        aws.disabled = true;
        gcloud.disabled = true;
        format = "$all"; # Remove this line to disable the default prompt format

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

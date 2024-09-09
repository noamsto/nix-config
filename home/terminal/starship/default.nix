{pkgs, ...}: {
  # starship - an customizable prompt for any shell
  programs.starship = let
    flavour = "mocha";
  in {
    enable = true;
    # custom settings
    settings =
      {
        add_newline = false;
        aws.disabled = true;
        gcloud.disabled = true;
        format = "$all"; # Remove this line to disable the default prompt format
        git_status = {
          deleted = "󱎘";
        };

        palette = "catppuccin_${flavour}";
      }
      // builtins.fromTOML (builtins.readFile
        (pkgs.fetchFromGitHub
          {
            owner = "catppuccin";
            repo = "starship";
            rev = "3c4749512e7d552adf48e75e5182a271392ab176"; # Replace with the latest commit hash
            sha256 = "sha256-t/Hmd2dzBn0AbLUlbL8CBt19/we8spY5nMP0Z+VPMXA=";
          }
          + /themes/${flavour}.toml));
  };
}

{...}: {
  # starship - an customizable prompt for any shell
  programs.starship = {
    enable = true;
    # custom settings
    settings = {
      add_newline = false;
      aws.disabled = true;
      gcloud.disabled = true;
      format = "$all"; # Remove this line to disable the default prompt format
      git_status = {
        deleted = "󱎘";
      };
    };
  };
}

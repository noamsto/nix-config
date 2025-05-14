{...}: {
  # Starship - a customizable prompt for any shell
  programs.starship = {
    enable = true;
    # custom settings
    settings = {
      add_newline = false;
    };
  };
}

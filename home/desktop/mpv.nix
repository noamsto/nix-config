{pkgs, ...}: {
  programs.mpv = {
    enable = true;
    scripts = with pkgs.mpvScripts; [
      uosc # Modern feature-rich OSC
      thumbfast # Thumbnails for uosc seekbar
    ];
    config = {
      # uosc recommended settings
      osc = false; # Disable default OSC (uosc replaces it)
      osd-bar = false; # uosc has its own progress bar
      border = false; # Remove window border for cleaner look
    };
  };
}

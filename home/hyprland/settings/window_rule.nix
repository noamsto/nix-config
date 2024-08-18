{...}: {
  wayland.windowManager.hyprland.settings = {
    windowrulev2 = [
      "suppressevent maximize, class:.*" # You'll probably like this.

      # make Firefox PiP window floating and sticky
      # "float, title:^(Picture-in-Picture)$"
      # "pin, title:^(Picture-in-Picture)$"

      # start spotify in ws9
      # "workspace 9 silent, title:^(Spotify( Premium)?)$"

      # fix xwayland apps
      # "rounding 0, xwayland:1"
    ];
  };
}

{...}: {
  # Minimal hyprlock configuration - catppuccin theming handled by theme module
  programs.hyprlock = {
    enable = true;
    settings = {
      # Authentication
      auth.fingerprint.enabled = true;

      # Essential stability settings
      general = {
        immediate_render = true; # Prevents crashes
        fail_timeout = 2000;
      };

      # Simple screenshot background
      background = [
        {
          monitor = "";
          path = "screenshot";
          blur_passes = 2;
          blur_size = 7;
        }
      ];

      # Simple labels - colors handled by catppuccin
      label = [
        {
          monitor = "";
          text = "Hi $USER";
          font_size = 24;
          position = "0, 80";
          halign = "center";
          valign = "center";
        }
        {
          monitor = "";
          text = "$TIME";
          font_size = 18;
          position = "0, 40";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };
}

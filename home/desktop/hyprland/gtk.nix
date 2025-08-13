{lib, ...}: {
  # Prevents home-manager from managing GTK4 CSS file, allowing manual customization
  xdg.configFile."gtk-4.0/gtk.css".enable = lib.mkForce false;

  # Enable sound theme support for system sounds
  gtk = {
    enable = true;
    gtk3.extraConfig = {
      gtk-sound-theme-name = "freedesktop";
      gtk-enable-event-sounds = 1;
      gtk-enable-input-feedback-sounds = 1;
    };
  };
}

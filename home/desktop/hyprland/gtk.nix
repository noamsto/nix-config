{lib, ...}: {
  # Prevents home-manager from managing GTK CSS files, allowing theme-toggle to modify them
  xdg.configFile."gtk-3.0/gtk.css".enable = lib.mkForce false;
  xdg.configFile."gtk-4.0/gtk.css".enable = lib.mkForce false;

  gtk = {
    enable = true;
    gtk3.extraConfig = {
      gtk-sound-theme-name = "freedesktop";
      gtk-enable-event-sounds = 1;
      gtk-enable-input-feedback-sounds = 1;
    };
  };
}

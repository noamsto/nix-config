{lib, ...}: {
  # Prevents home-manager from managing GTK4 CSS file, allowing manual customization
  xdg.configFile."gtk-4.0/gtk.css".enable = lib.mkForce false;
}

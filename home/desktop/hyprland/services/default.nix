{...}: {
  imports = [
    ./kanshi
  ];

  # Hyprland polkit authentication agent
  services.hyprpolkitagent.enable = true;
}

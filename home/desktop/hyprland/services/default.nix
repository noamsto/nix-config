{pkgs, ...}: {
  imports = [
    ./kanshi
  ];

  # Hyprland polkit authentication agent
  services.hyprpolkitagent.enable = true;

  # Hyprsunset blue light filter for Hyprland
  services.hyprsunset = {
    enable = true;
    # transitions = {
    #   sunset = {
    #     calendar = "sunset";
    #     requests = [["temperature" "3000"]];
    #   };
    #   sunrise = {
    #     calendar = "sunrise";
    #     requests = [["identity"]];
    #   };
    # };
  };
}

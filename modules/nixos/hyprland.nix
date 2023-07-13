{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.hyprland.nixosModules.default
  ];
  services.xserver = {
    enable = true;
    # videosDrivers = ["nvidia"];
    displayManager.gdm = {
      enable = true;
      wayland = true;
    };
  };
  programs.hyprland.enable = true;
}

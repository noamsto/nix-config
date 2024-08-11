{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
lib.mkIf (config.desktop.mode == "hyprland") {
  programs.hyprland = {
    enable = true;
    package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
  };

  services.blueman.enable = true;

  environment.systemPackages = with pkgs; [
    pavucontrol
  ];
}

{
  inputs,
  pkgs,
  lib,
  config,
  ...
}: let
  isHypr = config.desktop.mode == "hyprland";
in {
  imports = [./gnome-services.nix];
  config = lib.mkIf isHypr {
    programs.hyprland = {
      enable = true;
      package = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}.hyprland;
    };

    services.blueman.enable = true;

    # smooth backlight control
    hardware.brillo.enable = true;

    environment.systemPackages = with pkgs; [
      pavucontrol
    ];
  };
}

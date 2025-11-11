{
  inputs,
  pkgs,
  lib,
  ...
}: {
  imports = [
    inputs.vicinae.homeManagerModules.default # enable Home Manager
  ];
  home.packages = with pkgs; [
    libqalculate
  ];
  services.vicinae = {
    enable = true;
    autoStart = true;
    settings = {
      faviconService = "twenty"; # twenty | google | none
      font = {
        name = "Inter Nerd Font";
        size = 12;
      };
      popToRootOnClose = false;
      closeOnFocusLost = true;
      rootSearch.searchFiles = false;
      theme = {
        name = "catppuccin-mocha";
        iconTheme = "Papirus-Dark";
      };
      window = {
        csd = true; # Enable client-side decorations for rounded corners
        opacity = 0.95;
        rounding = 10;
      };
    };
  };

  # Workaround for layer-shell protocol error (https://github.com/vicinaehq/vicinae/issues/672)
  # This fixes crashes after Hyprland updates until the fix is in stable Hyprland
  systemd.user.services.vicinae.Service.Environment = lib.mkForce ["USE_LAYER_SHELL=0"];
}

{pkgs, ...}: {
  boot.loader = {
    systemd-boot = {
      enable = true;
      configurationLimit = 12;
      consoleMode = "auto";
    };
    efi.canTouchEfiVariables = true;
  };

  boot.plymouth = {
    enable = true;
    font = "${pkgs.jetbrains-mono}/share/fonts/truetype/JetBrainsMono-Regular.ttf";
    themePackages = [pkgs.catppuccin-plymouth];
    theme = "catppuccin-macchiato";
  };
}

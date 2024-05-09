{pkgs, ...}: {
  imports = [
    ./sddm
  ];
  environment.systemPackages = with pkgs; [
    kdePackages.yakuake
    kdePackages.kcalc
    wayland-utils
  ];
  programs.kdeconnect.enable = true;
  services.desktopManager.plasma6.enable = true;
}

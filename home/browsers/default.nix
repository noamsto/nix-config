{pkgs, ...}: {
  imports = [./firefox];
  home.packages = with pkgs; [
    google-chrome
    floorp
  ];
}

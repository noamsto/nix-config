{pkgs, ...}: {
  # K9s
  programs.k9s = {
    enable = true;
    settings.k9s = {
      ui = {
        enableMouse = true;
      };
    };
  };
  home.packages = with pkgs; [
    kubectl
  ];
}

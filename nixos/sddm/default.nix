{pkgs, ...}: {
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
    # theme = "${import ./sddm-theme.nix {inherit pkgs;}}";
  };
}

{pkgs, ...}: let
  desktop-packages = with pkgs; [
    # Note taking
    obsidian
  ];
in {
  environment.systemPackages = with pkgs;
    [
      vim
      wget
      git
      curl
      firefox
      dmidecode
      fastfetch

      # Nix/NixOS package version diff tool
      nvd

      # python
      (python312.withPackages (ps:
        with ps;
          [
            ipython
            catppuccin
          ]
          ++ catppuccin.optional-dependencies.pygments))
    ]
    #TODO: Add if desktop
    ++ desktop-packages;
}

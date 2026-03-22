{inputs, ...}: {
  imports = [inputs.nix-flatpak.homeManagerModules.nix-flatpak];

  services.flatpak = {
    packages = [
      "com.bambulab.BambuStudio"
    ];

    overrides."com.bambulab.BambuStudio".Context.filesystems = [
      "xdg-config/BambuStudio"
    ];
  };
}

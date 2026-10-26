{
  inputs,
  self,
  ...
}: {config, ...}: {
  imports = [inputs.home-manager.darwinModules.home-manager];
  # System-integrated Home Manager. osConfig is auto-injected as this darwin
  # config, so the shared home/ modules read desktop.mode/profile/username
  # exactly as on NixOS.
  home-manager = {
    backupFileExtension = "bak";
    useUserPackages = true;
    useGlobalPkgs = true;
    users.${config.username}.imports = [self.homeModules.default];
  };
}

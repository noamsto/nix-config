{
  inputs,
  self,
  ...
}: {config, ...}: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];
  home-manager = {
    backupFileExtension = "bak";
    useUserPackages = true;
    useGlobalPkgs = true;
    # Home manager config (configures programs like firefox, zsh, eww, etc)
    users.${config.username}.imports = [self.homeModules.default];
  };
}

{
  config,
  inputs,
  ...
}: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];
  home-manager = {
    backupFileExtension = "bak";
    useUserPackages = true;
    useGlobalPkgs = true;
    extraSpecialArgs = {inherit inputs;};
    # Home manager config (configures programs like firefox, zsh, eww, etc)
    users.${config.username} = ./. + "/${config.username}.nix";
  };
}

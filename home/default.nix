{
  config,
  inputs,
  ...
}: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.nur.modules.nixos.default
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

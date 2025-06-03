{
  config,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.matugen.nixosModules.default
  ];

  programs.matugen = {
    enable = true;
    package = pkgs.matugen;
  };
}

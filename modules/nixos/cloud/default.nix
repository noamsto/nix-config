{
  config,
  pkgs,
  inputs,
  pkgs-stable,
  ...
}: let
  stable = inputs.nixpkgs-stable;
in {
  environment.systemPackages = with pkgs; [
    pkgs-stable.azure-cli
    awscli2
    ssm-session-manager-plugin
  ];
}

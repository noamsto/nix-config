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
    azure-cli
    awscli2
    ssm-session-manager-plugin
  ];
}

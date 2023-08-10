{
  config,
  pkgs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    azure-cli
    awscli2
    ssm-session-manager-plugin
  ];
}

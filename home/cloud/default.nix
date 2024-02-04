{pkgs, ...}: {
  home.packages = with pkgs; [
    # azure-cli
    awscli2
    ssm-session-manager-plugin
  ];
}

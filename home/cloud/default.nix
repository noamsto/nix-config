{pkgs, ...}: {
  home.packages = with pkgs; [
    awscli2
    ssm-session-manager-plugin
  ];
}

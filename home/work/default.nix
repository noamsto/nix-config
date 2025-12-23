{pkgs, ...}: {
  home.packages = with pkgs; [
    slack

    stable.awscli2
    stable.aws-sam-cli
    ssm-session-manager-plugin

    # chromium moved to programs.chromium in home/desktop/default.nix for commandLineArgs
    crush
    stable.postman # Uses stable for API testing reliability
    ngrok
    dbeaver-bin
  ];
}

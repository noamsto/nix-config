{
  config,
  pkgs,
  ...
}: {
  imports = [./code-shell.nix];
  programs.vscode = {
    enable = true;
    package = pkgs.vscode.fhs;
  };
}

{
  config,
  pkgs,
  ...
}: {
  programs.vscode = {
    enable = true;
    extensions = with pkgs.vscode-extensions; [
      catppuccin.catppuccin-vsc
      vscodevim.vim
      yzhang.markdown-all-in-one
    ];
    userSettings = {
      "workbench.colorTheme" = "Catppuccin Mocha";
    };
  };
}

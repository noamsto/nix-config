{
  config,
  pkgs,
  ...
}: {
  programs.vscode = {
    enable = true;
    extensions = with pkgs.vscode-extensions; [
      Catppuccin.catppuccin-vsc
      vscodevim.vim
      yzhang.markdown-all-in-one
    ];
    userSettings = {
      "catppuccin.accentColor" = "frappe";
    };
  };
}

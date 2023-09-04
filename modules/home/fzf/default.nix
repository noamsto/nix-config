{
  config,
  pkgs,
  ...
}: {
  programs.fzf = {
    enable = true;
    fileWidgetOptions = [
      "--preview '${pkgs.bat}/bin/bat -n --color=always {}'"
      "--bind 'ctrl-/:change-preview-window(down|hidden|)'"
    ];
  };
}

{
  config,
  pkgs,
  ...
}: {
  programs.fzf = {
    enable = true;
    fileWidgetOptions = [
      "--preview 'bat -n --color=always {}'"
      "--bind 'ctrl-/:change-preview-window(down|hidden|)'"
    ];
  };
}

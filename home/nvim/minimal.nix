# Minimal neovim for servers (no LazyVim symlink or heavy LSP packages)
_: {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };
}

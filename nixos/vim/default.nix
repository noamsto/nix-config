{pkgs, ...}: {
  environment.variables = {
    EDITOR = "vim";
    BROWSER = "floorp";
    TERMINAL = "alacritty";
  };

  environment.systemPackages = with pkgs; [
    (
      (vim_configurable.override {}).customize {
        name = "vim";
        # Install plugins for example for syntax highlighting of nix files
        vimrcConfig.packages.myplugins = with pkgs.vimPlugins; {
          start = [vim-nix vim-lastplace vim-tmux-navigator];
          opt = [];
        };
        vimrcConfig.customRC = ''
                 " your custom vimrc
                 set nocompatible
                 set backspace=indent,eol,start
                 " Turn on syntax highlighting by default
                 syntax on

                 set background=dark
                 set mouse=a
                 set ttymouse=xterm2
                 filetype indent on


          " line numbers toggle
                 set number relativenumber
                 augroup numbertoggle
                   autocmd!
                   autocmd BufEnter,FocusGained,InsertLeave * set relativenumber
                   autocmd BufLeave,FocusLost,InsertEnter   * set norelativenumber
                 augroup END

          " for trailing spaces
                 highlight ExtraWhitespace ctermbg=darkgreen guibg=darkgreen
                 match ExtraWhitespace /\s\+$/

          " for column 100
          set colorcolumn=100
          highlight ColorColumn ctermbg=103 guibg=lightgrey

        '';
      }
    )
  ];
}

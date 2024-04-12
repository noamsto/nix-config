{
  pkgs,
  config,
  ...
}: {
  xdg.configFile = {
    "nvim-minimal".source = "/home/noams/nix-config/home/nvim/astronvim_minimal";
  };

  home.shellAliases = {
    nvim = "NVIM_APPNAME=nvim-minimal nvim";
  };
  programs.neovim = {
    package = pkgs.neovim-unwrapped;
    enable = true;
    defaultEditor = true;

    vimAlias = true;
    vimdiffAlias = true;

    withPython3 = true;
    withNodeJs = true;

    extraPackages = with pkgs; [
      # Astronvim requirements
      luarocks-nix

      # lua
      lua
      luajit
      stylua
      lua-language-server
      selene

      # Markdown
      marksman # Markdown
      icu.dev
      glow # markdown previewer

      # nix
      nil
      statix # Lints and suggestions for the nix programming language
      deadnix # Find and remove unused code in .nix source files
      alejandra # Nix Code Formatter

      # formatters
      # nodePackages.prettier # common code formatter
      prettierd # common code formatter

      # Others
      taplo # TOML language server / formatter / validator
      yaml-language-server
      sqlfluff # SQL linter
      actionlint # GitHub Actions linter
      proselint # English prose linter

      #-- bash
      nodePackages.bash-language-server
      shellcheck
      shfmt

      #-- json
      vscode-langservers-extracted

      #-- Misc
      tree-sitter # common language parser/highlighter

      # #-- Optional Requirements:
      gdu # disk usage analyzer, required by AstroNvim
      ripgrep # fast search tool, required by AstroNvim's '<leader>fw'(<leader> is space key)

      fd # Find files

      cmake
      cmake-language-server
      checkmake
      gnumake
      gcc # c/c++ compiler, required by nvim-treesitter!
      llvmPackages.clang-unwrapped # c/c++ tools with clang-tools such as clangd
      gdb
      lldb

      curl
      wget
      go
    ];
  };
}

{
  pkgs,
  config,
  astronvim,
  ...
}: {
  xdg.configFile = {
    "nvim".source = astronvim;
    "astronvim/lua/user".source = config.lib.file.mkOutOfStoreSymlink "/home/noams/nix-config/home/nvim/astronvim_user";
    # "astronvim/lua/user".source = ./astronvim_user;   # Enable after finishing configuring nvim
  };
  programs.neovim = {
    package = pkgs.neovim-unwrapped;
    enable = true;
    defaultEditor = true;

    vimAlias = true;
    vimdiffAlias = true;

    withPython3 = true;
    withNodeJs = true;
    extraPython3Packages = ps: [
      ps.debugpy
    ];
    extraPackages = with pkgs; [
      # Lua
      lua-language-server

      # General purpose Language Server (for sevices like black, mypy and others)
      efm-langserver

      # DB
      sqlite
      postgresql

      # Graphql
      nodePackages.graphql-language-service-cli

      #-- json
      nodePackages.vscode-langservers-extracted

      # Containers
      # nodePackages.compose-language-service
      nodePackages.dockerfile-language-server-nodejs
      terraform
      terraform-ls
      hadolint # dockerfile linter

      # protobuf
      buf-language-server
      buf

      #-- python
      nodePackages.pyright # python language server
      ruff-lsp

      #-- nix
      nil
      statix # Lints and suggestions for the nix programming language
      deadnix # Find and remove unused code in .nix source files
      alejandra # Nix Code Formatter

      #-- lua
      stylua

      #-- bash
      nodePackages.bash-language-server
      shellcheck
      shfmt

      #-- Others
      taplo # TOML language server / formatter / validator
      nodePackages.yaml-language-server
      sqlfluff # SQL linter
      actionlint # GitHub Actions linter
      proselint # English prose linter

      #-- Misc
      tree-sitter # common language parser/highlighter
      nodePackages.prettier # common code formatter
      marksman # language server for markdown
      glow # markdown previewer

      #-- Optional Requirements:
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

      # Wayland clipboard
      wl-clipboard
    ];

    # For development
    # extraLuaPackages = luaPkgs: with luaPkgs; [plenary-nvim luv];
  };
}

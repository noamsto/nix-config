{
  pkgs,
  config,
  lib,
  ...
}: {
  imports = [
    ./nixCats
  ];

  xdg.configFile = {
    "nvim".source = config.lib.file.mkOutOfStoreSymlink "/home/noams/nix-config/home/nvim/astronvim_v4";
    "lvim".source = config.lib.file.mkOutOfStoreSymlink "/home/noams/nix-config/home/nvim/lazyVim";
  };
  home.shellAliases = {
    "lvim" = "NVIM_APPNAME=lvim nvim";
  };

  programs.neovim = {
    package = pkgs.neovim-unwrapped;

    extraWrapperArgs = [
      "--suffix"
      "LIBRARY_PATH"
      ":"
      "''${lib.makeLibraryPath [pkgs.stdenv.cc.cc pkgs.zlib]}"
      "--suffix"
      "PKG_CONFIG_PATH"
      ":"
      "''${lib.makeSearchPathOutput "dev" "lib/pkgconfig" [pkgs.stdenv.cc.cc pkgs.zlib]}"
      "--set"
      "LIBGIT2_PATH"
      "${pkgs.libgit2.lib}/lib/libgit2.so"
      "--set"
      "SQLITE3_PATH"
      "${pkgs.sqlite.out}/lib/libsqlite3.so"
      "--suffix"
      "PATH"
      ":"
      (lib.makeBinPath [pkgs.nodejs])
    ];
    enable = true;
    defaultEditor = true;

    vimAlias = true;
    vimdiffAlias = true;

    withPython3 = true;
    withNodeJs = true;
    extraPython3Packages = ps: [
      ps.debugpy
      ps.python-lsp-server
      ps.pylsp-mypy
      ps.ruff
    ];

    extraPackages = with pkgs; [
      # Astronvim requirements
      lua5_1
      luajit
      lua51Packages.luarocks
      luajitPackages.lua-utils-nvim
      cargo

      # DB
      sqlite
      postgresql

      # lua
      stylua
      lua-language-server
      selene

      # python
      pyright # python language server

      # Markdown
      marksman # Markdown
      icu.dev
      glow # markdown previewer

      # nix
      nil
      nixd
      statix # Lints and suggestions for the nix programming language
      deadnix # Find and remove unused code in .nix source files
      alejandra # Nix Code Formatter

      # formatters
      # nodePackages.prettier # common code formatter
      prettierd # common code formatter
      lemminx

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

      # Containers
      docker-compose-language-service
      dockerfile-language-server-nodejs
      terraform
      terraform-ls
      hadolint # dockerfile linter

      # # protobuf
      # buf-language-server
      # buf

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

      yarn

      #typescript
      eslint
      typescript
    ];

    # For development
    # extraLuaPackages = luaPkgs: with luaPkgs; [plenary-nvim luv];
  };
}

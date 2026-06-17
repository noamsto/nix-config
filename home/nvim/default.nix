{
  pkgs,
  config,
  lib,
  ...
}: {
  xdg.configFile = let
    lazyVimDir = "${config.home.homeDirectory}/nix-config/home/nvim/lazyVim";
  in {
    "nvim/lua".source = config.lib.file.mkOutOfStoreSymlink "${lazyVimDir}/lua";
    "nvim/lazyvim.json".source = config.lib.file.mkOutOfStoreSymlink "${lazyVimDir}/lazyvim.json";
    "nvim/lazy-lock.json".source = config.lib.file.mkOutOfStoreSymlink "${lazyVimDir}/lazy-lock.json";
    "nvim/.neoconf.json".source = config.lib.file.mkOutOfStoreSymlink "${lazyVimDir}/.neoconf.json";
    "nvim/stylua.toml".source = config.lib.file.mkOutOfStoreSymlink "${lazyVimDir}/stylua.toml";
    "harper-ls/dictionary.txt".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/nvim/harper-dictionary.txt";
  };

  programs.neovim = {
    initLua = ''
      require("config.lazy")
    '';
    withRuby = false;
    extraWrapperArgs = [
      # Skip the DSR/'background' terminal probe that warns (E1568) on every
      # startup under tmux — the 100ms wait is a false-positive timeout during
      # heavy plugin load. Must be set before nvim starts; ':set nottyfast' in
      # config is too late. Added in nvim 0.12.3 (neovim/neovim#38699).
      "--set"
      "NVIM_NOTTYFAST"
      "1"
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

    extraPackages = with pkgs;
      [
        #Basic
        lua5_1
        luajit
        lua51Packages.luarocks
        luajitPackages.lua-utils-nvim
        cargo
        go
        zig

        # DB
        sqlite

        #-- Misc
        tree-sitter # common language parser/highlighter

        # Compilation
        cmake
        cmake-language-server
        checkmake
        gnumake
        gcc # c/c++ compiler, required by nvim-treesitter!
        llvmPackages.clang-unwrapped # c/c++ tools with clang-tools such as clangd
        gdb
        lldb

        marksman # Markdown
        hadolint
        uv

        # === ESSENTIAL LSP SERVERS (Better via Nix than Mason) ===
        rust-analyzer # Rust
        gopls # Go
        golangci-lint-langserver # Go linting LSP
        typescript-language-server # TypeScript/JavaScript
        yaml-language-server # YAML
        taplo # TOML
        bash-language-server
        statix
        nil # Nix LSP (nil_ls)
        alejandra # Nix formatter

        # === KEY FORMATTERS ===
        rustfmt # Rust formatting
        gotools # Go imports and formatting
        prettier # Web formatting
        shfmt

        mermaid-cli

        # for images
        imagemagick

        #pdf preview
        ghostscript

        # latex render
        tectonic
      ]
      # inotify-tools is Linux-only (inotify is a Linux kernel API).
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [pkgs.inotify-tools];
  };
}

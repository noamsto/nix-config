{
  pkgs,
  config,
  lib,
  ...
}: {
  xdg.configFile = {
    "nvim".source = config.lib.file.mkOutOfStoreSymlink "/home/noams/nix-config/home/nvim/lazyVim";
  };

  programs.neovim = {
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

    extraPackages = with pkgs; [
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
      harper # Grammar checker for developers
      hadolint
      uv

      # === ESSENTIAL LSP SERVERS (Better via Nix than Mason) ===
      rust-analyzer # Rust
      gopls # Go
      nodePackages.typescript-language-server # TypeScript/JavaScript
      yaml-language-server # YAML
      taplo # TOML
      bash-language-server

      # === KEY FORMATTERS ===
      rustfmt # Rust formatting
      gotools # Go imports and formatting
      nodePackages.prettier # Web formatting
      shfmt

      inotify-tools

      mermaid-cli

      # for images
      imagemagick

      #pdf preview
      ghostscript

      # latex render
      tectonic
    ];
  };
}

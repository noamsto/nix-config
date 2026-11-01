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
      "--set"
      "SQLITE3_PATH"
      "${pkgs.sqlite.out}/lib/libsqlite3.so"
    ];
    enable = true;
    defaultEditor = true;

    vimAlias = true;
    vimdiffAlias = true;

    withPython3 = false;
    withNodeJs = false;

    extraPackages = with pkgs;
      [
        go
        gcc # required by nvim-treesitter
        gnumake
        tree-sitter
        uv

        # LSP servers (Mason is disabled; Nix is the only source)
        marksman
        hadolint
        pyrefly
        vtsls
        lua-language-server
        gopls
        golangci-lint-langserver
        yaml-language-server
        taplo
        bash-language-server
        vscode-langservers-extracted # jsonls, eslint
        dockerfile-language-server
        docker-compose-language-service
        nil
        harper # harper-ls, commit messages

        # Linters and formatters
        ruff
        stylua
        gofumpt
        golangci-lint
        gotools
        shellcheck
        shfmt
        statix
        alejandra
        prettier
        markdown-toc

        mermaid-cli
        imagemagick # images
        ghostscript # pdf preview
        tectonic # latex render
      ]
      # inotify-tools is Linux-only (inotify is a Linux kernel API).
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [pkgs.inotify-tools];
  };
}

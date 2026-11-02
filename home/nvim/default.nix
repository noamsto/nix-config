{inputs, ...}: {
  pkgs,
  config,
  lib,
  ...
}: let
  vp = pkgs.vimPlugins;

  buildPlugin = pname: src:
    pkgs.vimUtils.buildVimPlugin {
      inherit pname src;
      version = src.shortRev or src.dirtyShortRev or "unstable";
    };

  # Keys are the directory name lazy.nvim derives from the spec: the last
  # component of the spec URL, or the spec's `name`.
  plugins = {
    "LazyVim" = vp.LazyVim;
    "SchemaStore.nvim" = vp.SchemaStore-nvim;
    "auto-dark-mode.nvim" = vp.auto-dark-mode-nvim;
    "backend-tmux" = buildPlugin "backend-tmux" inputs.smart-splits-backend-tmux;
    "better-escape.nvim" = vp.better-escape-nvim;
    "blink.cmp" = vp.blink-cmp;
    "bufferline.nvim" = vp.bufferline-nvim;
    catppuccin = vp.catppuccin-nvim;
    "conform.nvim" = vp.conform-nvim;
    "flash.nvim" = vp.flash-nvim;
    inherit (vp) friendly-snippets;
    "gitsigns.nvim" = vp.gitsigns-nvim;
    "grug-far.nvim" = vp.grug-far-nvim;
    "lazy.nvim" = vp.lazy-nvim;
    "lazydev.nvim" = vp.lazydev-nvim;
    "lualine.nvim" = vp.lualine-nvim;
    "markview.nvim" = vp.markview-nvim;
    "mini.ai" = vp.mini-ai;
    "mini.hipatterns" = vp.mini-hipatterns;
    "mini.icons" = vp.mini-icons;
    "mini.pairs" = vp.mini-pairs;
    "noice.nvim" = vp.noice-nvim;
    "nui.nvim" = vp.nui-nvim;
    inherit (vp) nvim-lint;
    inherit (vp) nvim-lspconfig;
    inherit (vp) nvim-spider;
    inherit (vp) nvim-treesitter;
    inherit (vp) nvim-treesitter-context;
    inherit (vp) nvim-treesitter-textobjects;
    inherit (vp) nvim-ts-autotag;
    "persistence.nvim" = vp.persistence-nvim;
    "plenary.nvim" = vp.plenary-nvim;
    "resolved.nvim" = buildPlugin "resolved.nvim" inputs.resolved-nvim;
    "smart-splits.nvim" = vp.smart-splits-nvim;
    "snacks.nvim" = vp.snacks-nvim;
    "todo-comments.nvim" = vp.todo-comments-nvim;
    "trouble.nvim" = vp.trouble-nvim;
    "ts-comments.nvim" = vp.ts-comments-nvim;
    "venv-selector.nvim" = vp.venv-selector-nvim;
    "which-key.nvim" = vp.which-key-nvim;
  };

  pluginDir = pkgs.linkFarm "lazy-plugins" plugins;

  # LazyVim's resolved ensure_installed; its dot extra adds fish and hyprlang
  # when ~/.config/fish or ~/.config/hypr exists.
  parsers = vp.nvim-treesitter.withPlugins (p:
    with p; [
      bash
      c
      diff
      dockerfile
      fish
      git_config
      gomod
      go
      gosum
      gowork
      html
      hyprlang
      javascript
      jsdoc
      json5
      json
      luadoc
      luap
      lua
      markdown_inline
      markdown
      ninja
      nix
      printf
      python
      query
      regex
      rst
      toml
      tsx
      typescript
      vimdoc
      vim
      xml
      yaml
    ]);

  # Query plugins' `requires` (e.g. `ecma`, `jsx` for `tsx`) are reachable only
  # through their `passthru.dependencies`.
  parserDir = pkgs.symlinkJoin {
    name = "nvim-treesitter-parsers";
    paths = map (x: x.drv) (builtins.genericClosure {
      startSet =
        map (d: {
          key = d.outPath;
          drv = d;
        })
        parsers.dependencies;
      operator = x:
        map (d: {
          key = d.outPath;
          drv = d;
        }) (x.drv.dependencies or []);
    });
  };
in {
  xdg.configFile = {
    "nvim/lua".source = ./lazyVim/lua;
    "nvim/lazyvim.json".source = ./lazyVim/lazyvim.json;
    "nvim/.neoconf.json".source = ./lazyVim/.neoconf.json;
    "nvim/stylua.toml".source = ./lazyVim/stylua.toml;
    # harper-ls writes added words to this file, so it stays a live link into the repo.
    "harper-ls/dictionary.txt".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/nvim/harper-dictionary.txt";
  };

  programs.neovim = {
    initLua = ''
      vim.g.lazy_nix = { plugins = "${pluginDir}", parsers = "${parserDir}" }
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

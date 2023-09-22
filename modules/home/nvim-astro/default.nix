{
  pkgs,
  config,
  astronvim,
  ...
}: let
  ruff-lsp = pkgs.python311Packages.buildPythonPackage rec {
    name = "ruff-lsp";
    version = "v0.0.36";
    format = "pyproject";
    src = pkgs.fetchFromGitHub {
      owner = "astral-sh";
      repo = name;
      rev = version;
      sha256 = "sha256-29LK/upjtgv9LIOn4bJMHkWXUJEkR0pR5fuyOYP9hAI=";
    };
    postPatch = ''
      # ruff binary is used directly, the ruff python package is not needed
      sed -i '/"ruff>=/d' pyproject.toml
    '';
    propagatedBuildInputs = with pkgs.python311Packages; [hatchling lsprotocol pygls typing-extensions pkgs.ruff];
    doCheck = true;
  };
in {
  xdg.configFile = {
    "nvim".source = astronvim;
    "astronvim/lua/user".source = ./astronvim_user;
  };
  programs.neovim = {
    enable = true;
    defaultEditor = true;

    vimAlias = true;
    vimdiffAlias = true;

    withPython3 = true;
    withNodeJs = true;
    extraPython3Packages = ps: [
      ps.debugpy
      ps.python-lsp-server
      ps.python-lsp-black
      ps.pylsp-mypy
    ];
    extraPackages = with pkgs; [
      lua-language-server
    ];
  };

  home.packages = with pkgs; [
    #-- c/c++
    cmake
    cmake-language-server
    gnumake
    checkmake
    gcc # c/c++ compiler, required by nvim-treesitter!
    llvmPackages.clang-unwrapped # c/c++ tools with clang-tools such as clangd
    gdb
    lldb

    #-- python
    nodePackages.pyright # python language server
    python311Packages.black # python formatter
    ruff-lsp

    #-- nix
    nil
    rnix-lsp
    # nixd
    statix # Lints and suggestions for the nix programming language
    deadnix # Find and remove unused code in .nix source files
    alejandra # Nix Code Formatter

    #-- lua
    stylua

    #-- bash
    nodePackages.bash-language-server
    shellcheck
    shfmt

    # #-- CloudNative
    nodePackages.dockerfile-language-server-nodejs
    terraform
    terraform-ls
    # hadolint # Dockerfile linter

    #-- Others
    taplo # TOML language server / formatter / validator
    nodePackages.yaml-language-server
    sqlfluff # SQL linter
    actionlint # GitHub Actions linter
    buf # protoc plugin for linting and formatting
    proselint # English prose linter

    #-- Misc
    tree-sitter # common language parser/highlighter
    nodePackages.prettier # common code formatter
    marksman # language server for markdown
    glow # markdown previewer

    #-- Optional Requirements:
    gdu # disk usage analyzer, required by AstroNvim
    ripgrep # fast search tool, required by AstroNvim's '<leader>fw'(<leader> is space key)
  ];
}

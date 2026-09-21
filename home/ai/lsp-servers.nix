# Shared language-server definitions for every agent harness (Claude Code,
# pi). Single source of truth, same shape as mcp-servers.nix.
{pkgs}: let
  wrap = name: runtimeInputs: text: pkgs.writeShellApplication {inherit name runtimeInputs text;};

  python = {
    ".py" = "python";
    ".pyi" = "python";
  };
in {
  ty = {
    package = wrap "ty-lsp" [pkgs.ty] ''exec ty server "$@"'';
    extensions = python;
  };

  # Lint-only: shares .py with ty, so a harness that picks one primary server
  # per file must not pick this one.
  ruff = {
    package = wrap "ruff-lsp" [pkgs.ruff] ''exec ruff server "$@"'';
    extensions = python;
    secondary = true;
  };

  # -remote=auto forwards to one shared gopls daemon, so its parse and
  # type-check cache of dependencies is paid once across sessions and workers.
  # gopls loads no view at all without `go` on PATH, and a harness started
  # outside a Go devshell has none. Appended, so a repo's own toolchain wins.
  gopls = {
    package = wrap "gopls-lsp" [pkgs.gopls] ''
      export PATH="$PATH:${pkgs.go}/bin"
      exec gopls -remote=auto "$@"
    '';
    extensions = {".go" = "go";};
  };

  typescript = {
    package = wrap "typescript-lsp" [pkgs.typescript-language-server] ''exec typescript-language-server --stdio "$@"'';
    extensions = {
      ".ts" = "typescript";
      ".tsx" = "typescriptreact";
      ".mts" = "typescript";
      ".cts" = "typescript";
      ".js" = "javascript";
      ".jsx" = "javascriptreact";
      ".mjs" = "javascript";
      ".cjs" = "javascript";
    };
  };

  nixd = {
    package = wrap "nixd-lsp" [pkgs.nixd] ''exec nixd "$@"'';
    extensions = {".nix" = "nix";};
  };

  bash = {
    package = wrap "bash-lsp" [pkgs.bash-language-server] ''exec bash-language-server start "$@"'';
    extensions = {
      ".sh" = "shellscript";
      ".bash" = "shellscript";
    };
  };

  lua = {
    package = wrap "lua-lsp" [pkgs.lua-language-server] ''exec lua-language-server "$@"'';
    extensions = {".lua" = "lua";};
  };

  yaml = {
    package = wrap "yaml-lsp" [pkgs.yaml-language-server] ''exec yaml-language-server --stdio "$@"'';
    extensions = {
      ".yaml" = "yaml";
      ".yml" = "yaml";
    };
  };
}

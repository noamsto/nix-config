{
  pkgs,
  lib,
  config,
  ...
}: let
  mcpServers = import ../mcp-servers.nix {
    inherit pkgs lib;
    inherit (config.home) username;
  };

  mcpAliases = {
    claude-frontend = "claude --mcp-config ~/.config/claude-code/mcp-playwright.json";
    claude-cad = "claude --mcp-config ~/.config/claude-code/mcp-freecad.json";
  };

  freecad-mcp-addon = pkgs.fetchFromGitHub {
    owner = "neka-nat";
    repo = "freecad-mcp";
    rev = "8babe9927ce8e6e8fe7dd6ae2ffa2c93776e845a";
    hash = "sha256-dryocwUb26S1+msUTZDUYGoyizxKuAeqMiTqyD8/ybo=";
  };

  # FreeCAD 1.1+ keeps user data per minor version (~/.local/share/FreeCAD/v1-1)
  freecadUserDir = "v" + lib.replaceStrings ["."] ["-"] (lib.versions.majorMinor pkgs.freecad.version);
in {
  # Generate additional MCP configs (add to base MCPs)
  xdg.configFile = {
    # Frontend MCP: Playwright for browser automation and UI inspection
    "claude-code/mcp-playwright.json".text = builtins.toJSON {
      mcpServers = {
        inherit (mcpServers.base) playwright;
      };
    };

    # FreeCAD MCP: talks to the addon's RPC server inside a running FreeCAD
    "claude-code/mcp-freecad.json".text = builtins.toJSON {
      mcpServers = {
        freecad = mcpServers.helpers.mkUvxMcp {package = "freecad-mcp";};
      };
    };
  };

  # macOS FreeCAD is a Homebrew cask with its own data dir
  home.file = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    ".local/share/FreeCAD/${freecadUserDir}/Mod/FreeCADMCP".source = "${freecad-mcp-addon}/addon/FreeCADMCP";
  };

  # Shell aliases (adds to base, allows project .mcp.json)
  programs.fish.shellAliases = mcpAliases;
  programs.bash.shellAliases = mcpAliases;
}

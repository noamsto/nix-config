{
  pkgs,
  lib,
  config,
  ...
}: let
  # Shared MCP server definitions
  mcpServers = import ../mcp-servers.nix {inherit pkgs;};

  # Convert MCP server definitions to Amp format
  # Amp expects mcpServers with command/args or url/headers
  toAmpMcpServer = name: server:
    if server ? command
    then {
      inherit (server) command;
      args = server.args or [];
      env = server.env or {};
    }
    else if server ? url || server ? type
    then {
      url = server.url;
      headers = server.headers or {};
    }
    else throw "Invalid MCP server definition for ${name}";

  # Generate Amp-compatible MCP server config
  ampMcpServers = lib.mapAttrs toAmpMcpServer mcpServers.base;

  # Wrap amp with nodejs/uv in PATH for MCP servers
  # Uses wrappers lib for clean PATH injection (similar to claude-code setup)
  amp-wrapped =
    if pkgs ? wrappers
    then
      pkgs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.amp;
        # Make npx (nodejs) and uvx (uv) available for MCP servers
        runtimeInputs = [pkgs.nodejs pkgs.uv];
      }
    else
      # Fallback if wrappers not available: simple shell wrapper
      pkgs.symlinkJoin {
        name = "amp-wrapped";
        paths = [pkgs.amp];
        buildInputs = [pkgs.makeWrapper];
        postBuild = ''
          wrapProgram $out/bin/amp \
            --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.nodejs pkgs.uv]}
        '';
      };
in {
  # Import MCP profiles module (generates conditional MCP configs and aliases)
  imports = [./mcp-profiles.nix];

  # Global AGENTS.md - symlink to Claude's global instructions
  # Amp searches for AGENTS.md (primary) or CLAUDE.md (fallback)
  # This makes the same instructions available to both agents
  home.file.".config/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "/home/noams/nix-config/home/ai/claude-code/CLAUDE.global.md";

  # Amp settings.json - CLI reads MCP servers from here
  xdg.configFile."amp/settings.json".text = builtins.toJSON {
    "amp.terminal.theme" = "catppuccin-mocha";
    "amp.mcpServers" = ampMcpServers;
  };

  # Install Amp with wrapped version (nodejs/uv in PATH)
  home.packages = [amp-wrapped];
}

{
  pkgs,
  lib,
  config,
  ...
}: let
  # Shared MCP server definitions
  mcpServers = import ../mcp-servers.nix {inherit pkgs;};

  toAmpMcpServer = name: server:
    if server ? command
    then {
      inherit (server) command;
      args = server.args or [];
      env = server.env or {};
    }
    else if server ? url || server ? type
    then {
      inherit (server) url;
      headers = server.headers or {};
    }
    else throw "Invalid MCP server definition for ${name}";

  ampMcpServers = lib.mapAttrs toAmpMcpServer mcpServers.base;

  amp-wrapped =
    if pkgs ? wrappers
    then
      pkgs.wrappers.lib.wrapPackage {
        inherit pkgs;
        package = pkgs.amp;
        runtimeInputs = [pkgs.nodejs pkgs.uv];
      }
    else
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
  imports = [./mcp-profiles.nix];

  # Amp reads AGENTS.md (primary) or CLAUDE.md (fallback) — share Claude's global instructions
  home.file.".config/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/claude-code/CLAUDE.global.md";

  xdg.configFile."amp/settings.json".text = builtins.toJSON {
    "amp.terminal.theme" = "catppuccin-mocha";
    "amp.mcpServers" = ampMcpServers;
  };

  home.packages = [amp-wrapped];
}

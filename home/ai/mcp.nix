# Centralized MCP server definitions for programs.mcp module
{
  pkgs,
  lib,
  config,
  ...
}: let
  mcpServers = import ./mcp-servers.nix {
    inherit pkgs lib;
    inherit (config.home) username;
  };
in {
  programs.mcp = {
    enable = true;
    servers = {
      inherit (mcpServers.base) context7;
    };
  };
}

# Centralized MCP server definitions for programs.mcp module
{
  pkgs,
  lib,
  ...
}: let
  mcpServers = import ./mcp-servers.nix {inherit pkgs lib;};
in {
  programs.mcp = {
    enable = true;
    servers = {
      inherit (mcpServers.base) context7;
    };
  };
}

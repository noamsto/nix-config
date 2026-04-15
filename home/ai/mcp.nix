# Centralized MCP server definitions for programs.mcp module
{
  pkgs,
  lib,
  osConfig,
  ...
}: let
  mcpServers = import ./mcp-servers.nix {inherit pkgs lib;};
in {
  programs.mcp = {
    enable = true;
    servers =
      {
        inherit (mcpServers.base) context7;
      }
      // lib.optionalAttrs (osConfig.profile == "work") {
        groundcover = mcpServers.helpers.mkNpxMcp {
          package = "mcp-remote@0.1.30";
          args = [
            "https://mcp.groundcover.com/api/mcp"
            "54278"
            "--header"
            "X-Timezone:Asia/Jerusalem"
            "--header"
            "X-Tenant-UUID:f9cea478-4af0-451b-b226-c05829b9f8ea"
            "--header"
            "X-Backend-Id:groundcover"
          ];
        };
      };
  };
}

{
  config,
  pkgs,
  lib,
  ...
}: let
  # Only include chromium browser, skip firefox and webkit
  executable = lib.getExe pkgs.chromium;
in {
  programs.claude-code = {
    enable = true;
    package = pkgs.claude-code;

    mcpServers = {
      # Packaged servers from mcp-servers-nix (reproducible, offline)
      playwright = {
        command = "${pkgs.playwright-mcp}/bin/mcp-server-playwright";
        args = [
          "--executable-path"
          executable
        ];
      };

      context7 = {
        command = "${pkgs.context7-mcp}/bin/context7-mcp";
        args = [];
        env = {};
      };

      sequential-thinking = {
        command = "${pkgs.mcp-server-sequential-thinking}/bin/mcp-server-sequential-thinking";
        args = [];
        env = {};
      };

      # Packaged tavily-mcp from custom package (packages/tavily-mcp.nix)
      # NOTE: Alternative npx approach (works but not reproducible):
      #   command = "${pkgs.nodejs}/bin/npx";
      #   args = ["-y" "tavily-mcp@latest"];
      #   env = {
      #     PATH = "${pkgs.lib.makeBinPath [pkgs.nodejs pkgs.bash pkgs.coreutils]}";
      #     # Need bash and coreutils for npm to spawn sh processes
      #     # TAVILY_API_KEY = "your-api-key";
      #   };
      tavily = {
        command = "${pkgs.tavily-mcp}/bin/tavily-mcp";
        args = [];
        env = {
          # TAVILY_API_KEY = "your-api-key-here";  # TODO: integrate with agenix
        };
      };
    };
  };
}

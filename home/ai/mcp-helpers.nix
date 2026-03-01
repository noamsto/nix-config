# Helper functions for creating MCP server configurations
# Provides pragmatic npx/uvx access via PATH injection
{pkgs}: {
  # Helper to create npx MCP server config
  # Usage: mkNpxMcp { package = "tavily-mcp@latest"; env.API_KEY = "..."; }
  mkNpxMcp = {
    package,
    args ? [],
    env ? {},
  }: {
    command = "${pkgs.nodejs}/bin/npx";
    args = ["-y" package] ++ args;
    env =
      {
        PATH = pkgs.lib.makeBinPath [pkgs.nodejs pkgs.bash pkgs.coreutils];
      }
      // env;
  };

  # Helper for uvx (Python) MCP servers
  # Usage: mkUvxMcp { package = "mcp-server-fetch"; }
  mkUvxMcp = {
    package,
    args ? [],
    env ? {},
  }: {
    command = "${pkgs.uv}/bin/uvx";
    args = [package] ++ args;
    inherit env;
  };
}

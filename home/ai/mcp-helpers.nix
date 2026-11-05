# Helper functions for creating MCP server configurations
# Provides pragmatic npx/uvx access via PATH injection or wrapper scripts
{pkgs}: {
  # Helper to create npx MCP server config with full paths
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

  # Create a wrapper script for npx-based MCP servers
  # This allows editable JSON configs while ensuring npx is in PATH
  # Usage: mkNpxWrapper { name = "playwright-mcp"; package = "playwright-mcp"; extraArgs = ["--headless"]; }
  mkNpxWrapper = {
    name,
    package,
    extraArgs ? [],
  }:
    pkgs.writeShellScriptBin name ''
      export PATH="${pkgs.lib.makeBinPath [pkgs.nodejs pkgs.bash pkgs.coreutils]}:$PATH"
      exec ${pkgs.nodejs}/bin/npx -y ${package} ${pkgs.lib.escapeShellArgs extraArgs} "$@"
    '';

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

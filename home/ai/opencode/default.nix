{
  pkgs,
  lib,
  config,
  ...
}: let
  mcpServers = import ../mcp-servers.nix {inherit pkgs lib;};
in {
  home.packages = with pkgs; [
    oh-my-opencode
    (pkgs.writeShellScriptBin "comment-checker" ''
      exec ${pkgs.nodejs}/bin/npx --yes @code-yeongyu/comment-checker "$@"
    '')
    nixd # Nix LSP
    typescript-language-server # TS/JS LSP
    bash-language-server # Shell script LSP
    yaml-language-server # YAML LSP
    lua-language-server # Lua LSP (nvim configs)
    # MCP servers
    context7-mcp
    # playwright-mcp has bundled chromium, no need to add separately
    # MCP wrappers for editable JSON configs (ensures npx is in PATH)
    mcpServers.wrappers.playwright
  ];

  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;
    tui = {
      theme = "catppuccin";
    };
  };

  # Symlink OpenCode directories and config for easy editing without rebuilding
  # These are out-of-store symlinks pointing to this repo
  xdg.configFile = {
    "opencode/opencode.json".source =
      lib.mkForce
      (config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/nix-config/home/ai/opencode/opencode.json");
    # package.json pins runtime npm deps that opencode resolves dynamically
    # (e.g. provider.<name>.npm). Activation runs `bun install` to populate
    # ~/.config/opencode/node_modules/.
    "opencode/package.json".source =
      lib.mkForce
      (config.lib.file.mkOutOfStoreSymlink
        "${config.home.homeDirectory}/nix-config/home/ai/opencode/package.json");
    "opencode/skills".source =
      config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nix-config/home/ai/opencode/skills";
    "opencode/commands".source =
      config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nix-config/home/ai/opencode/commands";
    "opencode/agents".source =
      config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nix-config/home/ai/opencode/agents";
    "opencode/plugins".source =
      config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nix-config/home/ai/opencode/plugins";
    "opencode/instructions".source =
      config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nix-config/home/ai/opencode/instructions";
    "opencode/oh-my-openagent.json".source =
      config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/nix-config/home/ai/opencode/oh-my-opencode.json";
  }; # closes xdg.configFile

  # Install the runtime npm deps declared in package.json (Lemonade provider
  # needs @ai-sdk/openai-compatible at resolve time). Bun reads ./package.json
  # and writes to ./node_modules/ — no global install.
  home.activation.opencodeBunInstall = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if [ -L "$HOME/.config/opencode/package.json" ]; then
      run --quiet ${pkgs.bun}/bin/bun install --cwd "$HOME/.config/opencode" --silent || true
    fi
  '';
}

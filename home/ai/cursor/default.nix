# Cursor CLI module with shared MCP configuration
{
  config,
  pkgs,
  lib,
  ...
}: let
  mcpServers = import ../mcp-servers.nix {inherit pkgs lib;};
in {
  home = {
    # Cursor CLI (`cursor-agent`). Used both interactively and as an alternate
    # work-profile `dispatch` worker engine (`dispatch … --agent cursor …`, gated
    # in dispatch.sh). Auth is out of band — run `cursor-agent login` once; there's
    # no secret to manage in Nix.
    packages = [pkgs.cursor-agent];

    file = {
      # Generate cursor MCP config at ~/.cursor/mcp.json
      # Uses same base MCPs as Claude Code for consistent experience.
      # cursor-agent has no per-invocation MCP-config flag, so this single shared
      # file also serves dispatched cursor workers (no separate worker profile —
      # the launch passes --approve-mcps for headless auto-approval).
      # Note: Cursor uses ~/.cursor (not ~/.config/cursor) for its config
      ".cursor/mcp.json".text = builtins.toJSON {
        mcpServers = mcpServers.base;
      };

      # Global instructions. `~/.cursor/rules/*.mdc` is cursor's user-level rule
      # directory — the file is silently ignored unless it carries
      # `alwaysApply: true` frontmatter, which AGENTS.shared.md provides. Symlinks
      # are followed, so this points at the same file claude imports and codex reads
      # as ~/.codex/AGENTS.md. Out-of-store to stay editable without a rebuild.
      ".cursor/rules/shared-conventions.mdc".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/ai/AGENTS.shared.md";
    };
  };
}

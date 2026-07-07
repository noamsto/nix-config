{
  lib,
  osConfig,
  ...
}: {
  imports =
    [
      ./amp
      ./claude-code
      ./cursor
      ./mcp.nix
      ./opencode
    ]
    # Codex is a work-only engine — there's no personal OpenAI account, so the
    # package and its dispatch worker profile are dead weight elsewhere.
    ++ lib.optionals (osConfig.profile == "work") [./codex];
}

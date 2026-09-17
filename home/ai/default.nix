{
  lib,
  osConfig,
  ...
}: {
  imports =
    [
      ./agent-skills
      ./amp
      ./claude-code
      ./cursor
      ./hookyard
      ./houston
      ./mcp.nix
      ./opencode
      ./pi
    ]
    # Codex is a work-only engine — there's no personal OpenAI account, so the
    # package and its dispatch worker profile are dead weight elsewhere.
    ++ lib.optionals (osConfig.profile == "work") [./codex];
}

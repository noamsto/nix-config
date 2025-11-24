{...}: {
  imports = [
    ./claude-code
    ./mcp.nix
    ./opencode
  ];
  programs = {
    gemini-cli = {
      enable = true;
      settings = {
        vimMode = true;
        preferredEditor = "vim";
      };
    };

    codex = {
      enable = true;
    };
  };
}

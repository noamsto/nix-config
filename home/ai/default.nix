{...}: {
  imports = [
    ./claude-code
    ./cursor
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

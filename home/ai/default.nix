{...}: {
  imports = [
    ./amp
    ./claude-code
    ./cursor
    ./mcp.nix
    ./opencode
  ];
  programs = {
    gemini-cli = {
      enable = false;
      settings = {
        vimMode = true;
        preferredEditor = "vim";
      };
    };
  };
}

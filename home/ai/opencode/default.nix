{pkgs, ...}: {
  home.packages = with pkgs; [
    oh-my-opencode
    (pkgs.writeShellScriptBin "comment-checker" ''
      exec ${pkgs.nodejs}/bin/npx --yes @code-yeongyu/comment-checker "$@"
    '')
    nil # Nix LSP
    typescript-language-server # TS/JS LSP
  ];

  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;
    settings = {
      autoupdate = false;
      plugin = [
        "oh-my-openagent"
      ];
    };
    tui = {
      theme = "catppuccin";
    };
  };

  xdg.configFile."opencode/oh-my-openagent.json".text = builtins.toJSON {
    agents = {
      sisyphus = { model = "opencode/claude-opus-4-6"; };
      oracle = { model = "opencode/gpt-5.4"; };
      explore = { model = "opencode/claude-haiku-4-5"; };
      prometheus = { model = "opencode/gemini-3.1-pro"; };
      atlas = { model = "opencode/claude-sonnet-4-6"; };
      metis = { model = "opencode/gemini-3.1-pro"; };
      librarian = { model = "opencode/claude-haiku-4-5"; };
      hephaestus = { model = "opencode/gpt-5.3-codex"; };
    };
  };
}

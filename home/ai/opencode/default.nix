{pkgs, ...}: {
  home.packages = with pkgs; [
    oh-my-opencode
    (pkgs.writeShellScriptBin "comment-checker" ''
      exec ${pkgs.nodejs}/bin/npx --yes @code-yeongyu/comment-checker "$@"
    '')
    nixd # Nix LSP
    typescript-language-server # TS/JS LSP
  ];

  programs.opencode = {
    enable = true;
    enableMcpIntegration = true;
    settings = {
      autoupdate = false;
      plugin = [
        "${pkgs.oh-my-opencode}/lib/oh-my-opencode"
      ];
    };
    tui = {
      theme = "catppuccin";
    };
  };

  # OpenCode web server — accessible via Tailscale
  systemd.user.services.opencode-web = {
    Unit = {
      Description = "OpenCode Web Server";
      After = ["network-online.target"];
    };
    Service = {
      Type = "simple";
      EnvironmentFile = "/etc/agenix/opencode-server-password.env";
      ExecStart = "${pkgs.opencode}/bin/opencode web --hostname 0.0.0.0 --port 4096";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    Install = {
      WantedBy = ["default.target"];
    };
  };

  xdg.configFile."opencode/oh-my-openagent.json".text = builtins.toJSON {
    agents = {
      sisyphus = {model = "opencode/kimi-k2.5";};
      oracle = {model = "opencode/gpt-5.4";};
      explore = {model = "opencode/claude-haiku-4-5";};
      prometheus = {model = "opencode/gemini-3.1-pro";};
      atlas = {model = "opencode/claude-sonnet-4-6";};
      metis = {model = "opencode/gemini-3.1-pro";};
      librarian = {model = "opencode/claude-haiku-4-5";};
      hephaestus = {model = "opencode/gpt-5.3-codex";};
    };
  };
}

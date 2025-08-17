{...}: {
  programs.ghostty = {
    enable = true;
    enableFishIntegration = true;
    installVimSyntax = true;
    installBatSyntax = true;
    settings = {
      background-opacity = 0.9;
    };
  };
}

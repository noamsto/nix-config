{inputs, ...}: {
  imports = [inputs.catppuccin.homeModules.catppuccin];

  catppuccin = {
    flavor = "mocha";

    starship.enable = true;
    btop.enable = true;
    foot.enable = true;
    ghostty.enable = true;
    k9s.enable = true;
    bat.enable = true;
    yazi.enable = true;
    lazygit.enable = true;
    fzf.enable = true;
    zsh-syntax-highlighting.enable = true;
    fish.enable = true;
    brave.enable = true;
  };
}

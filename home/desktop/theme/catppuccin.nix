{inputs, ...}: {
  imports = [inputs.catppuccin.homeModules.catppuccin];

  catppuccin = {
    flavor = "mocha";

    # === DEVELOPMENT & EDITORS ===
    # neovim theming is handled by LazyVim catppuccin plugin

    # === TERMINAL APPLICATIONS ===
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

    # === DEVELOPMENT TOOLS ===
    delta.enable = true; # Git diff highlighting

    # === BROWSERS ===
    brave.enable = true;
  };
}

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
    kitty.enable = true;
    k9s.enable = true;
    bat.enable = true;
    yazi.enable = true;
    lazygit.enable = true;
    fzf.enable = true;
    zsh-syntax-highlighting.enable = true;
    fish.enable = true;
    # wleave doesn't have catppuccin theme support yet - using custom CSS in wleave.nix

    # === DEVELOPMENT TOOLS ===
    delta.enable = true;

    # === BROWSERS ===
    brave.enable = true;

    # === HYPRLAND ===
    hyprlock.enable = true;
  };
}

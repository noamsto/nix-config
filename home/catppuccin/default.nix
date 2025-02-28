{inputs, ...}: {
  imports = [inputs.catppuccin.homeManagerModules.catppuccin];

  catppuccin = {
    flavor = "mocha";

    starship.enable = true;
    btop.enable = true;
    foot.enable = true;
    k9s.enable = true;
    bat.enable = true;
    yazi.enable = true;
  };
}

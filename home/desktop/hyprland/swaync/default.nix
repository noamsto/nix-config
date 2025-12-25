{
  config,
  lib,
  pkgs,
  ...
}: let
  # Generate CSS color definitions from palette
  mkColorsCss = p: ''
    /* ${p.name} color definitions - Generated from config.theme.palette */
    @define-color rosewater ${p.rosewater};
    @define-color flamingo ${p.flamingo};
    @define-color pink ${p.pink};
    @define-color mauve ${p.mauve};
    @define-color red ${p.red};
    @define-color maroon ${p.maroon};
    @define-color peach ${p.peach};
    @define-color yellow ${p.yellow};
    @define-color green ${p.green};
    @define-color teal ${p.teal};
    @define-color sky ${p.sky};
    @define-color sapphire ${p.sapphire};
    @define-color blue ${p.blue};
    @define-color lavender ${p.lavender};
    @define-color text ${p.text};
    @define-color subtext1 ${p.subtext1};
    @define-color subtext0 ${p.subtext0};
    @define-color overlay2 ${p.overlay2};
    @define-color overlay1 ${p.overlay1};
    @define-color overlay0 ${p.overlay0};
    @define-color surface2 ${p.surface2};
    @define-color surface1 ${p.surface1};
    @define-color surface0 ${p.surface0};
    @define-color base ${p.base};
    @define-color mantle ${p.mantle};
    @define-color crust ${p.crust};
  '';

  palette = config.theme.palette;
in {
  # Install swaync package directly instead of using service module
  # This avoids the service module overriding our out-of-store symlinks
  home.packages = [pkgs.swaynotificationcenter];

  # Use out-of-store symlinks for config (development iteration)
  # NOTE: style.css is NOT symlinked - it's generated directly by theme-toggle
  # from swaync-colors-*.css + swaync-style-base.css
  xdg.configFile = {
    "swaync/config.json".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/desktop/hyprland/swaync/swaync-config.json";
    "swaync/icons".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/desktop/hyprland/swaync/icons";
    # Base style (without colors)
    "swaync/swaync-style-base.css".source = config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/nix-config/home/desktop/hyprland/swaync/swaync-style-base.css";
    # Generated color CSS files (used by theme-toggle)
    "swaync/swaync-colors-${palette.dark.name}.css".text = mkColorsCss palette.dark;
    "swaync/swaync-colors-${palette.light.name}.css".text = mkColorsCss palette.light;
  };
}

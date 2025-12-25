{
  pkgs,
  config,
  ...
}: let
  palette = config.theme.palette;

  # Generate wleave CSS from palette
  # Window background uses semi-transparent variant of base
  windowBg = p:
    if p.variant == "dark"
    then "rgba(12, 12, 12, 0.8)"
    else "rgba(239, 241, 245, 0.9)";

  mkWleaveCss = p: ''
    /* ${p.name} - Generated from config.theme.palette */
    window {
        background-color: ${windowBg p};
    }

    button {
        background-color: ${p.base};
        border: none;
        padding: 10px;
        border-radius: 12px;
    }

    button:focus,
    button:hover {
        background-color: ${p.surface0};
    }

    button:active {
        background-color: ${p.surface1};
    }

    button label.action-name {
        font-size: 24px;
    }

    button label.keybind {
        font-size: 20px;
        font-family: monospace;
    }

    button:hover label.keybind, button:focus label.keybind {
        opacity: 1;
    }

    button#shutdown { color: ${p.red}; }
    button#hibernate { color: ${p.blue}; }
    button#reboot { color: ${p.green}; }
    button#lock { color: ${p.yellow}; }
    button#logout { color: ${p.peach}; }
    button#suspend { color: ${p.mauve}; }
  '';
in {
  programs.wleave = {
    enable = true;
    # Don't use style option - we manage style.css via theme-toggle for dynamic switching
  };

  # Theme CSS files for dynamic switching (generated from palette)
  # theme-toggle.sh copies the appropriate one to style.css
  xdg.configFile = {
    "wleave/style-${palette.dark.name}.css".text = mkWleaveCss palette.dark;
    "wleave/style-${palette.light.name}.css".text = mkWleaveCss palette.light;
  };
}

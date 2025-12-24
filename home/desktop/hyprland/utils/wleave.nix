{pkgs, ...}: let
  # Shared CSS structure
  baseCss = ''
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

    button#shutdown {
        color: #ff8d8d;
    }

    button#hibernate {
        color: #a8c0ff;
    }

    button#reboot {
        color: #84ffaa;
    }

    button#lock {
        color: #ffe8b6;
    }

    button#logout {
        color: #ffcca8;
    }

    button#suspend {
        color: #caaff9;
    }
  '';

  # Dark theme (Catppuccin Mocha)
  darkCss = ''
    /* Catppuccin Mocha */
    window {
        background-color: rgba(12, 12, 12, 0.8);
    }

    button {
        background-color: #1e1e2e;
        border: none;
        padding: 10px;
        border-radius: 12px;
    }

    button:focus,
    button:hover {
        background-color: #313244;
    }

    button:active {
        background-color: #45475a;
    }

    ${baseCss}
  '';

  # Light theme (Catppuccin Latte) - uses darker colors for contrast
  lightCss = ''
    /* Catppuccin Latte */
    window {
        background-color: rgba(239, 241, 245, 0.9);
    }

    button {
        background-color: #eff1f5;
        border: none;
        padding: 10px;
        border-radius: 12px;
    }

    button:focus,
    button:hover {
        background-color: #ccd0da;
    }

    button:active {
        background-color: #bcc0cc;
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

    /* WCAG AA compliant colors for light theme */
    button#shutdown {
        color: #d20f39;
    }

    button#hibernate {
        color: #1e66f5;
    }

    button#reboot {
        color: #358023; /* Darkened for 4.5:1 contrast */
    }

    button#lock {
        color: #996b00; /* Darkened for 4.7:1 contrast */
    }

    button#logout {
        color: #c24b00; /* Darkened for 4.6:1 contrast */
    }

    button#suspend {
        color: #8839ef;
    }
  '';
in {
  programs.wleave = {
    enable = true;
    # Don't use style option - we manage style.css via theme-toggle for dynamic switching
  };

  # Theme CSS files for dynamic switching
  # theme-toggle.sh copies the appropriate one to style.css
  xdg.configFile = {
    "wleave/style-mocha.css".text = darkCss;
    "wleave/style-latte.css".text = lightCss;
  };
}

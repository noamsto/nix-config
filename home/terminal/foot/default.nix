{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (config.theme) palette;

  # Same tmux attach/create flow as kitty (home/terminal/kitty/default.nix).
  # Wrapped in a script because foot's main.shell tokenizer doesn't preserve
  # quoting well enough to pass `fish -l -c '<long pipeline>'` reliably.
  tmuxLauncher = pkgs.writeShellScript "foot-tmux-launcher" ''
    exec ${pkgs.fish}/bin/fish -l -c \
      'systemctl --user start tmux-startup.service && \
        TMUX_TMPDIR=/run/user/$(id -u) tmux attach -t nix-config || \
        TMUX_TMPDIR=/run/user/$(id -u) tmux new -As nix-config -c $HOME/nix-config'
  '';

  s = color: lib.removePrefix "#" color;

  mkFootTheme = p: ''
    [colors-${p.variant}]
    foreground=${s p.text}
    background=${s p.base}
    cursor=${s p.base} ${s p.rosewater}
    selection-foreground=${s p.text}
    selection-background=${s p.surface1}
    search-box-no-match=${s p.crust} ${s p.red}
    search-box-match=${s p.text} ${s p.surface0}
    jump-labels=${s p.crust} ${s p.peach}
    urls=${s p.blue}

    regular0=${s p.surface1}
    regular1=${s p.red}
    regular2=${s p.green}
    regular3=${s p.yellow}
    regular4=${s p.blue}
    regular5=${s p.pink}
    regular6=${s p.teal}
    regular7=${s p.subtext1}

    bright0=${s p.surface2}
    bright1=${s p.red}
    bright2=${s p.green}
    bright3=${s p.yellow}
    bright4=${s p.blue}
    bright5=${s p.pink}
    bright6=${s p.teal}
    bright7=${s p.subtext0}

    16=${s p.peach}
    17=${s p.rosewater}
  '';

  footSettings = {
    main = {
      font = "Fira Code Nerd Font:size=11, Noto Color Emoji:size=11";
      dpi-aware = "yes";
      pad = "8x8 center";
      shell = "${tmuxLauncher}";
    };

    colors-dark = {
      alpha = "0.92";
    };

    cursor = {
      style = "beam";
      blink = "yes";
    };

    mouse = {
      hide-when-typing = "yes";
    };

    scrollback = {
      lines = 10000;
    };

    text-bindings = {
      "\\x1b[72;6u" = "Control+Shift+h";
      "\\x1b[74;6u" = "Control+Shift+j";
      "\\x1b[75;6u" = "Control+Shift+k";
      "\\x1b[76;6u" = "Control+Shift+l";

      "\\x1b[105;5u" = "Control+i";

      "\\x1b[46;5u" = "Control+period";
      "\\x1b[44;5u" = "Control+comma";
      "\\x1b[59;5u" = "Control+semicolon";

      "\\x1b[13;2u" = "Shift+Return";
    };
  };

  # foot's `include=` directive must live in the default (top-level) section,
  # before any [section] header. HM's programs.foot.settings is a strict
  # attrsOf-attrsOf, so we generate foot.ini ourselves and override it.
  footIni =
    ''
      # Default to the dark theme; theme-toggle rewrites this line at runtime
      # to switch between catppuccin-mocha (dark) and catppuccin-latte (light).
      include=${config.xdg.configHome}/foot/themes/${palette.dark.name}.ini

    ''
    + lib.generators.toINI {} footSettings;
in {
  programs.foot = {
    enable = true;
    # Leave HM's settings empty so its `mkIf (settings != {})` guard skips
    # generating foot.ini; the override below is the canonical source.
    settings = {};
  };

  xdg.configFile = {
    "foot/foot.ini".text = footIni;
    "foot/themes/${palette.dark.name}.ini".text = mkFootTheme palette.dark;
    "foot/themes/${palette.light.name}.ini".text = mkFootTheme palette.light;

    # Pin the preferred terminal for `Terminal=true` .desktop launches (btop,
    # htop, …). Without this, launchers like vicinae auto-pick across
    # foot.desktop / foot-server.desktop / footclient.desktop — the server
    # entry runs `foot --server -e <cmd>`, which daemonizes foot and ignores
    # the command, so nothing opens.
    "xdg-terminals.list".text = ''
      foot.desktop
      kitty.desktop
    '';
  };
}

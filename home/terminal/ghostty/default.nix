{
  pkgs,
  config,
  ...
}: let
  inherit (config.theme) palette;

  # Ghostty themes use hex colors without # prefix
  stripHash = color: builtins.replaceStrings ["#"] [""] color;

  mkGhosttyTheme = p: {
    background = stripHash p.base;
    foreground = stripHash p.text;
    cursor-color = stripHash p.rosewater;
    cursor-text = stripHash p.base;
    selection-background = stripHash p.rosewater;
    selection-foreground = stripHash p.base;

    palette = [
      "0=${stripHash p.surface1}"
      "1=${stripHash p.red}"
      "2=${stripHash p.green}"
      "3=${stripHash p.yellow}"
      "4=${stripHash p.blue}"
      "5=${stripHash p.pink}"
      "6=${stripHash p.teal}"
      "7=${stripHash p.subtext1}"
      "8=${stripHash p.surface2}"
      "9=${stripHash p.red}"
      "10=${stripHash p.green}"
      "11=${stripHash p.yellow}"
      "12=${stripHash p.blue}"
      "13=${stripHash p.pink}"
      "14=${stripHash p.teal}"
      "15=${stripHash p.subtext0}"
    ];
  };
in {
  programs.ghostty = {
    enable = true;
    enableFishIntegration = true;

    settings = {
      theme = palette.dark.name;

      background-opacity = 0.92;

      font-family = "FiraCode Nerd Font";
      font-family-bold = "FiraCode Nerd Font Bold";
      font-family-italic = "FiraCode Nerd Font Italic";
      font-family-bold-italic = "FiraCode Nerd Font Bold Italic";
      font-size = 12;
      font-feature = ["zero" "ss01"];

      cursor-style = "block";
      # Prevent fish integration from overriding cursor style — keeps shader uniforms consistent
      shell-integration-features = "no-cursor";
      custom-shader = builtins.toString ./shaders/cursor-trail.glsl;

      window-decoration = false;
      window-padding-x = 8;
      window-padding-y = 8;
      window-padding-balance = true;
      window-padding-color = "extend";

      mouse-hide-while-typing = true;
      shell-integration = "fish";

      scrollback-limit = 10000;

      clipboard-read = "ask";
      clipboard-write = "allow";

      confirm-close-surface = false;

      gtk-single-instance = true;

      # Linux: systemctl start is synchronous + idempotent (server created in its
      # own scope, never inside ghostty's), then point tmux at the
      # $XDG_RUNTIME_DIR socket. darwin: lazytmux's launchd agent already started
      # the server on the default /tmp socket, so just attach/create.
      command =
        if pkgs.stdenv.hostPlatform.isDarwin
        then "${pkgs.fish}/bin/fish -l -c 'tmux attach -t nix-config; or tmux new -As nix-config -c $HOME/nix-config'"
        else "${pkgs.fish}/bin/fish -l -c 'systemctl --user start tmux-startup.service; and TMUX_TMPDIR=/run/user/(id -u) tmux attach -t nix-config; or TMUX_TMPDIR=/run/user/(id -u) tmux new -As nix-config -c $HOME/nix-config'";

      keybind = [
        "ctrl+equal=increase_font_size:1"
        "ctrl+minus=decrease_font_size:1"
        "ctrl+shift+equal=reset_font_size"
        "ctrl+shift+c=copy_to_clipboard"
        "ctrl+shift+v=paste_from_clipboard"
        "shift+enter=text:\\x1b[13;2u"
        # Disable built-in tab/split management (using tmux)
        "ctrl+shift+t=unbind"
        "ctrl+shift+w=unbind"
        "ctrl+shift+n=unbind"
        "ctrl+shift+enter=unbind"
      ];
    };

    themes = {
      "${palette.dark.name}" = mkGhosttyTheme palette.dark;
      "${palette.light.name}" = mkGhosttyTheme palette.light;
    };
  };
}

{
  pkgs,
  config,
  ...
}: let
  pointer = config.home.pointerCursor;
  cursorName = "Bibata-Modern-Ice";
  # cursorPackage = pkgs.callPackage ./../bibata-hyprcursor {}; # Move to flake parts for this!
in {
  imports = [./bindings.nix ./window_rule.nix];
  # xdg.dataFile."icons/${cursorName}".source = "${cursorPackage}/share/icons/${cursorName}";
  wayland.windowManager.hyprland = {
    settings = let
      laptop-monitor = "eDP-1";
      laptop-monitor-pos = "${laptop-monitor},2880x1800, 2048x1152,1.40625";
      home-ext-monitor-left = "desc:Samsung Electric Company S27H85x H4ZM300138";
      home-ext-monitor-right = "desc:Samsung Electric Company S27H85x H4ZKB00167";
    in {
      monitor = [
        "${home-ext-monitor-left},2560x1440,0x0, 1.25" # Left External Monitor
        "${home-ext-monitor-right},2560x1440, 2048x0,1.25" # Right External Monitor Home
        laptop-monitor-pos # Laptop Monitor
        ",preferred,auto,auto"
      ];
      bindl = [
        # trigger when the switch is turning on
        ", switch:on:Lid Switch, exec, hyprctl keyword monitor \"${laptop-monitor}, disable\""
        # trigger when the switch is turning off
        ", switch:off:Lid Switch, exec, hyprctl keyword monitor \"${laptop-monitor-pos}\""
      ];
      workspace = [
        "1,default:true,monitor:${home-ext-monitor-left},persistent:true"
        "2,monitor:${home-ext-monitor-right},persistent:true"
        "3,monitor:${laptop-monitor},persistent:true"
      ];

      env = [
        "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
        "HYPRCURSOR_THEME,${cursorName}"
        "HYPRCURSOR_SIZE,${toString pointer.size}"
      ];

      exec-once = [
        # set cursor for HL itself
        "hyprctl setcursor ${cursorName} ${toString pointer.size}"
        "hyprlock"

        # Tmux wayland integration
        "tmux setenv -g HYPRLAND_INSTANCE_SIGNATURE \"$HYPRLAND_INSTANCE_SIGNATURE\""
        "tmux setenv -g WAYLAND_DISPLAY \"$WAYLAND_DISPLAY\""
        "tmux setenv -g XDG_RUNTIME_DIR \"$XDG_RUNTIME_DIR\""
      ];

      input = {
        kb_layout = "us,il";
        kb_options = "grp:win_space_toggle";
      };
    };
  };
}

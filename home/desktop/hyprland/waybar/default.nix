{pkgs, ...}: {
  programs.waybar = {
    enable = true;
    systemd.enable = false; # Disabled because using UWSM instead of systemd

    settings = [
      {
        height = 42;
        layer = "top";
        exclusive = true; # This ensures waybar gets its own space
        passthrough = false; # Waybar will capture input events
        # Show on left monitors and internal monitor
        # Exclude right monitors by using ! prefix
        modules-left = [
          "hyprland/workspaces"
          "clock"
          "custom/audio_idle_inhibitor"
          "tray"
        ];
        modules-center = [
          "wlr/taskbar"
        ];
        modules-right = [
          "network"
          "group/hardware"
          "group/power"
          "group/backlight"
          "group/audio"
          "custom/keyboard-layout"
          "custom/swaync"
          # "custom/power-menu"
        ];

        # Separator modules
        "custom/separator#dot" = {
          format = "";
          interval = "once";
          tooltip = false;
        };

        "custom/separator#dot-line" = {
          format = "";
          interval = "once";
          tooltip = false;
        };

        "custom/separator#line" = {
          format = "|";
          interval = "once";
          tooltip = false;
        };

        "custom/separator#blank" = {
          format = "";
          interval = "once";
          tooltip = false;
        };

        "custom/separator#blank_2" = {
          format = "  ";
          interval = "once";
          tooltip = false;
        };

        "custom/separator#blank_3" = {
          format = "   ";
          interval = "once";
          tooltip = false;
        };

        # Group modules with drawer functionality
        "group/hardware" = {
          orientation = "inherit";
          drawer = {
            transition-duration = 500;
            children-class = "not-power";
            transition-left-to-right = true;
          };
          modules = [
            "cpu"
            "memory"
            "disk"
          ];
        };

        "group/audio" = {
          orientation = "inherit";
          drawer = {
            transition-duration = 500;
            children-class = "not-power";
            transition-left-to-right = false;
          };
          modules = [
            "pulseaudio"
            "pulseaudio#microphone"
          ];
        };

        "group/power" = {
          orientation = "inherit";
          drawer = {
            transition-duration = 500;
            children-class = "not-power";
            transition-left-to-right = false;
          };
          modules = [
            "battery"
            "idle_inhibitor"
            "power-profiles-daemon"
          ];
        };

        "group/backlight" = {
          orientation = "inherit";
          drawer = {
            transition-duration = 500;
            children-class = "not-power";
            transition-left-to-right = false;
          };
          modules = [
            "backlight"
            "custom/hyprsunset"
            "backlight/slider"
          ];
        };

        # Hyprland workspaces
        "hyprland/workspaces" = {
          format = "{icon}";
          on-click = "activate";
          format-icons = {
            "1" = "1";
            "2" = "2";
            "3" = "3";
            "4" = "4";
            "5" = "5";
            "6" = "6";
            "7" = "7";
            "8" = "8";
            "9" = "9";
            urgent = "";
          };
          all-outputs = false;
          sort-by-number = true;
          on-scroll-down = "hyprctl dispatch workspace m+1";
          on-scroll-up = "hyprctl dispatch workspace m-1";
        };

        # System tray
        tray = {
          spacing = 10;
        };

        # Clock module
        clock = {
          interval = 60;
          align = 0;
          rotate = 0;
          tooltip-format = "<big>{:%B %Y}</big>\n<tt><small>{calendar}</small></tt>";
          format = "{:%d %b, %I:%M %p}";
          format-alt = "{:%a %b %d, %G}";
        };

        # Hardware monitoring modules
        cpu = {
          format = "{usage}% 󰍛";
          interval = 1;
          format-alt-click = "click";
          format-alt = "{icon0}{icon1}{icon2}{icon3} {usage:>2}% 󰍛";
          format-icons = [
            "▁"
            "▂"
            "▃"
            "▄"
            "▅"
            "▆"
            "▇"
            "█"
          ];
          on-click-right = "${pkgs.writeShellScript "open-system-monitor" ''
            if command -v resources >/dev/null 2>&1; then
              resources
            elif command -v gnome-system-monitor >/dev/null 2>&1; then
              gnome-system-monitor
            else
              foot btop
            fi
          ''}";
        };

        memory = {
          interval = 10;
          format = "{used:0.1f}G 󰾆";
          format-alt = "{percentage}% 󰾆";
          format-alt-click = "click";
          tooltip = true;
          tooltip-format = "{used:0.1f}GB/{total:0.1f}G";
          on-click-right = "foot btop";
        };

        disk = {
          interval = 30;
          path = "/";
          format = "{percentage_used}% 󰋊";
          format-alt-click = "click";
          format-alt = "{free} free 󰋊";
          tooltip = true;
          tooltip-format = "{used} used out of {total} on {path} ({percentage_used}%)";
        };

        # Audio modules
        pulseaudio = {
          format = "{icon}  {volume}%";
          format-bluetooth = "{icon}  {volume}%";
          format-muted = "󰝟";
          format-icons = {
            headphone = "󰋋";
            hands-free = "󰋎";
            headset = "󰋎";
            phone = "";
            portable = "";
            car = "";
            default = [
              "󰕿"
              "󰖀"
              "󰕾"
              "󰕾"
            ];
          };
          ignored-sinks = [
            "Easy Effects Sink"
          ];
          scroll-step = 5.0;
          on-click = "${pkgs.writeShellScript "toggle-audio" ''
            pactl set-sink-mute @DEFAULT_SINK@ toggle
          ''}";
          on-click-right = "pavucontrol -t 3";
          on-scroll-up = "${pkgs.writeShellScript "volume-up" ''
            pactl set-sink-volume @DEFAULT_SINK@ +5%
          ''}";
          on-scroll-down = "${pkgs.writeShellScript "volume-down" ''
            pactl set-sink-volume @DEFAULT_SINK@ -5%
          ''}";
          tooltip-format = "{icon} {desc} | {volume}%";
          smooth-scrolling-threshold = 1;
        };

        "pulseaudio#microphone" = {
          format = "{format_source}";
          format-source = "  {volume}%";
          format-source-muted = "󰍭";
          on-click = "${pkgs.writeShellScript "toggle-mic" ''
            pactl set-source-mute @DEFAULT_SOURCE@ toggle
          ''}";
          on-click-right = "pavucontrol -t 4";
          on-scroll-up = "${pkgs.writeShellScript "mic-up" ''
            pactl set-source-volume @DEFAULT_SOURCE@ +5%
          ''}";
          on-scroll-down = "${pkgs.writeShellScript "mic-down" ''
            pactl set-source-volume @DEFAULT_SOURCE@ -5%
          ''}";
          tooltip-format = "{source_desc} | {source_volume}%";
          scroll-step = 5;
        };

        # Battery module
        battery = {
          full-at = 100;
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon} {capacity}%";
          format-charging = "{icon} {capacity}% ";
          format-plugged = "{icon} {capacity}% ";
          format-full = "{icon} {capacity}% ";
          format-icons = [" " " " " " " " " "];
          format-time = "{H}h {M}min";
          tooltip = true;
        };

        # Taskbar
        "wlr/taskbar" = {
          format = "{icon}";
          icon-size = 28;
          all-outputs = true; # Show applications from all outputs
          tooltip-format = "{title}";
          on-click = "activate";
          on-click-middle = "close";
          markup = true;
          max-length = 50;
        };

        # Network module
        network = {
          tooltip-format-ethernet = "{ifname}  {ipaddr}/{cidr}";
          tooltip-format-wifi = "{essid} ({signalStrength}%)";
          interval = 2;
          on-click-right = "foot nmtui";
          format = "{icon}";
          format-alt-click = "click";
          format-alt = "  {ifname} | {ipaddr}/{cidr} | {gwaddr} {essid}";
          format-disconnected = "󰤭  Offline";
          format-wifi = "󰤨  {bandwidthDownBytes}  {bandwidthUpBytes}";
          format-ethernet = "󰈁  {bandwidthDownBytes}  {bandwidthUpBytes}";
          max-length = 25;
          format-icons = {
            wifi = ["󰤯" "󰤟" "󰤢" "󰤥" "󰤨"];
            ethernet = "󰈁";
            disconnected = "󰤭";
          };
        };

        # Custom keyboard layout indicator with Hebrew support
        "custom/keyboard-layout" = {
          format = "{}";
          exec = "keyboard-layout";
          return-type = "json";
          restart-interval = 0; # Keep script running
          on-click = "hyprctl switchxkblayout xremap next";
          tooltip = true;
        };

        # Idle inhibitor
        idle_inhibitor = {
          format = "{icon}";
          format-icons = {
            activated = "󰒳"; # No sleep/stay awake icon
            deactivated = "󰒲"; # Sleep allowed icon
          };
          tooltip = true;
          tooltip-format-activated = "Screen will stay awake";
          tooltip-format-deactivated = "Screen can go to sleep";
        };

        # Custom modules
        "custom/power-menu" = {
          format = " 󰐥 ";
          on-click = "${pkgs.writeShellScript "power-menu" ''
            if command -v wlogout >/dev/null 2>&1; then
              wlogout
            else
              echo "No power menu available"
            fi
          ''}";
        };

        "custom/audio_idle_inhibitor" = {
          format = "{icon}";
          exec = "${pkgs.writeShellScript "audio-idle-inhibitor" ''
            # Check if audio is playing
            if pactl list sink-inputs | grep -q "RUNNING"; then
              echo '{"text": "󰐎 ", "tooltip": "Audio playing - idle inhibited", "class": "active"}'
            else
              echo '{"text": "󰐏 ", "tooltip": "No audio - idle not inhibited", "class": "inactive"}'
            fi
          ''}";
          return-type = "json";
          interval = 2;
          format-icons = {
            output = "󰐎";
            input = "󰐏 ";
            output-input = "󰐎 󰐏 ";
            none = "󰐏 ";
          };
        };

        "custom/swaync" = {
          tooltip = true;
          format = "{icon}";
          format-icons = {
            notification = "󰂚 <span foreground='red'><sup></sup></span>";
            none = "󰂚";
            dnd-notification = "󰂛 <span foreground='red'><sup></sup></span>";
            dnd-none = "󰂛";
            inhibited-notification = "󰂚 <span foreground='red'><sup></sup></span>";
            inhibited-none = "󰂚";
            dnd-inhibited-notification = "󰂛 <span foreground='red'><sup></sup></span>";
            dnd-inhibited-none = "󰂛";
          };
          return-type = "json";
          exec-if = "which swaync-client";
          exec = "swaync-client -swb";
          on-click = "swaync-client -t -sw";
          on-click-right = "swaync-client -d -sw";
          escape = true;
        };

        "custom/hyprsunset" = {
          format = "{}";
          return-type = "json";
          exec = "${pkgs.writeShellScript "hyprsunset-status" ''
            state_file="$HOME/.cache/hyprsunset_active"
            if [ -f "$state_file" ]; then
              echo '{"text": "󰌵", "tooltip": "Blue light filter: ON (4000K)", "class": "on"}'
            else
              echo '{"text": "󰌶", "tooltip": "Blue light filter: OFF", "class": "off"}'
            fi
          ''}";
          interval = 2;
          on-click = "${pkgs.writeShellScript "toggle-blue-light" ''
            # Since hyprsunset service is running, use IPC commands
            # Keep track of state using a simple toggle file
            state_file="$HOME/.cache/hyprsunset_active"

            if [ -f "$state_file" ]; then
              # Currently active, disable it
              hyprctl hyprsunset identity
              rm -f "$state_file"
              notify-send "Blue Light Filter" "Disabled" -i display-brightness 2>/dev/null || true
            else
              # Currently inactive, enable it
              hyprctl hyprsunset temperature 4000
              touch "$state_file"
              notify-send "Blue Light Filter" "Enabled (4000K)" -i display-brightness 2>/dev/null || true
            fi
          ''}";
        };

        "power-profiles-daemon" = {
          format = "{icon}";
          tooltip-format = "Power profile: {profile}\nDriver: {driver}";
          tooltip = true;
          format-icons = {
            default = "";
            performance = "";
            balanced = " ";
            power-saver = " ";
          };
        };

        # Backlight icon module
        backlight = {
          format = "{icon}";
          format-icons = ["󰃞" "󰃟" "󰃠"];
          tooltip = true;
          tooltip-format = "Brightness: {percent}%";
          on-scroll-up = "brightness-control up 5";
          on-scroll-down = "brightness-control down 5";
          interval = 1;
        };

        # Brightness slider
        "backlight/slider" = {
          min = 5;
          max = 100;
          orientation = "horizontal";
          device = "amdgpu_bl1";
        };
      }
    ];

    # Custom Catppuccin Macchiato styling
    style = ./style.css;
  };

  # Ensure required utilities are available
  home.packages = with pkgs; [
    # Audio utilities
    pulseaudio
    playerctl

    # Network utilities
    networkmanagerapplet

    # Screenshot utilities
    swappy

    # Notification daemon (if using swaync)
    swaynotificationcenter

    # Brightness control (brightnessctl is enabled system-wide)
  ];

  # Create mocha.css file for waybar theming
  xdg.configFile."waybar/mocha.css" = {
    text = ''
      @define-color rosewater #f5e0dc;
      @define-color flamingo #f2cdcd;
      @define-color pink #f5c2e7;
      @define-color mauve #cba6f7;
      @define-color red #f38ba8;
      @define-color maroon #eba0ac;
      @define-color peach #fab387;
      @define-color yellow #f9e2af;
      @define-color green #a6e3a1;
      @define-color teal #94e2d5;
      @define-color sky #89dceb;
      @define-color sapphire #74c7ec;
      @define-color blue #89b4fa;
      @define-color lavender #b4befe;
      @define-color text #cdd6f4;
      @define-color subtext1 #bac2de;
      @define-color subtext0 #a6adc8;
      @define-color overlay2 #9399b2;
      @define-color overlay1 #7f849c;
      @define-color overlay0 #6c7086;
      @define-color surface2 #585b70;
      @define-color surface1 #45475a;
      @define-color surface0 #313244;
      @define-color base #1e1e2e;
      @define-color mantle #181825;
      @define-color crust #11111b;
    '';
  };
}

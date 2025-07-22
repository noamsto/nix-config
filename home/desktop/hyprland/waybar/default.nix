{pkgs, ...}: {
  programs.waybar = {
    enable = true;
    systemd.enable = false; # Disabled because using UWSM instead of systemd

    settings = [
      {
        height = 42;
        layer = "top";
        # Show on all monitors
        modules-left = [
          "custom/launcher"
          "clock"
          "custom/swaync"
          "custom/audio_idle_inhibitor"
          "idle_inhibitor"
          "hyprland/workspaces"
          "tray"
          "custom/wallpaper"
        ];
        modules-center = [
          "wlr/taskbar"
        ];
        modules-right = [
          "custom/usb"
          "network"
          "hyprland/language"
          "group/hardware"
          "custom/hyprsunset"
          "battery"
          "group/audio"
          "custom/power-menu"
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
          interval = 60;
          align = 0;
          rotate = 0;
          full-at = 100;
          design-capacity = false;
          states = {
            good = 95;
            warning = 30;
            critical = 15;
          };
          format = "{icon}  {capacity}%";
          format-charging = "󰂄 {capacity}%";
          format-plugged = " {capacity}%";
          format-full = "{icon} Full";
          format-alt = "{icon} {time}";
          format-icons = [
            "󰂎"
            "󰁺"
            "󰁻"
            "󰁼"
            "󰁽"
          ];
          format-time = "{H}h {M}min";
          tooltip = true;
        };

        # Taskbar
        "wlr/taskbar" = {
          format = "{icon}";
          icon-size = 28;
          all-outputs = true;
          tooltip-format = "{title}";
          on-click = "activate";
          on-click-middle = "close";
        };

        # Network module
        network = {
          tooltip-format-ethernet = "{ifname}  {ipaddr}/{cidr}";
          tooltip-format-wifi = "{essid} ({signalStrength}%)";
          interval = 2;
          on-click-right = "foot nmtui";
          format = "{}";
          format-alt-click = "click";
          format-alt = "  {ifname} | {ipaddr}/{cidr} | {gwaddr} {essid}";
          format-disconnected = "Disconnected";
          format-wifi = " {bandwidthDownBytes}  {bandwidthUpBytes} ";
          format-ethernet = " {bandwidthDownBytes}  {bandwidthUpBytes} 󰈁";
        };

        # Language switcher
        "hyprland/language" = {
          format = "{}";
          format-en = "En";
          format-he = "He";
          on-click = "hyprctl switchxkblayout next";
        };

        # Idle inhibitor
        idle_inhibitor = {
          format = "{icon}";
          format-icons = {
            activated = "󰅶";
            deactivated = "󰾪";
          };
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

        "custom/launcher" = {
          format = "   ";
          on-click = "${pkgs.writeShellScript "launcher" ''
            walker
          ''}";
        };

        # "custom/wallpaper" = {
        #   format = " 󰸉 ";
        #   on-click = "${pkgs.writeShellScript "wallpaper-menu" ''
        #     if command -v rofi >/dev/null 2>&1; then
        #       rofi -show filebrowser -filebrowser-directory ~/Pictures/wallpapers
        #     else
        #       echo "No wallpaper selector available"
        #     fi
        #   ''}";
        # };

        "custom/usb" = {
          format = "";
          tooltip = false;
          on-click = "${pkgs.writeShellScript "usb-eject" ''
            # Simple USB ejection script
            devices=$(lsblk -rno NAME,TRAN | awk '$2=="usb" {print "/dev/" $1}')
            if [ -n "$devices" ]; then
              device=$(echo "$devices" | walker -d -p "Eject USB:")
              if [ -n "$device" ]; then
                udisksctl unmount -b "$device" && udisksctl power-off -b "$device"
              fi
            else
              notify-send "No USB devices found"
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
          format = "{icon} {}";
          format-icons = {
            notification = "<span foreground='red'><sup>󰂞 </sup></span>";
            none = "󰂚";
            dnd-notification = "<span foreground='red'><sup>󰂠 </sup></span>";
            dnd-none = "󰂛";
            inhibited-notification = "<span foreground='red'><sup>󰂞 </sup></span>";
            inhibited-none = "󰂚";
            dnd-inhibited-notification = "<span foreground='red'><sup>󰂠 </sup></span>";
            dnd-inhibited-none = "󰂛";
          };
          return-type = "json";
          exec-if = "which swaync-client";
          exec = "swaync-client -swb";
          on-click = "sleep 0.1 && swaync-client -t -sw";
          on-click-right = "swaync-client -d -sw";
          escape = true;
        };

        "custom/hyprsunset" = {
          format = " 󰛨 ";
          on-click = "${pkgs.writeShellScript "toggle-blue-light" ''
            if command -v hyprctl >/dev/null 2>&1; then
              # Check if hyprsunset is currently active by checking the current state
              # If identity is active, enable temperature filter, otherwise disable
              current_state=$(hyprctl hyprsunset 2>/dev/null || echo "identity")
              if echo "$current_state" | grep -q "identity\|disabled"; then
                # Enable blue light filter (4000K temperature)
                hyprctl hyprsunset temperature 4000
                notify-send "Blue Light Filter" "Enabled (4000K)" -i display-brightness 2>/dev/null || true
              else
                # Disable blue light filter (reset to identity)
                hyprctl hyprsunset identity
                notify-send "Blue Light Filter" "Disabled" -i display-brightness 2>/dev/null || true
              fi
            else
              echo "hyprctl not available"
            fi
          ''}";
          tooltip = true;
          tooltip-format = "Toggle blue light filter (hyprsunset)";
        };
      }
    ];

    # Custom Catppuccin Macchiato styling
    style = ./style.css;
  };

  # Ensure required utilities are available
  home.packages = with pkgs; [
    # System monitoring
    btop

    # Audio utilities (if not already included)
    pavucontrol
    pulseaudio
    playerctl

    # Network utilities
    networkmanagerapplet

    # Screenshot utilities
    swappy

    # Notification daemon (if using swaync)
    # swaynotificationcenter
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

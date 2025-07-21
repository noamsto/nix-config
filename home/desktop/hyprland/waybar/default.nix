{pkgs, ...}: {
  programs.waybar = {
    enable = true;
    systemd.enable = false; # Disabled because using UWSM instead of systemd

    settings = [
      # Top Bar Config
      {
        name = "top_bar";
        layer = "top";
        position = "top";
        height = 36;
        spacing = 4;
        modules-left = ["hyprland/workspaces" "hyprland/submap"];
        modules-center = ["clock#simple"];
        modules-right = ["bluetooth" "network" "group/misc" "custom/logout_menu"];

        "hyprland/workspaces" = {
          on-click = "activate";
          format = "{icon}";
          format-icons = {
            "1" = "󰲠";
            "2" = "󰲢";
            "3" = "󰲤";
            "4" = "󰲦";
            "5" = "󰲨";
            "6" = "󰲪";
            "7" = "󰲬";
            "8" = "󰲮";
            "9" = "󰲰";
            "special" = "";
          };
          show-special = true;
          persistent-workspaces = {
            "*" = [1 2 3 4 5 6 7 8 9 10];
          };
          sort-by-number = true;
          all-outputs = false;
        };

        "hyprland/submap" = {
          format = "<span color='#a6da95'>Mode:</span> {}";
          tooltip = false;
        };

        "clock#simple" = {
          format = "{:%H:%M %Y-%m-%d}";
          tooltip-format = "<tt><small>{calendar}</small></tt>";
          actions = {
            on-click-right = "mode";
          };
          calendar = {
            mode = "month";
            mode-mon-col = 3;
            weeks-pos = "right";
            on-scroll = 1;
            on-click-right = "mode";
            format = {
              months = "<span color='#f4dbd6'><b>{}</b></span>";
              days = "<span color='#cad3f5'><b>{}</b></span>";
              weeks = "<span color='#c6a0f6'><b>W{}</b></span>";
              weekdays = "<span color='#a6da95'><b>{}</b></span>";
              today = "<span color='#8bd5ca'><b><u>{}</u></b></span>";
            };
          };
        };

        "custom/media" = {
          format = "{icon}󰎈";
          restart-interval = 2;
          return-type = "json";
          format-icons = {
            Playing = "";
            Paused = "";
          };
          max-length = 35;
          exec = "${pkgs.writeShellScript "fetch_music_player_data" ''            #!/bin/bash
            playerctl -a metadata --format "{\"text\": \"{{artist}} - {{markup_escape(title)}}\", \"tooltip\": \"<i><span color='#a6da95'>{{playerName}}</span></i>: <b><span color='#f5a97f'>{{artist}}</span> - <span color='#c6a0f6'>{{markup_escape(title)}}</span></b>\", \"alt\": \"{{status}}\", \"class\": \"{{status}}\"}" -F
          ''}";
          on-click = "playerctl play-pause";
          on-click-right = "playerctl next";
          on-click-middle = "playerctl prev";
          on-scroll-up = "playerctl volume 0.05-";
          on-scroll-down = "playerctl volume 0.05+";
          smooth-scrolling-threshold = "0.1";
        };

        bluetooth = {
          format = "󰂯";
          format-disabled = "󰂲";
          format-connected = "󰂱 {device_alias}";
          format-connected-battery = "󰂱 {device_alias} (󰥉 {device_battery_percentage}%)";
          tooltip-format = "{controller_alias}\t{controller_address} ({status})\n\n{num_connections} connected";
          tooltip-format-disabled = "bluetooth off";
          tooltip-format-connected = "{controller_alias}\t{controller_address} ({status})\n\n{num_connections} connected\n\n{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
          tooltip-format-enumerate-connected-battery = "{device_alias}\t{device_address}\t({device_battery_percentage}%)";
          max-length = 35;
          on-click = "system-toggles bluetooth";
          on-click-right = "overskride";
        };

        network = {
          format = "󰤭 ";
          format-wifi = "{icon} ({signalStrength}%) {essid}";
          format-icons = ["󰤯 " "󰤟 " "󰤢 " "󰤥 " "󰤨 "];
          format-disconnected = "󰤫  Disconnected";
          tooltip-format = "wifi <span color='#ee99a0'>off</span>";
          tooltip-format-wifi = "SSID: {essid}({signalStrength}%), {frequency} MHz\nInterface: {ifname}\nIP: {ipaddr}\nGW: {gwaddr}\n\n<span color='#a6da95'>{bandwidthUpBits}</span>\t<span color='#ee99a0'>{bandwidthDownBits}</span>\t<span color='#c6a0f6'>󰹹 {bandwidthTotalBits}</span>";
          tooltip-format-disconnected = "<span color='#ed8796'>disconnected</span>";
          max-length = 35;
          on-click = "system-toggles wifi";
          on-click-right = "iwgtk";
        };

        "group/misc" = {
          orientation = "horizontal";
          modules = [
            "custom/webcam"
            "privacy"
            "custom/recording"
            "custom/geo"
            "custom/dunst"
            "custom/night_mode"
            "custom/airplane_mode"
            "idle_inhibitor"
          ];
        };

        "custom/webcam" = {
          interval = 1;
          exec = "${pkgs.writeShellScript "check_webcam" ''
            #!/bin/bash
            if pgrep -x "mpv" > /dev/null || lsof /dev/video0 2>/dev/null | grep -q .; then
                echo '{"text": "󱚡 ", "tooltip": "webcam active", "class": "on"}'
            else
                echo '{"text": "", "tooltip": "webcam inactive", "class": "off"}'
            fi
          ''}";
          return-type = "json";
        };

        privacy = {
          icon-spacing = 1;
          icon-size = 12;
          transition-duration = 250;
          modules = [
            {
              type = "audio-in";
            }
            {
              type = "screenshare";
            }
          ];
        };

        "custom/recording" = {
          interval = 1;
          exec-if = "pgrep wl-screenrec";
          exec = "${pkgs.writeShellScript "check_recording" ''            #!/bin/bash
            if pgrep wl-screenrec > /dev/null; then
                echo '{"text": "󱞧", "tooltip": "recording active", "class": "on"}'
            else
                echo '{"text": "", "tooltip": "not recording", "class": "off"}'
            fi
          ''}";
          return-type = "json";
        };

        "custom/geo" = {
          interval = 1;
          exec-if = "pgrep geoclue";
          exec = "${pkgs.writeShellScript "check_geo_module" ''            #!/bin/bash
            if pgrep geoclue > /dev/null; then
                echo '{"text": "󰍒", "tooltip": "location services active", "class": "on"}'
            else
                echo '{"text": "", "tooltip": "location services inactive", "class": "off"}'
            fi
          ''}";
          return-type = "json";
        };

        "custom/airplane_mode" = {
          return-type = "json";
          interval = 1;
          exec = "${pkgs.writeShellScript "check_airplane_mode" ''            #!/bin/bash
            if [ -e ~/.cache/airplane_backup ]; then
                echo '{"text": "󰀞 ", "tooltip": "airplane mode on", "class": "on"}'
            else
                echo '{"text": "󰀝 ", "tooltip": "airplane mode off", "class": "off"}'
            fi
          ''}";
          on-click = "system-toggles airplane";
        };

        "custom/night_mode" = {
          return-type = "json";
          interval = 1;
          exec = "${pkgs.writeShellScript "check_night_mode" ''            #!/bin/bash
            # Check hyprsunset status via hyprctl
            # Try to apply identity (no filter) - if it succeeds, no filter was active
            if hyprctl hyprsunset identity >/dev/null 2>&1; then
                echo '{"text": "󱩕 ", "tooltip": "night mode off", "class": "off"}'
            else
                # If identity command fails, assume a filter is active
                echo '{"text": "󱩔 ", "tooltip": "night mode on", "class": "on"}'
            fi
          ''}";
          on-click = "system-toggles night-mode";
        };

        "custom/dunst" = {
          return-type = "json";
          exec = "${pkgs.writeShellScript "dunst_pause" ''            #!/bin/bash
            if dunstctl is-paused | grep -q true; then
                echo '{"text": "󰂛 ", "tooltip": "notifications paused", "class": "off"}'
            else
                echo '{"text": "󰂚 ", "tooltip": "notifications active", "class": "on"}'
            fi
          ''}";
          on-click = "dunstctl set-paused toggle";
          restart-interval = 1;
        };

        idle_inhibitor = {
          format = "{icon}";
          format-icons = {
            activated = "󰛐 ";
            deactivated = "󰛑 ";
          };
          tooltip-format-activated = "idle-inhibitor <span color='#a6da95'>on</span>";
          tooltip-format-deactivated = "idle-inhibitor <span color='#ee99a0'>off</span>";
          start-activated = true;
        };

        "custom/logout_menu" = {
          return-type = "json";
          exec = "echo '{\"text\":\"󰐥\", \"tooltip\": \"logout menu\"}'";
          interval = "once";
          on-click = "wlogout";
        };
      }

      # Bottom Bar Config
      {
        name = "bottom_bar";
        layer = "top";
        position = "bottom";
        height = 36;
        spacing = 4;
        modules-left = ["user"];
        modules-center = ["hyprland/window"];
        modules-right = ["keyboard-state" "hyprland/language"];

        "hyprland/window" = {
          format = "{title}";
          max-length = 50;
        };

        "hyprland/language" = {
          format-en = "🇺🇸 ENG";
          format-he = "🇮🇱 HEB";
          on-click = "hyprctl switchxkblayout next";
        };

        keyboard-state = {
          capslock = true;
          format = "{name} {icon}";
          format-icons = {
            locked = "󰌾";
            unlocked = "󰍀";
          };
        };

        user = {
          format = " <span color='#8bd5ca'>{user}</span> (up <span color='#f5bde6'>{work_d} d</span> <span color='#8aadf4'>{work_H} h</span> <span color='#eed49f'>{work_M} min</span> <span color='#a6da95'>↑</span>)";
          icon = true;
        };
      }

      # Left Bar Config
      {
        name = "left_bar";
        layer = "top";
        position = "left";
        spacing = 4;
        width = 64;
        margin-top = 10;
        margin-bottom = 10;
        modules-left = ["wlr/taskbar"];
        modules-center = ["cpu" "memory" "disk" "temperature" "battery" "backlight" "pulseaudio" "systemd-failed-units"];
        modules-right = ["tray"];

        "wlr/taskbar" = {
          format = "{icon}";
          icon-size = 20;
          icon-theme = "Numix-Circle";
          tooltip-format = "{title}";
          on-click = "activate";
          on-click-right = "close";
          on-click-middle = "fullscreen";
        };

        tray = {
          icon-size = 20;
          spacing = 2;
        };

        cpu = {
          format = "󰻠 {usage}%";
          states = {
            high = 90;
            upper-medium = 70;
            medium = 50;
            lower-medium = 30;
            low = 10;
          };
          on-click = "foot btop";
          on-click-right = "foot btop";
        };

        memory = {
          format = "󰍛 {percentage}%";
          tooltip-format = "Main: ({used} GiB/{total} GiB)({percentage}%), available {avail} GiB\nSwap: ({swapUsed} GiB/{swapTotal} GiB)({swapPercentage}%), available {swapAvail} GiB";
          states = {
            high = 90;
            upper-medium = 70;
            medium = 50;
            lower-medium = 30;
            low = 10;
          };
          on-click = "foot btop";
          on-click-right = "foot btop";
        };

        disk = {
          format = "󰋊 {percentage_used}%";
          tooltip-format = "({used}/{total})({percentage_used}%) in '{path}', available {free}({percentage_free}%)";
          states = {
            high = 90;
            upper-medium = 70;
            medium = 50;
            lower-medium = 30;
            low = 10;
          };
          on-click = "foot btop";
          on-click-right = "foot btop";
        };

        temperature = {
          tooltip = false;
          thermal-zone = 8;
          critical-threshold = 80;
          format = "{icon} {temperatureC}󰔄";
          format-critical = "🔥 {icon} {temperatureC}󰔄";
          format-icons = ["" "" "" "" ""];
        };

        battery = {
          states = {
            high = 90;
            upper-medium = 70;
            medium = 50;
            lower-medium = 30;
            low = 10;
          };
          format = "{icon} {capacity}%";
          format-charging = "󱐋{icon} {capacity}%";
          format-plugged = "󰚥{icon} {capacity}%";
          format-time = "{H} h {M} min";
          format-icons = ["󱃍" "󰁺" "󰁻" "󰁼" "󰁽" "󰁾" "󰁿" "󰂀" "󰂁" "󰂂" "󰁹"];
          tooltip-format = "{timeTo}";
        };

        backlight = {
          format = "{icon} {percent}%";
          format-icons = [
            "󰌶"
            "󱩎"
            "󱩏"
            "󱩐"
            "󱩑"
            "󱩒"
            "󱩓"
            "󱩔"
            "󱩕"
            "󱩖"
            "󰛨"
          ];
          tooltip = false;
          states = {
            high = 90;
            upper-medium = 70;
            medium = 50;
            lower-medium = 30;
            low = 10;
          };
          reverse-scrolling = true;
          reverse-mouse-scrolling = true;
        };

        pulseaudio = {
          states = {
            high = 90;
            upper-medium = 70;
            medium = 50;
            lower-medium = 30;
            low = 10;
          };
          tooltip-format = "{desc}";
          format = "{icon} {volume}%\n{format_source}";
          format-bluetooth = "󰂱 {icon} {volume}%\n{format_source}";
          format-bluetooth-muted = "󰂱 󰝟 {volume}%\n{format_source}";
          format-muted = "󰝟 {volume}%\n{format_source}";
          format-source = "󰍬 {volume}%";
          format-source-muted = "󰍭 {volume}%";
          format-icons = {
            headphone = "󰋋";
            hands-free = "";
            headset = "󰋎";
            phone = "󰄜";
            portable = "󰦧";
            car = "󰄋";
            speaker = "󰓃";
            hdmi = "󰡁";
            hifi = "󰋌";
            default = [
              "󰕿"
              "󰖀"
              "󰕾"
            ];
          };
          reverse-scrolling = true;
          reverse-mouse-scrolling = true;
          on-click = "pavucontrol";
        };

        "systemd-failed-units" = {
          format = "✗  {nr_failed}";
        };
      }
    ];

    # Custom Catppuccin Macchiato styling (matching reference)
    style = ./style.css;
  };

  # Ensure hyprsunset and related utilities are available
  home.packages = with pkgs; [
    swappy # For screenshot editing (optional but useful)
    btop # System monitor
  ];

  # Create macchiato.css file for waybar theming
  xdg.configFile."waybar/macchiato.css" = {
    text = ''
      /*
      *
      * Catppuccin Macchiato palette
      * Maintainer: rubyowo
      *
      */

      @define-color base   #24273a;
      @define-color mantle #1e2030;
      @define-color crust  #181926;

      @define-color text     #cad3f5;
      @define-color subtext0 #a5adcb;
      @define-color subtext1 #b8c0e0;

      @define-color surface0 #363a4f;
      @define-color surface1 #494d64;
      @define-color surface2 #5b6078;

      @define-color overlay0 #6e738d;
      @define-color overlay1 #8087a2;
      @define-color overlay2 #939ab7;

      @define-color blue      #8aadf4;
      @define-color lavender  #b7bdf8;
      @define-color sapphire  #7dc4e4;
      @define-color sky       #91d7e3;
      @define-color teal      #8bd5ca;
      @define-color green     #a6da95;
      @define-color yellow    #eed49f;
      @define-color peach     #f5a97f;
      @define-color maroon    #ee99a0;
      @define-color red       #ed8796;
      @define-color mauve     #c6a0f6;
      @define-color pink      #f5bde6;
      @define-color flamingo  #f0c6c6;
      @define-color rosewater #f4dbd6;
    '';
  };
}

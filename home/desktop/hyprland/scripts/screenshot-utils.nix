{pkgs, ...}: {
  home.packages = [
    # Screenshot edit script (complementary to grimblast)
    (pkgs.writeShellScriptBin "screenshot-edit" ''
      #!/bin/bash
      set -euo pipefail

      screenshot_dir="$HOME/Pictures/Screenshots"

      if [ ! -d "$screenshot_dir" ]; then
          dunstify -i dialog-error "Screenshot" "Screenshots directory not found" -t 2000
          exit 1
      fi

      # Get the most recent screenshot
      latest_file=$(find "$screenshot_dir" -name "*.png" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)

      if [ -z "$latest_file" ]; then
          dunstify -i dialog-error "Screenshot" "No screenshots found to edit" -t 2000
          exit 1
      fi

      # Open in swappy for editing (requires swappy package)
      if command -v swappy >/dev/null 2>&1; then
          swappy -f "$latest_file"
      else
          # Fallback to image viewer
          xdg-open "$latest_file"
      fi
    '')

    # Screen recording scripts
    (pkgs.writeShellScriptBin "record-screen-mp4" ''
      #!/bin/bash
      set -euo pipefail

      target_process="wl-screenrec"
      record_dir="$HOME/Pictures/Records"
      mkdir -p "$record_dir"

      if pgrep "$target_process" > /dev/null; then
          # Stop recording
          killall -s SIGINT "$target_process"
          dunstify -i media-record \
                   -r 1001 \
                   "Recording Stopped" \
                   "Screen recording saved" \
                   -t 2000
      else
          # Start recording
          geometry=$(slurp 2>/dev/null)
          if [ -n "$geometry" ]; then
              timestamp=$(date +"%Y-%m-%d--%H:%M:%S")
              record_name="record-$timestamp"

              dunstify -i media-record \
                       -r 1001 \
                       "Recording Started" \
                       "Recording screen region..." \
                       -t 2000

              wl-screenrec -g "$geometry" \
                          -f "$record_dir/$record_name.mp4" \
                          --encode-resolution 1920x1080 &
          fi
      fi
    '')

    (pkgs.writeShellScriptBin "record-screen-gif" ''
      #!/bin/bash
      set -euo pipefail

      target_process="wl-screenrec"
      record_dir="$HOME/Pictures/Records"
      mkdir -p "$record_dir"

      if pgrep "$target_process" > /dev/null; then
          # Stop recording and convert to GIF
          killall -s SIGINT "$target_process"

          # Wait for the process to fully stop
          sleep 1

          # Find the most recent MP4 file
          latest_mp4=$(find "$record_dir" -name "*.mp4" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)

          if [ -n "$latest_mp4" ] && [ -f "$latest_mp4" ]; then
              gif_file="''${latest_mp4%.mp4}.gif"

              # Convert to GIF with optimization
              ffmpeg -i "$latest_mp4" \
                     -vf "fps=15,scale=1024:-1:flags=lanczos,palettegen" \
                     -y "/tmp/palette.png"

              ffmpeg -i "$latest_mp4" -i "/tmp/palette.png" \
                     -filter_complex "fps=15,scale=1024:-1:flags=lanczos[x];[x][1:v]paletteuse" \
                     -y "$gif_file"

              # Clean up
              rm -f "$latest_mp4" "/tmp/palette.png"

              # Copy to clipboard and notify
              wl-copy -t text/uri-list "file://$gif_file"
              dunstify -i media-record \
                       -r 1001 \
                       "Recording Stopped" \
                       "GIF created and copied to clipboard" \
                       -t 2000
          fi
      else
          # Start recording
          geometry=$(slurp 2>/dev/null)
          if [ -n "$geometry" ]; then
              timestamp=$(date +"%Y-%m-%d--%H:%M:%S")
              record_name="record-$timestamp"

              dunstify -i media-record \
                       -r 1001 \
                       "Recording Started (GIF)" \
                       "Recording screen region for GIF..." \
                       -t 2000

              wl-screenrec -g "$geometry" \
                          -f "$record_dir/$record_name.mp4" \
                          --encode-resolution 1024x768 &
          fi
      fi
    '')

    # Clipboard management utilities
    (pkgs.writeShellScriptBin "clipboard-manager" ''
      #!/bin/bash
      set -euo pipefail

      case "''${1:-show}" in
          "clear")
              cliphist wipe
              dunstify -i edit-clear "Clipboard" "Clipboard history cleared" -t 1500
              ;;
          "delete")
              # Interactive delete with rofi
              cliphist list | rofi -dmenu -p "Delete item" | cliphist delete
              ;;
          "show"|*)
              # Show clipboard history
              cliphist list | rofi -dmenu -p "Clipboard" | cliphist decode | wl-copy
              ;;
      esac
    '')

    # System toggles
    (pkgs.writeShellScriptBin "system-toggles" ''
      #!/bin/bash
      set -euo pipefail

      case "''${1:-menu}" in
          "wifi")
              wifi_status=$(rfkill list wifi | grep -i -o "Soft blocked: yes" || echo "")
              if [ -z "$wifi_status" ]; then
                  rfkill block wifi
                  dunstify -i network-wireless-offline "WiFi" "WiFi disabled" -t 1500
              else
                  rfkill unblock wifi
                  dunstify -i network-wireless-signal-excellent "WiFi" "WiFi enabled" -t 1500
              fi
              ;;
          "bluetooth")
              bt_status=$(rfkill list bluetooth | grep -i -o "Soft blocked: yes" || echo "")
              if [ -z "$bt_status" ]; then
                  rfkill block bluetooth
                  dunstify -i bluetooth-disabled "Bluetooth" "Bluetooth disabled" -t 1500
              else
                  rfkill unblock bluetooth
                  dunstify -i bluetooth "Bluetooth" "Bluetooth enabled" -t 1500
              fi
              ;;
          "night-mode")
              # Control hyprsunset via hyprctl commands
              # Check current state and toggle
              if hyprctl hyprsunset identity >/dev/null 2>&1; then
                  dunstify -i weather-clear "Night Mode" "Night mode disabled" -t 1500
              else
                  # Apply 3000K temperature filter
                  hyprctl hyprsunset temperature 3000 >/dev/null 2>&1
                  dunstify -i weather-clear-night "Night Mode" "Night mode enabled (3000K)" -t 1500
              fi
              ;;
          "airplane")
              backup_file="$HOME/.cache/airplane_backup"
              if [ -e "$backup_file" ]; then
                  # Restore from airplane mode
                  rfkill unblock wifi bluetooth
                  rm -f "$backup_file"
                  dunstify -i airplane-mode-off "Airplane Mode" "Airplane mode disabled" -t 1500
              else
                  # Enable airplane mode
                  touch "$backup_file"
                  rfkill block wifi bluetooth
                  dunstify -i airplane-mode "Airplane Mode" "Airplane mode enabled" -t 1500
              fi
              ;;
          "menu"|*)
              # Show toggle menu
              choice=$(echo -e "WiFi Toggle\nBluetooth Toggle\nNight Mode\nAirplane Mode" | \
                      rofi -dmenu -p "System Toggles")
              case "$choice" in
                  "WiFi Toggle") system-toggles wifi ;;
                  "Bluetooth Toggle") system-toggles bluetooth ;;
                  "Night Mode") system-toggles night-mode ;;
                  "Airplane Mode") system-toggles airplane ;;
              esac
              ;;
      esac
    '')
  ];
}

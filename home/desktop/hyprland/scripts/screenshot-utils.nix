{pkgs, ...}: {
  home.packages = [
    # Screenshot edit script (complementary to grimblast)
    (pkgs.writeShellScriptBin "screenshot-edit" ''
      #!/bin/bash
      set -euo pipefail

      screenshot_dir="$HOME/Pictures/Screenshots"

      if [ ! -d "$screenshot_dir" ]; then
          notify-send -i dialog-error "Screenshot" "Screenshots directory not found" -t 2000
          exit 1
      fi

      # Get the most recent screenshot
      latest_file=$(find "$screenshot_dir" -name "*.png" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)

      if [ -z "$latest_file" ]; then
          notify-send -i dialog-error "Screenshot" "No screenshots found to edit" -t 2000
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
      record_type_file="$HOME/.cache/current_record_type"
      mkdir -p "$record_dir"

      if pgrep -x "$target_process" > /dev/null; then
          # Check if this is an MP4 recording
          if [ -f "$record_type_file" ] && [ "$(cat "$record_type_file")" = "mp4" ]; then
              # Stop recording
              pkill -SIGINT -x "$target_process"
              rm -f "$record_type_file"

              # Show processing notification with unique ID
              notify-send -i media-record \
                       -h string:x-canonical-private-synchronous:recording-mp4 \
                       "Recording Stopped" \
                       "Processing MP4..." \
                       -t 0

              # Wait for file to be written
              sleep 1

              # Find the most recent MP4 and show completion
              latest_mp4=$(find "$record_dir" -name "*.mp4" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)
              if [ -n "$latest_mp4" ]; then
                  filename=$(basename "$latest_mp4")

                  notify-send -i media-record \
                           -h string:x-canonical-private-synchronous:recording-mp4 \
                           "Recording Complete" \
                           "MP4 saved: $filename" \
                           -t 3000
              fi
          fi
      else
          # Start recording with grimblast-like smart selection
          # Get active window geometry as default
          active_geometry=$(hyprctl -j activewindow | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' 2>/dev/null)

          # Show selection menu
          if [ -n "$active_geometry" ] && [ "$active_geometry" != "null,null 0x0" ]; then
              selection=$(printf "Active Window\nSelect Area" | walker --dmenu -p "Record")
              case "$selection" in
                  "Active Window")
                      geometry="$active_geometry"
                      ;;
                  "Select Area")
                      geometry=$(slurp 2>/dev/null)
                      ;;
                  *)
                      exit 0
                      ;;
              esac
          else
              # No active window, go straight to area selection
              geometry=$(slurp 2>/dev/null)
          fi

          if [ -n "$geometry" ]; then
              timestamp=$(date +"%Y-%m-%d--%H:%M:%S")
              record_name="record-$timestamp"

              # Mark this as MP4 recording
              echo "mp4" > "$record_type_file"

              notify-send -i media-record \
                       -h string:x-canonical-private-synchronous:recording-mp4 \
                       "🔴 Recording MP4" \
                       "Press Super+Shift+R to stop recording" \
                       -t 0

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
      record_type_file="$HOME/.cache/current_record_type"
      mkdir -p "$record_dir"

      if pgrep -x "$target_process" > /dev/null; then
          # Check if this is a GIF recording
          if [ -f "$record_type_file" ] && [ "$(cat "$record_type_file")" = "gif" ]; then
              # Stop recording and convert to GIF
              pkill -SIGINT -x "$target_process"
              rm -f "$record_type_file"

              # Show processing notification with unique ID
              notify-send -i media-record \
                       -h string:x-canonical-private-synchronous:recording-gif \
                       "Recording Stopped" \
                       "Processing GIF..." \
                       -t 0

              # Wait for the process to fully stop
              sleep 2

              # Ensure process is really stopped
              while pgrep -x "$target_process" > /dev/null; do
                sleep 0.5
              done

              # Find the most recent MP4 file
              latest_mp4=$(find "$record_dir" -name "*.mp4" -type f -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-)

              if [ -n "$latest_mp4" ] && [ -f "$latest_mp4" ]; then
                  gif_file="''${latest_mp4%.mp4}.gif"
                  filename=$(basename "$gif_file")

                  # Update notification for conversion step
                  notify-send -i media-record \
                           -h string:x-canonical-private-synchronous:recording-gif \
                           "Processing GIF" \
                           "Converting to optimized GIF..." \
                           -t 0

                  # Convert to GIF with optimization (hide ffmpeg output)
                  ffmpeg -i "$latest_mp4" \
                         -vf "fps=15,scale=1024:-1:flags=lanczos,palettegen" \
                         -y "/tmp/palette.png" \
                         -v quiet

                  ffmpeg -i "$latest_mp4" -i "/tmp/palette.png" \
                         -filter_complex "fps=15,scale=1024:-1:flags=lanczos[x];[x][1:v]paletteuse" \
                         -y "$gif_file" \
                         -v quiet

                  # Clean up
                  rm -f "$latest_mp4" "/tmp/palette.png"

                  # Copy to clipboard and show completion
                  wl-copy -t text/uri-list "file://$gif_file"
                  notify-send -i media-record \
                           -h string:x-canonical-private-synchronous:recording-gif \
                           "GIF Complete" \
                           "GIF created and copied to clipboard: $filename" \
                           -t 3000
              else
                  # Error notification
                  notify-send -i dialog-error \
                           -h string:x-canonical-private-synchronous:recording-gif \
                           "Recording Error" \
                           "Failed to process GIF" \
                           -t 3000
              fi
          fi
      else
          # Start recording with grimblast-like smart selection
          # Get active window geometry as default
          active_geometry=$(hyprctl -j activewindow | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' 2>/dev/null)

          # Show selection menu
          if [ -n "$active_geometry" ] && [ "$active_geometry" != "null,null 0x0" ]; then
              selection=$(printf "Active Window\nSelect Area" | walker --dmenu -p "Record")
              case "$selection" in
                  "Active Window")
                      geometry="$active_geometry"
                      ;;
                  "Select Area")
                      geometry=$(slurp 2>/dev/null)
                      ;;
                  *)
                      exit 0
                      ;;
              esac
          else
              # No active window, go straight to area selection
              geometry=$(slurp 2>/dev/null)
          fi

          if [ -n "$geometry" ]; then
              timestamp=$(date +"%Y-%m-%d--%H:%M:%S")
              record_name="record-$timestamp"

              # Mark this as GIF recording
              echo "gif" > "$record_type_file"

              notify-send -i media-record \
                       -h string:x-canonical-private-synchronous:recording-gif \
                       "🔴 Recording GIF" \
                       "Press Alt+Shift+R to stop recording" \
                       -t 0

              wl-screenrec -g "$geometry" \
                          -f "$record_dir/$record_name.mp4" \
                          --encode-resolution 1024x768 &
          fi
      fi
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
                  notify-send -i network-wireless-offline "WiFi" "WiFi disabled" -t 1500
              else
                  rfkill unblock wifi
                  notify-send -i network-wireless-signal-excellent "WiFi" "WiFi enabled" -t 1500
              fi
              ;;
          "bluetooth")
              bt_status=$(rfkill list bluetooth | grep -i -o "Soft blocked: yes" || echo "")
              if [ -z "$bt_status" ]; then
                  rfkill block bluetooth
                  notify-send -i bluetooth-disabled "Bluetooth" "Bluetooth disabled" -t 1500
              else
                  rfkill unblock bluetooth
                  notify-send -i bluetooth "Bluetooth" "Bluetooth enabled" -t 1500
              fi
              ;;
          "night-mode")
              # Control hyprsunset via hyprctl commands
              # Check current state and toggle
              if hyprctl hyprsunset identity >/dev/null 2>&1; then
                  notify-send -i weather-clear "Night Mode" "Night mode disabled" -t 1500
              else
                  # Apply 3000K temperature filter
                  hyprctl hyprsunset temperature 3000 >/dev/null 2>&1
                  notify-send -i weather-clear-night "Night Mode" "Night mode enabled (3000K)" -t 1500
              fi
              ;;
          "airplane")
              backup_file="$HOME/.cache/airplane_backup"
              if [ -e "$backup_file" ]; then
                  # Restore from airplane mode
                  rfkill unblock wifi bluetooth
                  rm -f "$backup_file"
                  notify-send -i airplane-mode-off "Airplane Mode" "Airplane mode disabled" -t 1500
              else
                  # Enable airplane mode
                  touch "$backup_file"
                  rfkill block wifi bluetooth
                  notify-send -i airplane-mode "Airplane Mode" "Airplane mode enabled" -t 1500
              fi
              ;;
          "menu"|*)
              # Show toggle menu
              choice=$(echo -e "WiFi Toggle\nBluetooth Toggle\nNight Mode\nAirplane Mode" | \
                      walker --dmenu -p "System Toggles")
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

#!/bin/bash
# Area screenshot: copy to the clipboard, then offer Edit in the notification
set -euo pipefail

dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
mkdir -p "$dir"
file="$dir/screenshot-$(date +%Y-%m-%d_%H-%M-%S).png"

# save, not edit: edit keeps hyprpicker's freeze up until the editor closes
grimblast --freeze save area "$file" || exit 1
wl-copy --type image/png <"$file"

action=$(notify-send --app-name=Screenshot --icon="$file" \
  --action=edit=Edit "Screenshot copied" "${file/#$HOME/\~}")
[ "$action" = edit ] || exit 0
satty --filename "$file"

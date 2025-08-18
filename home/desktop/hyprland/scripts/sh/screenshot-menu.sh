#!/bin/bash
set -euo pipefail

# Screenshot menu using walker with grimblast
# Provides different screenshot modes with satty integration

# Define screenshot options with icons
options="📋 Select Area/Window\n🖥️ Current Output\n🖼️ All Screens\n⏰ Delay Output (3s)\n⏰ Delay All Screens (3s)"

# Show walker menu and get selection
choice=$(echo -e "$options" | walker -d)

case "$choice" in
"📋 Select Area/Window")
  GRIMBLAST_EDITOR='satty -f' grimblast edit area
  ;;
"🖥️ Current Output")
  GRIMBLAST_EDITOR='satty -f' grimblast edit output
  ;;
"🖼️ All Screens")
  GRIMBLAST_EDITOR='satty -f' grimblast edit screen
  ;;
"⏰ Delay Output (3s)")
  GRIMBLAST_EDITOR='satty -f' grimblast --wait 3 edit output
  ;;
"⏰ Delay All Screens (3s)")
  GRIMBLAST_EDITOR='satty -f' grimblast --wait 3 edit screen
  ;;
esac

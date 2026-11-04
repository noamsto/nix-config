#!/bin/bash
# Wrapper for grimblast that saves screenshot and opens satty
# Uses 'save' instead of 'edit' to avoid keeping hyprpicker frozen

set -euo pipefail

# Use grimblast save (which kills hyprpicker after screenshot)
# instead of edit (which keeps it running until editor closes)
TEMP_FILE="/tmp/grimblast-$(date +%Y%m%d_%H%M%S).png"

# Take screenshot with freeze - grimblast save kills hyprpicker immediately
grimblast --freeze save area "$TEMP_FILE" || exit 1

# Now open in satty (screen is unfrozen at this point)
satty --filename "$TEMP_FILE"

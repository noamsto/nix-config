#!/bin/bash

# Hyprland Quickshell Bar Installation Script

set -e

echo \"🚀 Installing Hyprland Quickshell Bar...\"

# Check if quickshell is installed
if ! command -v quickshell &> /dev/null; then
    echo \"❌ Quickshell is not installed. Please install it first.\"
    exit 1
fi

# Check if NetworkManager is available
if ! command -v nmcli &> /dev/null; then
    echo \"⚠️  NetworkManager (nmcli) not found. Network status may not work.\"
fi

# Check if UPower is available
if ! command -v upower &> /dev/null; then
    echo \"⚠️  UPower not found. Battery status will use basic sysfs method.\"
fi

# Check if systemctl is available
if ! command -v systemctl &> /dev/null; then
    echo \"❌ systemctl not found. Power management will not work.\"
    exit 1
fi

# Check for required directories
HYPR_CONFIG_DIR=\"$HOME/.config/hypr\"
QUICKSHELL_DIR=\"$HYPR_CONFIG_DIR/quickshell\"

if [ ! -d \"$HYPR_CONFIG_DIR\" ]; then
    echo \"❌ Hyprland config directory not found at $HYPR_CONFIG_DIR\"
    exit 1
fi

# Create quickshell directory if it doesn't exist
if [ ! -d \"$QUICKSHELL_DIR\" ]; then
    mkdir -p \"$QUICKSHELL_DIR\"
    echo \"📁 Created quickshell directory at $QUICKSHELL_DIR\"
fi

# Copy files (this assumes the script is run from the quickshell directory)
SCRIPT_DIR=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")\" && pwd)\"

echo \"📋 Copying quickshell bar files...\"
cp -r \"$SCRIPT_DIR\"/* \"$QUICKSHELL_DIR/\"

# Make the script executable
chmod +x \"$QUICKSHELL_DIR/install.sh\"

echo \"✅ Installation complete!\"
echo \"\"
echo \"📝 Next steps:\"
echo \"1. Add the following to your Hyprland config (~/.config/hypr/hyprland.conf):\"
echo \"   exec-once = quickshell -c ~/.config/hypr/quickshell/shell.qml\"
echo \"\"
echo \"2. Restart Hyprland or run:\"
echo \"   quickshell -c ~/.config/hypr/quickshell/shell.qml\"
echo \"\"
echo \"3. Test the services with:\"
echo \"   quickshell -c ~/.config/hypr/quickshell/test_services.qml\"
echo \"\"
echo \"📖 See README.md for more configuration options.\"
"


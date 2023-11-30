#!/usr/bin/env bash

# initialize wallpaper daemon
swww init &

# Set wallpaper
# swww img ~/Wallpapers/gruvbox-mountain-village.png &

# Network applet
nm-applet --indicator &

# top bar
waybar &

dunst


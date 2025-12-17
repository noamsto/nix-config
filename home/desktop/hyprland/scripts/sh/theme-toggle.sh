#!/usr/bin/env bash
# Theme toggle script - switches between dark and light themes at runtime
#
# Dynamic switching (instant):
# - GTK apps via dconf color-scheme (Adwaita theme respects this)
# - Hyprland border colors via hyprctl
# - Kitty terminal via remote control (set-colors)
# - Tmux via catppuccin flavor + config reload
# - Waybar via colors.css swap + reload
# - Swaync via CSS concatenation + reload
# - Vicinae via config JSON + server restart
#
# Requires app restart:
# - Qt/Kvantum apps (Dolphin, etc.)
# - KDE apps (KDE Connect) via kdeglobals
# - btop, yazi, lazygit, k9s (pick up theme on next start)

set -euo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_FILE="$STATE_DIR/theme-mode"

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Catppuccin colors for Hyprland borders
MOCHA_BLUE="89b4fa"
MOCHA_LAVENDER="b4befe"
LATTE_BLUE="1e66f5"
LATTE_LAVENDER="7287fd"

# Read current state (default to dark)
get_current_theme() {
  if [[ -f $STATE_FILE ]]; then
    cat "$STATE_FILE"
  else
    echo "dark"
  fi
}

# Update dconf for GTK apps (immediate effect via portal)
update_gtk_theme() {
  local theme="$1"
  # Use dconf directly as gsettings may fail to find schemas in wrapped scripts
  if [[ $theme == "light" ]]; then
    dconf write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
    dconf write /org/gnome/desktop/interface/icon-theme "'Papirus-Light'"
  else
    dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
    dconf write /org/gnome/desktop/interface/icon-theme "'Papirus-Dark'"
  fi
}

# Update Hyprland border colors
update_hyprland_borders() {
  local theme="$1"
  if [[ $theme == "light" ]]; then
    hyprctl keyword general:col.active_border "rgba(${LATTE_BLUE}ee) rgba(${LATTE_LAVENDER}ee) 45deg" >/dev/null
    hyprctl keyword general:col.inactive_border "rgba(${LATTE_LAVENDER}40)" >/dev/null
  else
    hyprctl keyword general:col.active_border "rgba(${MOCHA_BLUE}ee) rgba(${MOCHA_LAVENDER}ee) 45deg" >/dev/null
    hyprctl keyword general:col.inactive_border "rgba(${MOCHA_LAVENDER}40)" >/dev/null
  fi
}

# Update kitty terminal theme (all running instances)
update_kitty() {
  local theme="$1"
  local kitty_theme
  if [[ $theme == "light" ]]; then
    kitty_theme="Catppuccin-Latte"
  else
    kitty_theme="Catppuccin-Mocha"
  fi
  # Theme path is set by Nix wrapper via KITTY_THEMES_PATH
  local theme_file="${KITTY_THEMES_PATH}/${kitty_theme}.conf"
  if [[ -f $theme_file ]]; then
    # Update all kitty instances via their sockets (socket has PID suffix)
    for sock in /tmp/kitty-*; do
      [[ -S $sock ]] && kitty @ --to "unix:$sock" set-colors --all "$theme_file" 2>/dev/null || true
    done
  fi
}

# Update tmux catppuccin flavor
update_tmux() {
  local theme="$1"
  local tmux_flavor
  if [[ $theme == "light" ]]; then
    tmux_flavor="latte"
  else
    tmux_flavor="mocha"
  fi
  # Check if tmux is running
  if tmux list-sessions &>/dev/null; then
    # Update the catppuccin flavor
    tmux set -g @catppuccin_flavor "$tmux_flavor" 2>/dev/null || true
    # Re-source the full config to pick up new @thm_* variables
    # The catppuccin plugin sets variables, but status line formats need re-parsing
    tmux source-file ~/.config/tmux/tmux.conf 2>/dev/null || true
  fi
}

# Update Kvantum theme for Qt apps (requires app restart)
update_kvantum() {
  local theme="$1"
  local kvantum_theme
  if [[ $theme == "light" ]]; then
    kvantum_theme="catppuccin-latte-blue"
  else
    kvantum_theme="catppuccin-mocha-blue"
  fi
  # Write directly to Kvantum config (kvantummanager is GUI only)
  local kvantum_config="${XDG_CONFIG_HOME:-$HOME/.config}/Kvantum/kvantum.kvconfig"
  mkdir -p "$(dirname "$kvantum_config")"
  cat >"$kvantum_config" <<EOF
[General]
theme=$kvantum_theme
EOF
}

# Update waybar colors
update_waybar() {
  local theme="$1"
  local colors_file
  if [[ $theme == "light" ]]; then
    colors_file="colors-latte.css"
  else
    colors_file="colors-mocha.css"
  fi
  # Copy the appropriate colors file (path set by Nix wrapper)
  if [[ -n ${WAYBAR_COLORS_DIR:-} && -f "${WAYBAR_COLORS_DIR}/${colors_file}" ]]; then
    cp "${WAYBAR_COLORS_DIR}/${colors_file}" "${WAYBAR_COLORS_DIR}/colors.css"
    # Signal waybar to reload its styles
    pkill -SIGUSR2 waybar 2>/dev/null || true
  fi
}

# Update Vicinae theme (modify config + restart server)
update_vicinae() {
  local theme="$1"
  local vicinae_theme icon_theme
  local config_file="${HOME}/nix-config/home/desktop/hyprland/vicinae/vicinae-config.json"

  if [[ $theme == "light" ]]; then
    vicinae_theme="catppuccin-latte"
    icon_theme="Papirus-Light"
  else
    vicinae_theme="catppuccin-mocha"
    icon_theme="Papirus-Dark"
  fi

  # Update config file using jq
  if [[ -f $config_file ]] && command -v jq &>/dev/null; then
    local tmp_file="${config_file}.tmp"
    jq --arg theme "$vicinae_theme" --arg icons "$icon_theme" \
      '.theme.name = $theme | .theme.iconTheme = $icons' \
      "$config_file" >"$tmp_file" && mv "$tmp_file" "$config_file"

    # Restart vicinae server to pick up new config
    vicinae server 2>/dev/null || true
  fi
}

# Update swaync notification daemon CSS
update_swaync() {
  local theme="$1"
  local swaync_dir="${HOME}/nix-config/home/desktop/hyprland/swaync"
  local colors_file base_file style_file

  if [[ $theme == "light" ]]; then
    colors_file="${swaync_dir}/swaync-colors-latte.css"
  else
    colors_file="${swaync_dir}/swaync-colors-mocha.css"
  fi
  base_file="${swaync_dir}/swaync-style-base.css"
  style_file="${swaync_dir}/swaync-style.css"

  # Concatenate colors + base styles into the final style file
  if [[ -f $colors_file && -f $base_file ]]; then
    cat "$colors_file" "$base_file" >"$style_file"
  fi
}

# Update KDE color scheme for KDE apps (KDE Connect, etc.)
# Apps need restart to pick up changes
update_kde_colorscheme() {
  local theme="$1"
  local kdeglobals="${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals"

  if [[ $theme == "light" ]]; then
    # Catppuccin Latte colors
    cat >"$kdeglobals" <<'EOF'
[General]
ColorScheme=CatppuccinLatteBlue

[Colors:View]
BackgroundNormal=239,241,245
ForegroundNormal=76,79,105

[Colors:Window]
BackgroundNormal=230,233,239
ForegroundNormal=76,79,105

[Colors:Button]
BackgroundNormal=204,208,218
ForegroundNormal=76,79,105

[Colors:Selection]
BackgroundNormal=30,102,245
ForegroundNormal=239,241,245

[KDE]
LookAndFeelPackage=org.kde.breeze.desktop
EOF
  else
    # Catppuccin Mocha colors
    cat >"$kdeglobals" <<'EOF'
[General]
ColorScheme=CatppuccinMochaBlue

[Colors:View]
BackgroundNormal=30,30,46
ForegroundNormal=205,214,244

[Colors:Window]
BackgroundNormal=24,24,37
ForegroundNormal=205,214,244

[Colors:Button]
BackgroundNormal=49,50,68
ForegroundNormal=205,214,244

[Colors:Selection]
BackgroundNormal=137,180,250
ForegroundNormal=30,30,46

[KDE]
LookAndFeelPackage=org.kde.breezedark.desktop
EOF
  fi
}

# Signal apps to reload their themes
signal_apps() {
  # Swaync - reload CSS
  swaync-client --reload-css 2>/dev/null || true

  # Restart tray applets so they pick up new icon theme
  # nm-applet
  if pgrep -x nm-applet >/dev/null; then
    pkill -x nm-applet
    nohup nm-applet --indicator >/dev/null 2>&1 &
  fi
  # blueman-applet
  if pgrep -x blueman-applet >/dev/null; then
    pkill -x blueman-applet
    nohup blueman-applet >/dev/null 2>&1 &
  fi
}

# Main toggle function
toggle_theme() {
  local current
  current=$(get_current_theme)

  local new_theme
  if [[ $current == "dark" ]]; then
    new_theme="light"
  else
    new_theme="dark"
  fi

  # Save new state first (so waybar can read it)
  echo "$new_theme" >"$STATE_FILE"

  # Update dynamic components
  update_gtk_theme "$new_theme"
  update_hyprland_borders "$new_theme"
  update_kitty "$new_theme"
  update_tmux "$new_theme"
  update_kvantum "$new_theme"
  update_waybar "$new_theme"
  update_swaync "$new_theme"
  update_vicinae "$new_theme"
  update_kde_colorscheme "$new_theme"
  signal_apps

  # Notify user
  local icon
  if [[ $new_theme == "light" ]]; then
    icon="weather-clear"
  else
    icon="weather-clear-night"
  fi
  notify-send "Theme" "Switched to $new_theme mode" -i "$icon"
}

# Restore theme (called at login)
restore_theme() {
  local current
  current=$(get_current_theme)

  # Update dynamic components without toggling
  update_gtk_theme "$current"
  update_hyprland_borders "$current"
  update_kitty "$current"
  update_tmux "$current"
  update_kvantum "$current"
  update_waybar "$current"
  update_swaync "$current"
  update_vicinae "$current"
  update_kde_colorscheme "$current"
  signal_apps
}

# Query current theme (for waybar)
query_theme() {
  local current
  current=$(get_current_theme)

  local icon text tooltip css_class
  if [[ $current == "light" ]]; then
    icon="󰖨"
    text="$icon"
    tooltip="Light mode - Click to switch to dark"
    css_class="light"
  else
    icon="󰖔"
    text="$icon"
    tooltip="Dark mode - Click to switch to light"
    css_class="dark"
  fi

  # Output JSON for waybar
  printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' "$text" "$tooltip" "$css_class"
}

# Main entry point
case "${1:-toggle}" in
toggle)
  toggle_theme
  ;;
restore)
  restore_theme
  ;;
query)
  query_theme
  ;;
get)
  get_current_theme
  ;;
*)
  echo "Usage: theme-toggle [toggle|restore|query|get]"
  echo "  toggle  - Switch between dark and light themes (default)"
  echo "  restore - Restore saved theme (for login)"
  echo "  query   - Output current theme as JSON (for waybar)"
  echo "  get     - Output current theme name"
  exit 1
  ;;
esac

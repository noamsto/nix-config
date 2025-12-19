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
  local gtk_theme_variant
  # Use dconf directly as gsettings may fail to find schemas in wrapped scripts
  if [[ $theme == "light" ]]; then
    dconf write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
    dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita'"
    dconf write /org/gnome/desktop/interface/icon-theme "'Papirus-Light'"
    gtk_theme_variant="Adwaita"
  else
    dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
    dconf write /org/gnome/desktop/interface/gtk-theme "'Adwaita-dark'"
    dconf write /org/gnome/desktop/interface/icon-theme "'Papirus-Dark'"
    gtk_theme_variant="Adwaita:dark"
  fi

  # Update environment for new processes (Hyprland + systemd user)
  hyprctl keyword env GTK_THEME,"$gtk_theme_variant" >/dev/null
  systemctl --user set-environment GTK_THEME="$gtk_theme_variant"

  # Note: Thunar doesn't dynamically respond to theme changes
  # User needs to close and reopen Thunar for theme to take effect
  # New Thunar windows will use correct GTK_THEME from environment
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

# Update kitty terminal theme (all running instances and config for new instances)
update_kitty() {
  local theme="$1"
  local kitty_theme
  if [[ $theme == "light" ]]; then
    kitty_theme="Catppuccin-Latte"
  else
    kitty_theme="Catppuccin-Mocha"
  fi

  local kitty_config="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"

  # Extract theme path from kitty.conf (themes are in nix store)
  if [[ -f $kitty_config ]]; then
    # Get the current theme include line and extract the directory path
    local theme_line
    theme_line=$(grep "^include.*Catppuccin.*\.conf" "$kitty_config" 2>/dev/null || true)

    if [[ -n $theme_line ]]; then
      # Extract the directory path (everything before the theme filename)
      # Example: "include /path/to/themes/Catppuccin-Mocha.conf" -> "/path/to/themes"
      local theme_path="${theme_line#include }" # Remove "include " prefix
      local theme_dir="${theme_path%/*}"        # Remove filename (everything after last /)
      local theme_file="${theme_dir}/${kitty_theme}.conf"

      # Update all running kitty instances via their sockets
      for sock in /tmp/kitty-*; do
        if [[ -S $sock ]]; then
          kitty @ --to "unix:$sock" set-colors --all --configured "$theme_file" 2>/dev/null || true
        fi
      done

      # Update kitty.conf include line for new instances (atomically)
      local tmp_config="${kitty_config}.tmp"
      sed "s|^include.*/Catppuccin-[^/]*\.conf|include ${theme_file}|" "$kitty_config" >"$tmp_config"
      mv "$tmp_config" "$kitty_config"
    fi
  fi
}

# Update fish shell theme
update_fish() {
  local theme="$1"

  # Call __reload_theme to set universal variables
  # Universal variables automatically propagate to all running fish instances
  if command -v fish &>/dev/null; then
    fish -c "__reload_theme" 2>/dev/null || true
  fi
}

# Update starship prompt theme
update_starship() {
  local theme="$1"
  local starship_palette
  if [[ $theme == "light" ]]; then
    starship_palette="catppuccin_latte"
  else
    starship_palette="catppuccin_mocha"
  fi

  local starship_config="${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
  if [[ -f $starship_config ]]; then
    # Atomically update the palette line in starship.toml
    local tmp_config="${starship_config}.tmp"
    sed "s/^palette = .*/palette = \"$starship_palette\"/" "$starship_config" >"$tmp_config"
    mv "$tmp_config" "$starship_config"
  fi
}

# Update k9s theme
update_k9s() {
  local theme="$1"
  local k9s_skin
  if [[ $theme == "light" ]]; then
    k9s_skin="catppuccin-latte"
  else
    k9s_skin="catppuccin-mocha"
  fi

  local k9s_config="${XDG_CONFIG_HOME:-$HOME/.config}/k9s/config.yaml"
  if [[ -f $k9s_config ]]; then
    # Atomically update the skin line in k9s config
    local tmp_config="${k9s_config}.tmp"
    sed "s/skin: catppuccin-.*/skin: $k9s_skin/" "$k9s_config" >"$tmp_config"
    mv "$tmp_config" "$k9s_config"
  fi
}

# Update lazygit theme
update_lazygit() {
  local theme="$1"
  local lazygit_flavor
  if [[ $theme == "light" ]]; then
    lazygit_flavor="latte"
  else
    lazygit_flavor="mocha"
  fi

  # Find the catppuccin-lazygit package in nix store
  local theme_dir
  theme_dir=$(find /nix/store -maxdepth 1 -name "*catppuccin-lazygit-0" -type d 2>/dev/null | head -1)

  if [[ -n $theme_dir && -d ${theme_dir}/${lazygit_flavor} ]]; then
    local lazygit_config="${XDG_CONFIG_HOME:-$HOME/.config}/lazygit/config.yml"
    local config_dir
    config_dir=$(dirname "$lazygit_config")
    mkdir -p "$config_dir"

    # Use blue accent by default (can be customized)
    local theme_file="${theme_dir}/${lazygit_flavor}/blue.yml"
    if [[ -f $theme_file ]]; then
      # Atomically copy theme file
      local tmp_config="${lazygit_config}.tmp"
      cp "$theme_file" "$tmp_config"
      mv "$tmp_config" "$lazygit_config"
    fi
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
  # Check if tmux is running (need to find socket when run from keybinding)
  # Try default socket location first, then fall back to auto-detection
  local tmux_cmd="tmux"
  if [[ -S "/run/user/$(id -u)/tmux-$(id -u)/default" ]]; then
    tmux_cmd="tmux -S /run/user/$(id -u)/tmux-$(id -u)/default"
  fi

  if $tmux_cmd list-sessions &>/dev/null; then
    # Unset all @thm_* variables first - catppuccin uses "set -ogq" which
    # only sets if not exists, so we must clear them for theme switch to work
    # Use awk to extract just variable names from lines like: @thm_bg "#1e1e2e"
    for var in $($tmux_cmd show-options -g | awk '$1 ~ /^@thm_/ {print $1}' | sort -u); do
      $tmux_cmd set -gu "$var" 2>/dev/null || true
    done
    # Update the catppuccin flavor
    $tmux_cmd set -g @catppuccin_flavor "$tmux_flavor" 2>/dev/null || true
    # Re-source the full config to pick up new @thm_* variables
    $tmux_cmd source-file ~/.config/tmux/tmux.conf 2>/dev/null || true

    # Update pane-border-format with expanded color values
    # (nested #{@thm_*} inside #[] style tags don't expand at render time)
    local thm_mauve thm_green thm_bg thm_overlay_1
    thm_mauve=$($tmux_cmd show-options -gv @thm_mauve 2>/dev/null | tr -d '"')
    thm_green=$($tmux_cmd show-options -gv @thm_green 2>/dev/null | tr -d '"')
    thm_bg=$($tmux_cmd show-options -gv @thm_bg 2>/dev/null | tr -d '"')
    thm_overlay_1=$($tmux_cmd show-options -gv @thm_overlay_1 2>/dev/null | tr -d '"')
    # Format: dot on active split pane, clean line when zoomed/inactive
    $tmux_cmd setw -g pane-border-format \
      "#{?#{&&:#{pane_active},#{&&:#{>:#{window_panes},1},#{==:#{window_zoomed_flag},0}}},#[fg=${thm_mauve}]━━ #[fg=${thm_green}]●#[fg=${thm_mauve}] ━━,#[bg=${thm_bg},fg=${thm_overlay_1}]━━━━━}"
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
  # Write atomically to Kvantum config (kvantummanager is GUI only)
  local kvantum_config="${XDG_CONFIG_HOME:-$HOME/.config}/Kvantum/kvantum.kvconfig"
  mkdir -p "$(dirname "$kvantum_config")"
  local tmp_config="${kvantum_config}.tmp"
  cat >"$tmp_config" <<EOF
[General]
theme=$kvantum_theme
EOF
  mv "$tmp_config" "$kvantum_config"
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

# Update Vicinae theme using native theme command
update_vicinae() {
  local theme="$1"
  local vicinae_theme

  if [[ $theme == "light" ]]; then
    vicinae_theme="vicinae-light"
  else
    vicinae_theme="vicinae-dark"
  fi

  # Use vicinae's native theme set command (automatically updates config and reloads)
  if command -v vicinae &>/dev/null; then
    vicinae theme set "$vicinae_theme" 2>/dev/null || true
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

# Update process-compose theme
update_process_compose() {
  local theme="$1"
  local pc_dir="${HOME}/nix-config/home/terminal/process_compose"
  local theme_file

  if [[ $theme == "light" ]]; then
    theme_file="${pc_dir}/catppuccin-latte.yaml"
  else
    theme_file="${pc_dir}/catppuccin-mocha.yaml"
  fi

  # Copy the appropriate theme to theme.yaml (symlinked by Home Manager)
  if [[ -f $theme_file ]]; then
    cp "$theme_file" "${pc_dir}/theme.yaml"
  fi
}

# Update KDE color scheme for KDE apps (KDE Connect, etc.)
# Apps need restart to pick up changes
update_kde_colorscheme() {
  local theme="$1"
  local kdeglobals="${XDG_CONFIG_HOME:-$HOME/.config}/kdeglobals"
  local tmp_kdeglobals="${kdeglobals}.tmp"

  if [[ $theme == "light" ]]; then
    # Catppuccin Latte colors
    cat >"$tmp_kdeglobals" <<'EOF'
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
    cat >"$tmp_kdeglobals" <<'EOF'
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
  # Atomically move temp file to actual config
  mv "$tmp_kdeglobals" "$kdeglobals"
}

# Signal apps to reload their themes
signal_apps() {
  # Swaync - full restart needed for theme changes (CSS reload alone doesn't work)
  # Note: NixOS wraps the binary as .swaync-wrapped, so use -f for pattern match
  if pgrep -f "swaync$" >/dev/null; then
    pkill -f "swaync$" || true
    # Wait for process to actually die (max 2 seconds)
    for _ in {1..20}; do
      pgrep -f "swaync$" >/dev/null || break
      sleep 0.1
    done
    nohup swaync >/dev/null 2>&1 &
  fi

  # Tray applets (nm-applet, blueman) pick up icon theme from dconf automatically
  # Electron apps (youtube-music, ferdium, slack) need manual restart for titlebar
  # theme change - this is a known GTK/Wayland limitation
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

  # Save new state atomically (so waybar can read it safely)
  local tmp_state="${STATE_FILE}.tmp"
  echo "$new_theme" >"$tmp_state"
  mv "$tmp_state" "$STATE_FILE"

  # Update dynamic components
  update_gtk_theme "$new_theme"
  update_hyprland_borders "$new_theme"
  update_kitty "$new_theme"
  update_fish "$new_theme"
  update_starship "$new_theme"
  update_k9s "$new_theme"
  update_lazygit "$new_theme"
  update_tmux "$new_theme"
  update_kvantum "$new_theme"
  update_waybar "$new_theme"
  update_swaync "$new_theme"
  update_process_compose "$new_theme"
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
  update_fish "$current"
  update_starship "$current"
  update_k9s "$current"
  update_lazygit "$current"
  update_tmux "$current"
  update_kvantum "$current"
  update_waybar "$current"
  update_swaync "$current"
  update_process_compose "$current"
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

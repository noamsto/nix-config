#!/usr/bin/env bash
# Theme toggle script - switches between dark and light themes at runtime
#
# Dynamic switching (instant):
# - GTK apps via dconf color-scheme (Adwaita theme respects this)
# - Hyprland border colors via hyprctl
# - Kitty terminal via remote control (set-colors)
# - Tmux via catppuccin flavor + config reload
# - Noctalia Shell via settings file update
# - Vicinae via config JSON + server restart
# - Noctalia session menu (auto-themed)
# - lazygit via config.yml swap (requires restart)
# - lazydocker via config.yml swap (requires restart)
# - btop via btop.conf theme setting (requires restart)
#
# Requires app restart:
# - Qt/Kvantum apps (Dolphin, etc.)
# - KDE apps (KDE Connect) via kdeglobals
# - yazi (config updated, picks up theme on next start)

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE_FILE="$STATE_DIR/theme-state.json"
LEGACY_STATE_FILE="$STATE_DIR/theme-mode"

# Debug mode - set THEME_TOGGLE_DEBUG=1 to enable verbose logging
DEBUG="${THEME_TOGGLE_DEBUG:-0}"

# Catppuccin colors for Hyprland borders (injected from config.theme.palette)
# Using _RAW variants (without #) for rgba() compatibility
MOCHA_BLUE="$DARK_BLUE_RAW"
MOCHA_LAVENDER="$DARK_LAVENDER_RAW"
LATTE_BLUE="$LIGHT_BLUE_RAW"
LATTE_LAVENDER="$LIGHT_LAVENDER_RAW"

# Track failed updates for recovery
declare -a FAILED_UPDATES=()

# =============================================================================
# Logging & Debug
# =============================================================================

log_debug() {
  [[ $DEBUG == "1" ]] && echo "[DEBUG] $*" >&2 || true
}

log_error() {
  echo "[ERROR] $*" >&2
}

log_warn() {
  echo "[WARN] $*" >&2
}

# =============================================================================
# State File Management (JSON)
# =============================================================================

# Ensure state directory exists
mkdir -p "$STATE_DIR"

# Migrate from legacy plain text state file
migrate_legacy_state() {
  if [[ -f $LEGACY_STATE_FILE && ! -f $STATE_FILE ]]; then
    local legacy_theme
    legacy_theme=$(cat "$LEGACY_STATE_FILE")
    log_debug "Migrating legacy state file: theme=$legacy_theme"
    write_state "$legacy_theme" "[]"
    rm -f "$LEGACY_STATE_FILE"
  fi
}

# Read current theme from state file
get_current_theme() {
  migrate_legacy_state
  if [[ -f $STATE_FILE ]]; then
    jq -r '.theme // "dark"' "$STATE_FILE" 2>/dev/null || echo "dark"
  else
    echo "dark"
  fi
}

# Read failed updates from state file
get_failed_updates() {
  if [[ -f $STATE_FILE ]]; then
    jq -r '.failed // [] | .[]' "$STATE_FILE" 2>/dev/null || true
  fi
}

# Write state file atomically
write_state() {
  local theme="$1"
  local failed_json="$2"
  local timestamp
  timestamp=$(date -Iseconds)

  local tmp_state="${STATE_FILE}.tmp"
  jq -n \
    --arg theme "$theme" \
    --arg timestamp "$timestamp" \
    --argjson failed "$failed_json" \
    '{theme: $theme, timestamp: $timestamp, failed: $failed, version: 1}' >"$tmp_state"
  mv "$tmp_state" "$STATE_FILE"
  log_debug "State saved: theme=$theme, failed=$failed_json"
}

# Convert FAILED_UPDATES array to JSON
failed_to_json() {
  if [[ ${#FAILED_UPDATES[@]} -eq 0 ]]; then
    echo "[]"
  else
    printf '%s\n' "${FAILED_UPDATES[@]}" | jq -R . | jq -s .
  fi
}

# Record a failed update
record_failure() {
  local component="$1"
  FAILED_UPDATES+=("$component")
  log_warn "Update failed: $component"
}

# =============================================================================
# Update Functions
# =============================================================================

# Update dconf for GTK apps (immediate effect via portal)
update_gtk_theme() {
  local theme="$1"
  local gtk_theme_variant
  log_debug "Updating GTK theme to $theme"

  if [[ $theme == "light" ]]; then
    gtk_theme_variant="Adwaita"
  else
    gtk_theme_variant="Adwaita:dark"
  fi

  # Use dconf load to write all values atomically (single portal notification)
  if [[ $theme == "light" ]]; then
    if ! dconf load /org/gnome/desktop/interface/ <<'EOF'; then
[/]
color-scheme='prefer-light'
gtk-theme='Adwaita'
icon-theme='Papirus-Light'
EOF
      record_failure "gtk"
      return 1
    fi
  else
    if ! dconf load /org/gnome/desktop/interface/ <<'EOF'; then
[/]
color-scheme='prefer-dark'
gtk-theme='Adwaita-dark'
icon-theme='Papirus-Dark'
EOF
      record_failure "gtk"
      return 1
    fi
  fi

  # Update environment for new processes (Hyprland + systemd user)
  hyprctl keyword env GTK_THEME,"$gtk_theme_variant" >/dev/null 2>&1 || true
  systemctl --user set-environment GTK_THEME="$gtk_theme_variant" 2>/dev/null || true

  # Update GTK3/4 settings.ini for apps that read it directly (e.g. Thunar)
  # These may be Nix store symlinks, so replace them with writable copies
  local prefer_dark=0
  local gtk_theme_name="Adwaita"
  local icon_theme="Papirus-Dark"
  if [[ $theme == "dark" ]]; then
    prefer_dark=1
    gtk_theme_name="Adwaita-dark"
    icon_theme="Papirus-Dark"
  else
    icon_theme="Papirus-Light"
  fi

  for settings_dir in "${XDG_CONFIG_HOME}/gtk-3.0" "${XDG_CONFIG_HOME}/gtk-4.0"; do
    local ini="$settings_dir/settings.ini"
    mkdir -p "$settings_dir"

    # If it's a symlink (Nix store), read contents and replace with a real file
    if [[ -L $ini ]]; then
      local contents
      contents=$(cat "$ini" 2>/dev/null) || contents=""
      rm -f "$ini"
      printf '%s\n' "$contents" >"$ini"
    fi

    if [[ -f $ini ]]; then
      # Remove existing theme keys, then append updated values
      local tmp="${ini}.tmp"
      grep -v -E '^gtk-(application-prefer-dark-theme|theme-name|icon-theme-name)=' "$ini" >"$tmp" 2>/dev/null || true
      {
        printf 'gtk-application-prefer-dark-theme=%d\n' "$prefer_dark"
        printf 'gtk-theme-name=%s\n' "$gtk_theme_name"
        printf 'gtk-icon-theme-name=%s\n' "$icon_theme"
      } >>"$tmp"
      mv "$tmp" "$ini"
    fi
  done
}

# Update GTK CSS with Catppuccin colors (libadwaita color injection)
update_gtk_css() {
  local theme="$1"
  local css_file theme_name
  log_debug "Updating GTK CSS to $theme"

  # Get theme name from environment (set by Nix from palette)
  if [[ $theme == "light" ]]; then
    theme_name="$LIGHT_THEME_NAME"
  else
    theme_name="$DARK_THEME_NAME"
  fi

  # Source CSS files generated by Nix from palette
  css_file="${XDG_CONFIG_HOME}/gtk-theme/gtk-${theme_name}.css"

  if [[ ! -f $css_file ]]; then
    log_error "GTK CSS file not found: $css_file"
    record_failure "gtk-css"
    return 1
  fi

  # Update GTK4 (libadwaita)
  mkdir -p "${XDG_CONFIG_HOME}/gtk-4.0"
  cp "$css_file" "${XDG_CONFIG_HOME}/gtk-4.0/gtk.css" || {
    record_failure "gtk-css"
    return 1
  }

  # Update GTK3 (for apps using adw-gtk3 or respecting gtk.css)
  mkdir -p "${XDG_CONFIG_HOME}/gtk-3.0"
  cp "$css_file" "${XDG_CONFIG_HOME}/gtk-3.0/gtk.css" || {
    record_failure "gtk-css"
    return 1
  }

  log_debug "GTK CSS updated to $theme"
}

# Wait for Hyprland to be ready (responsive IPC)
# This prevents crashes during resume when Hyprland is reconfiguring displays
wait_for_hyprland() {
  local max_attempts=10
  local attempt=1
  local delay=0.2

  while [[ $attempt -le $max_attempts ]]; do
    # Check if hyprctl can communicate with Hyprland
    if hyprctl version &>/dev/null; then
      log_debug "Hyprland ready after $attempt attempt(s)"
      return 0
    fi

    log_debug "Waiting for Hyprland... attempt $attempt/$max_attempts"
    sleep "$delay"

    # Exponential backoff (0.2, 0.4, 0.8, 1.0, 1.0, ...)
    delay=$(awk "BEGIN {d=$delay*2; print (d>1.0)?1.0:d}")
    ((attempt++))
  done

  log_debug "Hyprland not ready after $max_attempts attempts"
  return 1
}

# Update Hyprland border colors with retry logic
# Robust against transient failures during resume
update_hyprland_borders() {
  local theme="$1"
  log_debug "Updating Hyprland borders to $theme"

  if ! command -v hyprctl &>/dev/null; then
    log_debug "hyprctl not found, skipping"
    return 0
  fi

  # Check for Hyprland socket (skip if not running)
  local socket_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr"
  if [[ ! -d $socket_dir ]] || ! ls "$socket_dir"/*/.socket.sock &>/dev/null 2>&1; then
    log_debug "Hyprland socket not found, skipping (not running?)"
    return 0
  fi

  # Wait for Hyprland to be responsive (critical during resume)
  if ! wait_for_hyprland; then
    log_debug "Hyprland not responsive, skipping border update"
    record_failure "hyprland"
    return 1
  fi

  # Retry logic for border updates (hyprctl can fail transiently during resume)
  local max_retries=3
  local retry=0
  local success=false

  while [[ $retry -lt $max_retries && $success == false ]]; do
    if [[ $theme == "light" ]]; then
      if hyprctl keyword general:col.active_border "rgba(${LATTE_BLUE}ee) rgba(${LATTE_LAVENDER}ee) 45deg" >/dev/null 2>&1; then
        hyprctl keyword general:col.inactive_border "rgba(${LATTE_LAVENDER}40)" >/dev/null 2>&1
        success=true
      fi
    else
      if hyprctl keyword general:col.active_border "rgba(${MOCHA_BLUE}ee) rgba(${MOCHA_LAVENDER}ee) 45deg" >/dev/null 2>&1; then
        hyprctl keyword general:col.inactive_border "rgba(${MOCHA_LAVENDER}40)" >/dev/null 2>&1
        success=true
      fi
    fi

    if [[ $success == false ]]; then
      ((retry++))
      log_debug "Hyprland border update failed, retry $retry/$max_retries"
      sleep 0.5
    fi
  done

  if [[ $success == false ]]; then
    record_failure "hyprland"
    return 1
  fi

  return 0
}

# Update kitty terminal theme (all running instances and config for new instances)
update_kitty() {
  local theme="$1"
  local theme_name
  log_debug "Updating kitty to $theme"

  # Get theme name from environment (set by Nix from palette)
  if [[ $theme == "light" ]]; then
    theme_name="$LIGHT_THEME_NAME"
  else
    theme_name="$DARK_THEME_NAME"
  fi

  local kitty_config="${XDG_CONFIG_HOME}/kitty/kitty.conf"

  # Use generated theme from ~/.config/kitty/themes/
  local theme_file="${XDG_CONFIG_HOME}/kitty/themes/${theme_name}.conf"
  if [[ ! -f $theme_file ]]; then
    log_error "Kitty theme file not found: $theme_file"
    record_failure "kitty"
    return 1
  fi

  # Font weight: SemiBold for light theme (better contrast), Medium for dark
  local font_weight
  if [[ $theme == "light" ]]; then
    font_weight="SemiBold"
  else
    font_weight="Medium"
  fi

  # Update all running kitty instances via their sockets
  # Use nullglob to handle case where no sockets exist
  shopt -s nullglob
  local sockets=(/tmp/kitty-*)
  shopt -u nullglob

  log_debug "Found ${#sockets[@]} kitty sockets"
  for sock in "${sockets[@]}"; do
    if [[ -S $sock ]]; then
      log_debug "Updating kitty socket: $sock"
      kitty @ --to "unix:$sock" set-colors --all --configured "$theme_file" 2>/dev/null || true
      # Update font weight for theme
      kitty @ --to "unix:$sock" set-font-size -- 0 2>/dev/null || true # Reset to default first
    fi
  done

  # Update kitty.conf for new instances (atomically)
  if [[ -f $kitty_config ]]; then
    local tmp_config="${kitty_config}.tmp"

    # Remove any existing theme-toggle overrides and update include/font lines
    grep -v "^# theme-toggle:" "$kitty_config" 2>/dev/null |
      grep -v "^include.*/kitty/themes/" |
      sed "s|^font_family.*FiraCode Nerd Font.*|font_family FiraCode Nerd Font ${font_weight}|" >"$tmp_config" || {
      record_failure "kitty"
      rm -f "$tmp_config"
      return 1
    }

    # Prepend theme include at the top of the config
    local final_config="${kitty_config}.final"
    {
      echo "# theme-toggle: catppuccin theme"
      echo "include ${theme_file}"
      echo ""
      cat "$tmp_config"
    } >"$final_config"
    rm -f "$tmp_config"
    mv "$final_config" "$tmp_config"
    mv "$tmp_config" "$kitty_config"
  fi
}

# Update fish shell theme
update_fish() {
  local theme="$1"
  log_debug "Updating fish to $theme"

  if ! command -v fish &>/dev/null; then
    log_debug "fish not found, skipping"
    return 0
  fi

  # Check if __reload_theme function exists
  if ! fish -c "functions -q __reload_theme" 2>/dev/null; then
    log_debug "fish __reload_theme function not found, skipping"
    return 0
  fi

  # Pass theme directly to avoid race condition with state file
  fish -c "__reload_theme $theme" 2>/dev/null || {
    record_failure "fish"
    return 1
  }
}

# Update starship prompt theme
update_starship() {
  local theme="$1"
  local starship_palette
  log_debug "Updating starship to $theme"

  if [[ $theme == "light" ]]; then
    starship_palette="catppuccin_latte"
  else
    starship_palette="catppuccin_mocha"
  fi

  local starship_config="${XDG_CONFIG_HOME}/starship.toml"
  if [[ ! -f $starship_config ]]; then
    log_debug "starship config not found, skipping"
    return 0
  fi

  local tmp_config="${starship_config}.tmp"
  sed "s/^palette = .*/palette = \"$starship_palette\"/" "$starship_config" >"$tmp_config" || {
    record_failure "starship"
    rm -f "$tmp_config"
    return 1
  }
  mv "$tmp_config" "$starship_config"
}

# Update k9s theme
update_k9s() {
  local theme="$1"
  local k9s_skin
  log_debug "Updating k9s to $theme"

  # Use theme name from environment (set by Nix from palette)
  if [[ $theme == "light" ]]; then
    k9s_skin="$LIGHT_THEME_NAME"
  else
    k9s_skin="$DARK_THEME_NAME"
  fi

  local k9s_config="${XDG_CONFIG_HOME}/k9s/config.yaml"

  # Ensure directory exists
  mkdir -p "$(dirname "$k9s_config")"

  if [[ ! -f $k9s_config ]]; then
    # Create minimal config with skin setting
    cat >"$k9s_config" <<EOF
k9s:
  ui:
    enableMouse: true
    skin: $k9s_skin
EOF
    chmod 644 "$k9s_config"
    return 0
  fi

  local tmp_config="${k9s_config}.tmp"

  if [[ ! -w $k9s_config ]]; then
    # File not writable (HM symlink or read-only), recreate it
    rm -f "$k9s_config"
    cat >"$k9s_config" <<EOF
k9s:
  ui:
    enableMouse: true
    skin: $k9s_skin
EOF
    chmod 644 "$k9s_config"
  else
    # File is writable, update in place
    sed "s/skin: catppuccin-.*/skin: $k9s_skin/" "$k9s_config" >"$tmp_config" || {
      record_failure "k9s"
      rm -f "$tmp_config"
      return 1
    }
    mv "$tmp_config" "$k9s_config"
  fi
}

# Update lazygit theme
update_lazygit() {
  local theme="$1"
  local lazygit_config="${XDG_CONFIG_HOME}/lazygit/config.yml"
  log_debug "Updating lazygit to $theme"

  mkdir -p "$(dirname "$lazygit_config")"

  # Remove existing file (may be read-only from HM)
  rm -f "$lazygit_config"

  if [[ $theme == "light" ]]; then
    # Custom Catppuccin Latte theme with proper contrast
    cat >"$lazygit_config" <<EOF
gui:
  lightTheme: true
  nerdFontsVersion: "3"
  theme:
    activeBorderColor:
      - '$LIGHT_BLUE'
      - bold
    inactiveBorderColor:
      - '$LIGHT_OVERLAY1'
    optionsTextColor:
      - '$LIGHT_BLUE'
    selectedLineBgColor:
      - '$LIGHT_SURFACE0'
    cherryPickedCommitBgColor:
      - '$LIGHT_SURFACE1'
    cherryPickedCommitFgColor:
      - '$LIGHT_BLUE'
    unstagedChangesColor:
      - '$LIGHT_RED'
    defaultFgColor:
      - '$LIGHT_TEXT'
    searchingActiveBorderColor:
      - '$LIGHT_YELLOW'
  authorColors:
    '*': '$LIGHT_SUBTEXT1'
  branchColors:
    '*': '$LIGHT_SUBTEXT1'
EOF
  else
    # Use theme from Nix-provided package
    if [[ -z ${LAZYGIT_THEMES_PATH:-} ]]; then
      log_error "LAZYGIT_THEMES_PATH not set"
      record_failure "lazygit"
      return 1
    fi

    local mocha_theme="${LAZYGIT_THEMES_PATH}/mocha/blue.yml"
    if [[ -f $mocha_theme ]]; then
      cp "$mocha_theme" "$lazygit_config"
    else
      log_error "Lazygit mocha theme not found: $mocha_theme"
      record_failure "lazygit"
      return 1
    fi
  fi

  chmod 644 "$lazygit_config"
}

# Update btop theme (uses palette-generated themes)
update_btop() {
  local theme="$1"
  local btop_theme
  log_debug "Updating btop to $theme"

  # Use theme names from palette (DARK_THEME_NAME/LIGHT_THEME_NAME set by theme-toggle.nix)
  if [[ $theme == "light" ]]; then
    btop_theme="$LIGHT_THEME_NAME"
  else
    btop_theme="$DARK_THEME_NAME"
  fi

  local btop_config="${XDG_CONFIG_HOME}/btop/btop.conf"

  if [[ ! -f $btop_config ]]; then
    log_debug "btop config not found, skipping"
    return 0
  fi

  # Use atomic tmp-file-mv pattern
  local tmp_config="${btop_config}.tmp"

  if [[ ! -w $btop_config ]]; then
    # File not writable, recreate it
    rm -f "$btop_config"
    echo "color_theme = \"${btop_theme}.theme\"" >"$btop_config"
    chmod 644 "$btop_config"
  else
    sed "s/^color_theme = .*/color_theme = \"${btop_theme}.theme\"/" "$btop_config" >"$tmp_config" || {
      record_failure "btop"
      rm -f "$tmp_config"
      return 1
    }
    mv "$tmp_config" "$btop_config"
  fi
}

# Update lazydocker theme (copies pre-generated config from themes directory)
update_lazydocker() {
  local theme="$1"
  local lazydocker_theme
  log_debug "Updating lazydocker to $theme"

  # Use theme names from palette
  if [[ $theme == "light" ]]; then
    lazydocker_theme="$LIGHT_THEME_NAME"
  else
    lazydocker_theme="$DARK_THEME_NAME"
  fi

  local lazydocker_config="${XDG_CONFIG_HOME}/lazydocker/config.yml"
  local theme_source="${XDG_CONFIG_HOME}/lazydocker/themes/${lazydocker_theme}.yml"

  if [[ ! -f $theme_source ]]; then
    log_debug "lazydocker theme source not found: $theme_source, skipping"
    return 0
  fi

  # Ensure config directory exists
  mkdir -p "$(dirname "$lazydocker_config")"

  # Remove existing config if not writable (HM symlink)
  if [[ -f $lazydocker_config && ! -w $lazydocker_config ]]; then
    rm -f "$lazydocker_config"
  fi

  cp "$theme_source" "$lazydocker_config" || {
    record_failure "lazydocker"
    return 1
  }
  chmod 644 "$lazydocker_config"
}

# Update tmux catppuccin flavor
update_tmux() {
  local theme="$1"
  local tmux_flavor
  log_debug "Updating tmux to $theme"

  if [[ $theme == "light" ]]; then
    tmux_flavor="latte"
  else
    tmux_flavor="mocha"
  fi

  # Find tmux socket - check TMUX env first, then default locations
  local tmux_cmd="tmux"
  if [[ -n ${TMUX:-} ]]; then
    # Inside tmux, use standard commands
    tmux_cmd="tmux"
  elif [[ -S "/run/user/$(id -u)/tmux-$(id -u)/default" ]]; then
    tmux_cmd="tmux -S /run/user/$(id -u)/tmux-$(id -u)/default"
  fi

  # Check if tmux is running
  if ! $tmux_cmd list-sessions &>/dev/null 2>&1; then
    log_debug "tmux not running, skipping"
    return 0
  fi

  # Unset all @thm_* variables first - catppuccin uses "set -ogq" which
  # only sets if not exists, so we must clear them for theme switch to work
  local var
  for var in $($tmux_cmd show-options -g 2>/dev/null | awk '$1 ~ /^@thm_/ {print $1}' | sort -u); do
    $tmux_cmd set -gu "$var" 2>/dev/null || true
  done

  # Update the catppuccin flavor
  $tmux_cmd set -g @catppuccin_flavor "$tmux_flavor" 2>/dev/null || {
    record_failure "tmux"
    return 1
  }

  # Re-source the full config to pick up new @thm_* variables
  $tmux_cmd source-file ~/.config/tmux/tmux.conf 2>/dev/null || true

  # Update pane-border-format with expanded color values
  local thm_mauve thm_green thm_bg thm_overlay_1
  thm_mauve=$($tmux_cmd show-options -gv @thm_mauve 2>/dev/null | tr -d '"')
  thm_green=$($tmux_cmd show-options -gv @thm_green 2>/dev/null | tr -d '"')
  thm_bg=$($tmux_cmd show-options -gv @thm_bg 2>/dev/null | tr -d '"')
  thm_overlay_1=$($tmux_cmd show-options -gv @thm_overlay_1 2>/dev/null | tr -d '"')

  # Validate colors (should be hex format)
  if [[ -n $thm_mauve && -n $thm_green && -n $thm_bg && -n $thm_overlay_1 ]]; then
    $tmux_cmd setw -g pane-border-format \
      "#{?#{&&:#{pane_active},#{&&:#{>:#{window_panes},1},#{==:#{window_zoomed_flag},0}}},#[fg=${thm_mauve}]━━ #[fg=${thm_green}]●#[fg=${thm_mauve}] ━━,#[bg=${thm_bg},fg=${thm_overlay_1}]━━━━━}"
  fi
}

# Update Kvantum theme for Qt apps (requires app restart)
update_kvantum() {
  local theme="$1"
  local kvantum_theme
  log_debug "Updating kvantum to $theme"

  if [[ $theme == "light" ]]; then
    kvantum_theme="catppuccin-latte-blue"
  else
    kvantum_theme="catppuccin-mocha-blue"
  fi

  local kvantum_config="${XDG_CONFIG_HOME}/Kvantum/kvantum.kvconfig"

  if ! mkdir -p "$(dirname "$kvantum_config")"; then
    log_error "Failed to create Kvantum config directory"
    record_failure "kvantum"
    return 1
  fi

  local tmp_config="${kvantum_config}.tmp"
  if ! cat >"$tmp_config" <<EOF; then
[General]
theme=$kvantum_theme
EOF
    record_failure "kvantum"
    rm -f "$tmp_config"
    return 1
  fi
  mv "$tmp_config" "$kvantum_config"
}

# Update Noctalia Shell dark/light mode
update_noctalia() {
  local theme="$1"
  local dark_mode
  log_debug "Updating Noctalia to $theme"

  if [[ $theme == "light" ]]; then
    dark_mode="false"
  else
    dark_mode="true"
  fi

  local gui_settings="${XDG_CONFIG_HOME}/noctalia/settings.json"

  if [[ ! -f $gui_settings ]]; then
    log_debug "Noctalia settings.json not found, skipping"
    return 0
  fi

  # Update darkMode in settings.json
  local tmp_file
  tmp_file=$(mktemp)
  if jq --argjson dark "$dark_mode" '.colorSchemes.darkMode = $dark' "$gui_settings" >"$tmp_file" 2>/dev/null; then
    mv "$tmp_file" "$gui_settings"
    # Restart Noctalia to pick up the change
    systemctl --user restart noctalia-shell.service 2>/dev/null || true
  else
    rm -f "$tmp_file"
    record_failure "noctalia"
    return 1
  fi
}

# Update Vicinae theme using native theme command
update_vicinae() {
  local theme="$1"
  local vicinae_theme
  log_debug "Updating vicinae to $theme"

  if [[ $theme == "light" ]]; then
    vicinae_theme="vicinae-light"
  else
    vicinae_theme="vicinae-dark"
  fi

  if ! command -v vicinae &>/dev/null; then
    log_debug "vicinae not found, skipping"
    return 0
  fi

  vicinae theme set "$vicinae_theme" 2>/dev/null || {
    record_failure "vicinae"
    return 1
  }
}

# Update process-compose theme
update_process_compose() {
  local theme="$1"
  local theme_file target_file theme_name
  log_debug "Updating process-compose to $theme"

  # Source theme files generated by Nix from palette
  local pc_dir="${XDG_CONFIG_HOME}/process-compose"

  # Get theme name from environment (set by Nix from palette)
  if [[ $theme == "light" ]]; then
    theme_name="$LIGHT_THEME_NAME"
  else
    theme_name="$DARK_THEME_NAME"
  fi
  theme_file="${pc_dir}/${theme_name}.yaml"

  target_file="${pc_dir}/theme.yaml"

  if [[ ! -f $theme_file ]]; then
    log_debug "Process-compose theme file not found: $theme_file"
    return 0
  fi

  cp "$theme_file" "$target_file" || {
    record_failure "process-compose"
    return 1
  }
}

# wleave removed - using Noctalia session menu which auto-themes

# Update KDE color scheme for KDE apps (KDE Connect, etc.)
update_kde_colorscheme() {
  local theme="$1"
  local kdeglobals="${XDG_CONFIG_HOME}/kdeglobals"
  local tmp_kdeglobals="${kdeglobals}.tmp"
  log_debug "Updating KDE colorscheme to $theme"

  if [[ $theme == "light" ]]; then
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

  mv "$tmp_kdeglobals" "$kdeglobals" || {
    record_failure "kde"
    rm -f "$tmp_kdeglobals"
    return 1
  }
}

# Update bat syntax highlighter theme
update_bat() {
  local theme="$1"
  local bat_theme
  log_debug "Updating bat to $theme"

  if [[ $theme == "light" ]]; then
    bat_theme="Catppuccin Latte"
  else
    bat_theme="Catppuccin Mocha"
  fi

  # Set fish universal variable (persists across sessions, updates immediately)
  # New shells will pick this up automatically
  # Note: explicit `true` at end ensures exit 0 even if set -U returns non-zero
  fish -c "set -U BAT_THEME '$bat_theme'; true" 2>/dev/null || true

  # For existing fish sessions: update their BAT_THEME environment
  fish -c "set -gx BAT_THEME '$bat_theme'; true" 2>/dev/null || true

  # Also update systemd user environment for non-fish shells
  systemctl --user set-environment BAT_THEME="$bat_theme" 2>/dev/null || true
  # Also update Hyprland environment
  hyprctl keyword env BAT_THEME,"$bat_theme" >/dev/null 2>&1 || true
}

# Update delta git diff theme
update_delta() {
  local theme="$1"
  local syntax_theme minus_style minus_emph plus_style plus_emph
  local minus_line plus_line zero_line
  local theme_override_file="$XDG_CONFIG_HOME/git/theme-override"
  log_debug "Updating delta to $theme"

  if [[ $theme == "light" ]]; then
    syntax_theme="Catppuccin Latte"
    # Latte: subtle backgrounds for diff (custom blends, not pure palette)
    minus_style="syntax #e8cdd0"
    minus_emph="syntax #d4a5ab"
    plus_style="syntax #cee0cf"
    plus_emph="syntax #a8d1aa"
    minus_line="$LIGHT_RED"
    plus_line="#358023" # Darker green for contrast
    zero_line="$LIGHT_OVERLAY0"
  else
    syntax_theme="Catppuccin Mocha"
    # Mocha: more vibrant backgrounds for diff visibility (custom blends)
    minus_style="syntax #53394a"
    minus_emph="syntax #6e4458"
    plus_style="syntax #394e42"
    plus_emph="syntax #4a6652"
    minus_line="$DARK_RED"
    plus_line="$DARK_GREEN"
    zero_line="$DARK_OVERLAY0"
  fi

  # Write to mutable theme-override file (included by main git config)
  local tmp_file
  tmp_file=$(mktemp)
  cat >"$tmp_file" <<EOF
# This file is managed by theme-toggle script at runtime
# Do not edit manually - changes will be overwritten
[delta]
  syntax-theme = $syntax_theme
  minus-style = $minus_style
  minus-emph-style = $minus_emph
  plus-style = $plus_style
  plus-emph-style = $plus_emph
  line-numbers-minus-style = $minus_line
  line-numbers-plus-style = $plus_line
  line-numbers-zero-style = $zero_line
EOF
  mv "$tmp_file" "$theme_override_file" || {
    rm -f "$tmp_file"
    record_failure "delta"
    return 1
  }
}

# Update foot terminal theme
update_foot() {
  local theme="$1"
  local theme_name
  log_debug "Updating foot to $theme"

  # Get theme name from environment (set by Nix from palette)
  if [[ $theme == "light" ]]; then
    theme_name="$LIGHT_THEME_NAME"
  else
    theme_name="$DARK_THEME_NAME"
  fi

  # Font weight: semibold for light theme (better contrast), regular for dark
  local font_weight_suffix
  if [[ $theme == "light" ]]; then
    font_weight_suffix=":weight=semibold"
  else
    font_weight_suffix=""
  fi

  local foot_config="${XDG_CONFIG_HOME}/foot/foot.ini"
  if [[ ! -f $foot_config ]]; then
    log_debug "foot config not found, skipping"
    return 0
  fi

  # Use generated theme from ~/.config/foot/themes/
  local theme_file="${XDG_CONFIG_HOME}/foot/themes/${theme_name}.ini"
  if [[ ! -f $theme_file ]]; then
    log_debug "foot theme file not found: $theme_file"
    return 0
  fi

  local tmp_config="${foot_config}.tmp"

  # Update include line and font weight in foot.ini
  # Remove any existing weight suffix, then add the appropriate one
  sed -e "s|^include=.*/foot/themes/.*\.ini|include=${theme_file}|" \
    -e "s|^include=.*/catppuccin-.*\.ini|include=${theme_file}|" \
    -e "s|^font=\(Fira Code Nerd Font:size=[0-9]*\)\(:weight=[a-z]*\)\?|font=\1${font_weight_suffix}|" \
    "$foot_config" >"$tmp_config" || {
    record_failure "foot"
    rm -f "$tmp_config"
    return 1
  }
  mv "$tmp_config" "$foot_config"

  # Signal running foot instances to reload config
  pkill -USR1 foot 2>/dev/null || true
}

# Update fzf fuzzy finder colors
update_fzf() {
  local theme="$1"
  local fzf_colors
  log_debug "Updating fzf to $theme"

  # Catppuccin color schemes for fzf (using palette variables)
  if [[ $theme == "light" ]]; then
    # Catppuccin Latte
    fzf_colors="bg+:$LIGHT_SURFACE0,bg:$LIGHT_BASE,spinner:$LIGHT_ROSEWATER,hl:$LIGHT_RED,fg:$LIGHT_TEXT,header:$LIGHT_RED,info:$LIGHT_MAUVE,pointer:$LIGHT_ROSEWATER,marker:$LIGHT_LAVENDER,fg+:$LIGHT_TEXT,prompt:$LIGHT_MAUVE,hl+:$LIGHT_RED,selected-bg:$LIGHT_SURFACE1,border:$LIGHT_OVERLAY0,label:$LIGHT_TEXT"
  else
    # Catppuccin Mocha
    fzf_colors="bg+:$DARK_SURFACE0,bg:$DARK_BASE,spinner:$DARK_ROSEWATER,hl:$DARK_RED,fg:$DARK_TEXT,header:$DARK_RED,info:$DARK_MAUVE,pointer:$DARK_ROSEWATER,marker:$DARK_LAVENDER,fg+:$DARK_TEXT,prompt:$DARK_MAUVE,hl+:$DARK_RED,selected-bg:$DARK_SURFACE1,border:$DARK_OVERLAY0,label:$DARK_TEXT"
  fi

  # Set fish universal variable (persists across sessions, updates immediately)
  # New shells will pick this up via interactiveShellInit
  # Note: explicit `true` at end ensures exit 0 even if set -U returns non-zero
  fish -c "set -U fzf_theme_colors '--color=$fzf_colors'; true" 2>/dev/null || true

  # For existing fish sessions: directly update their FZF_DEFAULT_OPTS
  # by appending our theme colors (later --color overrides earlier)
  # Note: string replace returns 1 if no match, so we end with `true`
  fish -c "
    set -l base_opts (string replace -r -- '--color=[^ ]+\$' '' \$FZF_DEFAULT_OPTS; or true)
    set -U FZF_DEFAULT_OPTS \$base_opts '--color=$fzf_colors'
    true
  " 2>/dev/null || true

  # Also update systemd/hyprland env for non-fish shells
  systemctl --user set-environment FZF_DEFAULT_OPTS_THEME="--color=$fzf_colors" 2>/dev/null || true
  hyprctl keyword env FZF_DEFAULT_OPTS_THEME,"--color=$fzf_colors" >/dev/null 2>&1 || true
}

# Update yazi file manager theme
# Note: Requires yazi restart to take effect
update_yazi() {
  local theme="$1"
  local yazi_flavor yazi_theme_file
  log_debug "Updating yazi to $theme"

  if [[ -z ${YAZI_THEMES_PATH:-} ]]; then
    log_error "YAZI_THEMES_PATH not set"
    record_failure "yazi"
    return 1
  fi

  if [[ $theme == "light" ]]; then
    yazi_flavor="latte"
  else
    yazi_flavor="mocha"
  fi

  yazi_theme_file="${YAZI_THEMES_PATH}/${yazi_flavor}/catppuccin-${yazi_flavor}-blue.toml"

  if [[ ! -f $yazi_theme_file ]]; then
    log_error "Yazi theme file not found: $yazi_theme_file"
    record_failure "yazi"
    return 1
  fi

  local yazi_config="${XDG_CONFIG_HOME}/yazi/theme.toml"
  mkdir -p "$(dirname "$yazi_config")"

  # Remove existing file (may be symlink from HM)
  rm -f "$yazi_config"
  cp "$yazi_theme_file" "$yazi_config" || {
    record_failure "yazi"
    return 1
  }
  chmod 644 "$yazi_config"
}

# Update Claude Code theme
# Note: Only affects new sessions; running sessions won't update until restart
# In Claude Code: dark theme = no "theme" key, light theme = "theme": "light"
update_claude_code() {
  local theme="$1"
  local config_file="${HOME}/.claude.json"
  log_debug "Updating Claude Code to $theme"

  if [[ ! -f $config_file ]]; then
    log_debug "Claude config not found: $config_file"
    return 0
  fi

  local tmp_file
  tmp_file=$(mktemp)

  if [[ $theme == "dark" ]]; then
    # Dark theme = remove theme key
    if jq 'del(.theme)' "$config_file" >"$tmp_file" 2>/dev/null; then
      mv "$tmp_file" "$config_file"
    else
      rm -f "$tmp_file"
      record_failure "claude-code"
      return 1
    fi
  else
    # Light theme = set theme key
    if jq --arg theme "$theme" '.theme = $theme' "$config_file" >"$tmp_file" 2>/dev/null; then
      mv "$tmp_file" "$config_file"
    else
      rm -f "$tmp_file"
      record_failure "claude-code"
      return 1
    fi
  fi
}

# =============================================================================
# Service Management
# =============================================================================

# Restart a service using systemd if available
restart_service() {
  local service="$1"
  log_debug "Restarting service: $service"

  # Try systemd
  if systemctl --user is-active "${service}.service" &>/dev/null; then
    log_debug "Using systemctl to restart $service"
    systemctl restart --user "${service}.service" 2>/dev/null && return 0
  fi

  log_debug "Service $service not running or not found"
}

# Signal apps to reload their themes
signal_apps() {
  log_debug "Signaling apps to reload"

  # GTK portal - restart to pick up new GTK theme settings (for Firefox file picker, etc.)
  systemctl --user restart xdg-desktop-portal-gtk.service 2>/dev/null || true

  # Restart vicinae so it launches apps with the new GTK_THEME environment
  systemctl --user restart vicinae.service 2>/dev/null || true
}

# =============================================================================
# Main Commands
# =============================================================================

# Apply theme to all components (excluding Noctalia - used when Noctalia triggers the change)
apply_theme_from_noctalia() {
  local theme="$1"
  FAILED_UPDATES=()

  log_debug "Applying theme from Noctalia: $theme"

  # Update all components EXCEPT Noctalia (it already changed)
  update_gtk_theme "$theme" || true
  update_gtk_css "$theme" || true
  update_hyprland_borders "$theme" || true
  update_kitty "$theme" || true
  update_foot "$theme" || true
  update_fish "$theme" || true
  update_starship "$theme" || true
  update_k9s "$theme" || true
  update_lazygit "$theme" || true
  update_lazydocker "$theme" || true
  update_btop "$theme" || true
  update_bat "$theme" || true
  update_delta "$theme" || true
  update_fzf "$theme" || true
  update_yazi "$theme" || true
  update_tmux "$theme" || true
  update_kvantum "$theme" || true
  # NOTE: Noctalia NOT updated here - it triggered this change
  update_process_compose "$theme" || true
  update_vicinae "$theme" || true
  update_kde_colorscheme "$theme" || true
  update_claude_code "$theme" || true
  signal_apps
}

# Apply theme to all components (including Noctalia - used for restore/sync)
apply_theme() {
  local theme="$1"
  FAILED_UPDATES=()

  log_debug "Applying theme: $theme"

  # Update all components (|| true prevents set -e from exiting on failures)
  update_gtk_theme "$theme" || true
  update_gtk_css "$theme" || true
  update_hyprland_borders "$theme" || true
  update_kitty "$theme" || true
  update_foot "$theme" || true
  update_fish "$theme" || true
  update_starship "$theme" || true
  update_k9s "$theme" || true
  update_lazygit "$theme" || true
  update_lazydocker "$theme" || true
  update_btop "$theme" || true
  update_bat "$theme" || true
  update_delta "$theme" || true
  update_fzf "$theme" || true
  update_yazi "$theme" || true
  update_tmux "$theme" || true
  update_kvantum "$theme" || true
  update_noctalia "$theme" || true
  update_process_compose "$theme" || true
  update_vicinae "$theme" || true
  update_kde_colorscheme "$theme" || true
  update_claude_code "$theme" || true
  signal_apps
}

# Toggle between dark and light themes via Noctalia
# Noctalia is the source of truth - toggling it triggers the darkModeChange hook
toggle_theme() {
  log_debug "Toggling theme via Noctalia"

  # Find Noctalia's quickshell process (the wrapper script)
  local noctalia_pid
  noctalia_pid=$(pgrep -f "quickshell.*noctalia-shell" 2>/dev/null | head -1)

  if [[ -n $noctalia_pid ]]; then
    log_debug "Found Noctalia at PID $noctalia_pid"
    # Use Noctalia IPC to toggle dark mode - this triggers the darkModeChange hook
    # which then calls `theme-toggle apply` to update all other apps
    if noctalia-ipc --pid "$noctalia_pid" darkMode toggle 2>/dev/null; then
      log_debug "Noctalia dark mode toggled via IPC"
      return 0
    fi
    log_error "Noctalia IPC call failed"
  else
    log_error "Noctalia process not found"
  fi

  # Fallback: toggle all apps except Noctalia to avoid potential cycle
  # (If we updated Noctalia here, its hook might re-trigger us)
  log_debug "Using fallback theme toggle"
  local current
  current=$(get_current_theme)
  local new_theme
  if [[ $current == "dark" ]]; then
    new_theme="light"
  else
    new_theme="dark"
  fi
  # Use apply_theme_from_noctalia to avoid updating Noctalia (prevents cycle)
  apply_theme_from_noctalia "$new_theme"
  write_state "$new_theme" "$(failed_to_json)"
  notify-send "Theme" "Switched to $new_theme mode (Noctalia not synced)" -i "$([ "$new_theme" = "light" ] && echo weather-clear || echo weather-clear-night)"
}

# Apply theme from Noctalia hook (called when Noctalia dark mode changes)
# This is triggered by Noctalia's darkModeChange hook
apply_theme_command() {
  local theme="$1"

  if [[ -z $theme || ($theme != "dark" && $theme != "light") ]]; then
    echo "Usage: theme-toggle apply <dark|light>"
    exit 1
  fi

  log_debug "Applying theme (from Noctalia hook): $theme"

  # Apply to all apps except Noctalia (it already changed)
  apply_theme_from_noctalia "$theme"

  # Save state with any failures
  write_state "$theme" "$(failed_to_json)"

  # Notify user
  local icon
  if [[ $theme == "light" ]]; then
    icon="weather-clear"
  else
    icon="weather-clear-night"
  fi

  if [[ ${#FAILED_UPDATES[@]} -gt 0 ]]; then
    notify-send "Theme" "Switched to $theme (${#FAILED_UPDATES[@]} failed: ${FAILED_UPDATES[*]})" -i "$icon"
  else
    notify-send "Theme" "Switched to $theme mode" -i "$icon"
  fi
}

# Restore theme (called at login)
restore_theme() {
  local current
  current=$(get_current_theme)
  log_debug "Restoring theme: $current"

  # Apply theme
  apply_theme "$current"

  # Save state with any new failures
  write_state "$current" "$(failed_to_json)"
}

# Sync/retry failed updates
sync_theme() {
  local current
  current=$(get_current_theme)

  # Get previously failed updates
  local failed
  mapfile -t failed < <(get_failed_updates)

  if [[ ${#failed[@]} -eq 0 ]]; then
    echo "No failed updates to retry"
    return 0
  fi

  echo "Retrying ${#failed[@]} failed updates: ${failed[*]}"
  FAILED_UPDATES=()

  # Retry only failed components
  for component in "${failed[@]}"; do
    log_debug "Retrying: $component"
    case "$component" in
    gtk) update_gtk_theme "$current" ;;
    hyprland) update_hyprland_borders "$current" ;;
    kitty) update_kitty "$current" ;;
    foot) update_foot "$current" ;;
    fish) update_fish "$current" ;;
    starship) update_starship "$current" ;;
    k9s) update_k9s "$current" ;;
    lazygit) update_lazygit "$current" ;;
    lazydocker) update_lazydocker "$current" ;;
    btop) update_btop "$current" ;;
    bat) update_bat "$current" ;;
    delta) update_delta "$current" ;;
    fzf) update_fzf "$current" ;;
    yazi) update_yazi "$current" ;;
    tmux) update_tmux "$current" ;;
    kvantum) update_kvantum "$current" ;;
    noctalia) update_noctalia "$current" ;;
    process-compose) update_process_compose "$current" ;;
    vicinae) update_vicinae "$current" ;;
    kde) update_kde_colorscheme "$current" ;;
    claude-code) update_claude_code "$current" ;;
    gtk-css) update_gtk_css "$current" ;;
    *) log_warn "Unknown component: $component" ;;
    esac
  done

  # Update state
  write_state "$current" "$(failed_to_json)"

  if [[ ${#FAILED_UPDATES[@]} -gt 0 ]]; then
    echo "Still failing: ${FAILED_UPDATES[*]}"
    return 1
  else
    echo "All updates successful"
    return 0
  fi
}

# Show current status
show_status() {
  if [[ ! -f $STATE_FILE ]]; then
    echo "Theme: dark (default, no state file)"
    return 0
  fi

  local theme timestamp failed_count
  theme=$(jq -r '.theme // "unknown"' "$STATE_FILE")
  timestamp=$(jq -r '.timestamp // "unknown"' "$STATE_FILE")
  failed_count=$(jq -r '.failed | length' "$STATE_FILE")

  echo "Theme: $theme"
  echo "Last changed: $timestamp"

  if [[ $failed_count -gt 0 ]]; then
    echo "Failed updates ($failed_count):"
    jq -r '.failed[]' "$STATE_FILE" | while read -r f; do
      echo "  - $f"
    done
    echo ""
    echo "Run 'theme-toggle sync' to retry failed updates"
  else
    echo "All components updated successfully"
  fi
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

# =============================================================================
# Main Entry Point
# =============================================================================

case "${1:-toggle}" in
toggle)
  toggle_theme
  exit 0
  ;;
apply)
  apply_theme_command "${2:-}"
  exit 0
  ;;
restore)
  restore_theme
  ;;
sync)
  sync_theme
  ;;
status)
  show_status
  ;;
query)
  query_theme
  ;;
get)
  get_current_theme
  ;;
*)
  echo "Usage: theme-toggle [toggle|apply|restore|sync|status|query|get]"
  echo "  toggle        - Switch between dark and light themes (default)"
  echo "  apply <theme> - Apply specific theme (dark|light) - used by Noctalia hook"
  echo "  restore       - Restore saved theme (for login)"
  echo "  sync          - Retry failed updates"
  echo "  status        - Show current theme status and any failures"
  echo "  query         - Output current theme as JSON (for waybar)"
  echo "  get           - Output current theme name"
  echo ""
  echo "Environment variables:"
  echo "  THEME_TOGGLE_DEBUG=1  Enable debug logging"
  exit 1
  ;;
esac

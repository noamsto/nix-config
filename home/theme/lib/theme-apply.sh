# theme-apply.sh — shared, platform-neutral theme application library.
# Sourced by the Linux theme-toggle wrapper and the macOS theme-apply-macos
# driver. Contains ONLY platform-neutral logic: per-app update_* functions,
# failure tracking, and a parallel runner with no signaling tail. Platform
# orchestration (Noctalia/systemctl/notify on Linux; launchd/defaults on macOS)
# lives in the respective wrappers.
# shellcheck shell=bash
# Palette vars (DARK_*, LIGHT_*, *_RAW, *_THEME_NAME) and theme paths are
# exported by the sourcing wrapper, so shellcheck cannot see their assignment.
# shellcheck disable=SC2154
# The MOCHA_*/LATTE_* border vars are consumed by the Linux wrapper's
# update_hyprland_borders, not by this neutral lib.
# shellcheck disable=SC2034

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

# Record a failed update.
# Sequential mode appends to FAILED_UPDATES. Parallel mode (FAILED_DIR set)
# touches a marker file so children in subshells survive the wait barrier.
record_failure() {
  local component="$1"
  log_warn "Update failed: $component"
  if [[ -n ${FAILED_DIR:-} ]]; then
    : >"$FAILED_DIR/$component" 2>/dev/null || true
  else
    FAILED_UPDATES+=("$component")
  fi
}

# Collect failures written by parallel children into FAILED_UPDATES, then
# clean up the temp dir. No-op if not in parallel mode.
collect_parallel_failures() {
  [[ -z ${FAILED_DIR:-} || ! -d ${FAILED_DIR:-} ]] && return 0
  local f
  for f in "$FAILED_DIR"/*; do
    [[ -e $f ]] || continue
    FAILED_UPDATES+=("$(basename "$f")")
  done
  rm -rf "$FAILED_DIR"
  unset FAILED_DIR
}

# =============================================================================
# Parallel Runner
# =============================================================================

# Run a list of update fns in parallel, collecting failures. No signaling tail.
# Args: theme + update fn names.
_run_updates_neutral() {
  local theme="$1"
  shift
  FAILED_UPDATES=()
  FAILED_DIR=$(mktemp -d -t theme-apply.XXXXXX) || {
    log_warn "mktemp failed; falling back to sequential"
    local fn
    for fn in "$@"; do "$fn" "$theme" || true; done
    return 0
  }
  export FAILED_DIR
  local fn
  for fn in "$@"; do "$fn" "$theme" & done
  wait
  collect_parallel_failures
}

# =============================================================================
# Update Functions
# =============================================================================

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
    log_debug "Kitty theme file not found: $theme_file, skipping"
    return 0
  fi

  # Font weight: SemiBold for light theme (better contrast), Medium for dark
  local font_weight
  if [[ $theme == "light" ]]; then
    font_weight="SemiBold"
  else
    font_weight="Medium"
  fi

  # Update all running kitty instances via their sockets
  shopt -s nullglob
  local sockets=(/tmp/kitty-*)
  shopt -u nullglob

  for sock in "${sockets[@]}"; do
    if [[ -S $sock ]]; then
      kitty @ --to "unix:$sock" set-colors --all --configured "$theme_file" 2>/dev/null || true
      kitty @ --to "unix:$sock" set-font-size -- 0 2>/dev/null || true
    fi
  done

  # Update kitty.conf for new instances (atomically)
  if [[ -f $kitty_config ]]; then
    local tmp_config="${kitty_config}.tmp"

    grep -v "^# theme-toggle:" "$kitty_config" 2>/dev/null |
      grep -v "^include.*/kitty/themes/" |
      sed "s|^font_family.*FiraCode Nerd Font.*|font_family FiraCode Nerd Font ${font_weight}|" >"$tmp_config" || {
      record_failure "kitty"
      rm -f "$tmp_config"
      return 1
    }

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

  # Update colors via universals, then bump __theme_mode so every running
  # interactive fish receives an --on-variable event and repaints its prompt
  # (handler in zzz-dynamic-theme.fish).
  fish -c "__reload_theme $theme; set -U __theme_mode $theme" 2>/dev/null || {
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
      - '$LIGHT_MAUVE'
      - bold
    inactiveBorderColor:
      - '$LIGHT_OVERLAY1'
    optionsTextColor:
      - '$LIGHT_MAUVE'
    selectedLineBgColor:
      - '$LIGHT_SURFACE0'
    cherryPickedCommitBgColor:
      - '$LIGHT_SURFACE1'
    cherryPickedCommitFgColor:
      - '$LIGHT_MAUVE'
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

    local mocha_theme="${LAZYGIT_THEMES_PATH}/mocha/mauve.yml"
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

  # Remove existing file first: cp derives a new file's mode from the source,
  # and the source is a read-only HM symlink into the Nix store, so a plain
  # overwrite fails with "Permission denied" on the second and later runs.
  rm -f "$target_file"
  cp "$theme_file" "$target_file" || {
    record_failure "process-compose"
    return 1
  }
  chmod 644 "$target_file"
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

  yazi_theme_file="${YAZI_THEMES_PATH}/${yazi_flavor}/catppuccin-${yazi_flavor}-mauve.toml"

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

  # Custom folder/file icons (inject into [icon].files array)
  # Palette accent colors based on current theme
  local accent peach sky sapphire green
  if [[ $theme == "light" ]]; then
    accent="$LIGHT_MAUVE"
    peach="$LIGHT_PEACH"
    sky="$LIGHT_SKY"
    sapphire="$LIGHT_SAPPHIRE"
    green="$LIGHT_GREEN"
  else
    accent="$DARK_MAUVE"
    peach="$DARK_PEACH"
    sky="$DARK_SKY"
    sapphire="$DARK_SAPPHIRE"
    green="$DARK_GREEN"
  fi

  # Nerd Font glyphs - paste actual glyph chars here (variables avoid Unicode loss in editors)
  local ICON_NIX_CONFIG="󰜗" # nerd: nf-md-snowflake
  local ICON_VAULTS="󱒇"     # nerd: nf-md-vault
  local ICON_GIT=""        # nerd: nf-fa-git_alt
  local ICON_DOTFILES="󰒓"   # nerd: nf-md-cog
  local ICON_SRC=""        # nerd: nf-cod-folder_library
  local ICON_DOCS=""       # nerd: nf-md-book
  local ICON_SCRIPTS=""    # nerd: nf-cod-terminal

  # Yazi schema: [icon].dirs for folders only - leave files/exts to catppuccin defaults
  local custom_dirs="  { name = \"nix-config\", text = \"$ICON_NIX_CONFIG\", fg = \"$accent\" },
  { name = \"vaults\", text = \"$ICON_VAULTS\", fg = \"$accent\" },
  { name = \"git\", text = \"$ICON_GIT\", fg = \"$peach\" },
  { name = \"dotfiles\", text = \"$ICON_DOTFILES\", fg = \"$accent\" },
  { name = \"src\", text = \"$ICON_SRC\", fg = \"$sky\" },
  { name = \"docs\", text = \"$ICON_DOCS\", fg = \"$sapphire\" },
  { name = \"scripts\", text = \"$ICON_SCRIPTS\", fg = \"$green\" },"

  # Prepend custom entries to the flavor's own [icon].dirs when it has one
  # (a second `dirs` key is a TOML error); otherwise add the array after [icon].
  local tmp_config="${yazi_config}.tmp"
  awk -v dirs="$custom_dirs" '
    NR == FNR {
      if (/^\[/) in_icon = ($0 == "[icon]")
      else if (in_icon && /^dirs[ \t]*=[ \t]*\[/) has_dirs = 1
      next
    }
    /^\[/ { in_icon = ($0 == "[icon]") }
    in_icon && has_dirs && /^dirs[ \t]*=[ \t]*\[/ { print; print dirs; next }
    !has_dirs && /^\[icon\]$/ { print; print "dirs = ["; print dirs; print "]"; next }
    { print }
  ' "$yazi_config" "$yazi_config" >"$tmp_config" && mv "$tmp_config" "$yazi_config"
}

# Update bat syntax highlighter theme.
# macOS: fish-universal only. Linux: also exports to systemd + hyprland env.
update_bat() {
  local theme="$1"
  local bat_theme
  log_debug "Updating bat to $theme"

  if [[ $theme == "light" ]]; then
    bat_theme="Catppuccin Latte"
  else
    bat_theme="Catppuccin Mocha"
  fi

  fish -c "set -U BAT_THEME '$bat_theme'; true" 2>/dev/null || true
  fish -c "set -gx BAT_THEME '$bat_theme'; true" 2>/dev/null || true

  if [[ ${THEME_APPLY_PLATFORM:-linux} == "linux" ]]; then
    systemctl --user set-environment BAT_THEME="$bat_theme" 2>/dev/null || true
    hyprctl eval "hl.env(\"BAT_THEME\", \"$bat_theme\")" >/dev/null 2>&1 || true
  fi
}

# Update fzf fuzzy finder colors.
# macOS: fish-universal only. Linux: also exports to systemd + hyprland env.
update_fzf() {
  local theme="$1"
  local fzf_colors
  log_debug "Updating fzf to $theme"

  if [[ $theme == "light" ]]; then
    fzf_colors="bg+:$LIGHT_SURFACE0,bg:$LIGHT_BASE,spinner:$LIGHT_ROSEWATER,hl:$LIGHT_RED,fg:$LIGHT_TEXT,header:$LIGHT_RED,info:$LIGHT_MAUVE,pointer:$LIGHT_ROSEWATER,marker:$LIGHT_LAVENDER,fg+:$LIGHT_TEXT,prompt:$LIGHT_MAUVE,hl+:$LIGHT_RED,selected-bg:$LIGHT_SURFACE1,border:$LIGHT_OVERLAY0,label:$LIGHT_TEXT"
  else
    fzf_colors="bg+:$DARK_SURFACE0,bg:$DARK_BASE,spinner:$DARK_ROSEWATER,hl:$DARK_RED,fg:$DARK_TEXT,header:$DARK_RED,info:$DARK_MAUVE,pointer:$DARK_ROSEWATER,marker:$DARK_LAVENDER,fg+:$DARK_TEXT,prompt:$DARK_MAUVE,hl+:$DARK_RED,selected-bg:$DARK_SURFACE1,border:$DARK_OVERLAY0,label:$DARK_TEXT"
  fi

  fish -c "set -U fzf_theme_colors '--color=$fzf_colors'; true" 2>/dev/null || true
  fish -c "
    set -l base_opts (string replace -r -- '--color=[^ ]+\$' '' \$FZF_DEFAULT_OPTS; or true)
    set -U FZF_DEFAULT_OPTS \$base_opts '--color=$fzf_colors'
    true
  " 2>/dev/null || true

  if [[ ${THEME_APPLY_PLATFORM:-linux} == "linux" ]]; then
    systemctl --user set-environment FZF_DEFAULT_OPTS_THEME="--color=$fzf_colors" 2>/dev/null || true
    hyprctl eval "hl.env(\"FZF_DEFAULT_OPTS_THEME\", \"--color=$fzf_colors\")" >/dev/null 2>&1 || true
  fi
}

# Update tmux catppuccin flavor. Socket discovery is platform-aware:
# Linux uses /run/user/<uid>/tmux-<uid>/default; macOS uses tmux's default
# /tmp (or $TMUX when inside a session).
update_tmux() {
  local theme="$1"
  local tmux_flavor
  log_debug "Updating tmux to $theme"

  if [[ $theme == "light" ]]; then
    tmux_flavor="latte"
  else
    tmux_flavor="mocha"
  fi

  local tmux_cmd="tmux"
  if [[ -n ${TMUX:-} ]]; then
    tmux_cmd="tmux"
  elif [[ -S "/run/user/$(id -u)/tmux-$(id -u)/default" ]]; then
    tmux_cmd="tmux -S /run/user/$(id -u)/tmux-$(id -u)/default"
  fi
  # macOS: no /run/user socket; bare `tmux` uses its default socket dir
  # ($TMUX_TMPDIR or /tmp), which is where the lazytmux server listens.

  if ! $tmux_cmd list-sessions &>/dev/null 2>&1; then
    log_debug "tmux not running, skipping"
    return 0
  fi

  # A loaded palette already on the wanted flavor needs no work — that is every
  # `restore` after a rebuild. Worth the early exit: the reload below clears the
  # palette first and only gets it back if the server accepts the config.
  if [[ $($tmux_cmd show-options -gv @catppuccin_flavor 2>/dev/null) == "$tmux_flavor" ]] &&
    [[ -n $($tmux_cmd show-options -gv @thm_bg 2>/dev/null) ]]; then
    log_debug "tmux already on $tmux_flavor, keeping the loaded palette"
    return 0
  fi

  # The flavor files set the palette with `set -ogq`, which refuses to overwrite
  # an option that already holds a value — clearing it is the only way a second
  # flavor ever loads.
  local var
  for var in $($tmux_cmd show-options -g 2>/dev/null | awk '$1 ~ /^@thm_/ {print $1}' | sort -u); do
    $tmux_cmd set -gu "$var" 2>/dev/null || true
  done

  $tmux_cmd set -g @catppuccin_flavor "$tmux_flavor" 2>/dev/null || {
    record_failure "tmux"
    return 1
  }

  local src_err
  if src_err=$($tmux_cmd source-file "$HOME/.config/tmux/tmux.conf" 2>&1); then
    return 0
  fi

  # tmux parses a config as one unit, so a single command the running server
  # does not know discards every line in the file — including the plugin
  # run-shells that reload the palette cleared above, which leaves every
  # `#{@thm_*}` in the status format expanding to nothing. A server that
  # outlived the rebuild generating the config is enough to land here (new
  # tmux and new config, old running binary), so replay the theme plugins the
  # config would have run rather than leave the status bar and window names
  # colorless until the server restarts.
  log_warn "tmux rejected its config, loading the palette directly: $src_err"
  local plugin
  while read -r plugin; do
    $tmux_cmd run-shell "$plugin" 2>/dev/null || true
  done < <(grep -oE '[^" ]+/(catppuccin\.tmux|bin/tmux-apply-theme-colors)' \
    "$HOME/.config/tmux/tmux.conf" 2>/dev/null)

  if [[ -z $($tmux_cmd show-options -gv @thm_bg 2>/dev/null) ]]; then
    record_failure "tmux"
    return 1
  fi
}

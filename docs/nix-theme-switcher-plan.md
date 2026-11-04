# nix-theme-switcher - Design Plan

A Home Manager flake module for declarative dark/light theme switching across desktop applications.

## Problem Statement

Desktop theming on Linux is fragmented. Each application has its own theme format, config location, and reload mechanism. Users wanting consistent dark/light switching must:

1. Maintain separate theme files for each app
2. Write custom scripts to switch between them
3. Handle runtime reloading (some apps need signals, some need restart)
4. Keep colors in sync across 10+ applications

Existing solutions like pywal/matugen generate palettes from wallpapers but don't solve the switching problem.

## Goals

1. **Declarative** - Define dark/light palettes once in Nix, generate all app themes
2. **Modular** - Enable only the apps you use
3. **Extensible** - Users can add custom app modules
4. **Runtime switching** - Single command toggles all enabled apps
5. **Palette-agnostic** - Works with any color scheme (Catppuccin, Dracula, Nord, custom)

## Non-Goals

- Palette generation from images (use matugen/pywal for that, feed output here)
- Application-specific features beyond theming
- System-level theming (Plymouth, GRUB, etc.)

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                     User Configuration                       │
│  programs.theme-switcher.dark = { ... }                      │
│  programs.theme-switcher.light = { ... }                     │
│  programs.theme-switcher.apps.kitty.enable = true            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      Core Module                             │
│  - Validates palette structure                               │
│  - Passes palette to enabled app modules                     │
│  - Generates toggle script based on enabled apps             │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
        ┌──────────┐   ┌──────────┐   ┌──────────┐
        │  Kitty   │   │   Foot   │   │   GTK    │  ... more apps
        │  Module  │   │  Module  │   │  Module  │
        └──────────┘   └──────────┘   └──────────┘
              │               │               │
              ▼               ▼               ▼
        ┌──────────┐   ┌──────────┐   ┌──────────┐
        │ Generate │   │ Generate │   │ Generate │
        │ .conf    │   │ .ini     │   │ .css     │
        └──────────┘   └──────────┘   └──────────┘
```

## Palette Type Design

### Semantic Core (Required)

Every palette must provide these semantic colors:

```nix
{
  name = "mocha";                    # Identifier for filenames
  variant = "dark";                  # "dark" | "light"

  # Backgrounds (dark: dark colors, light: light colors)
  bg = "#1e1e2e";                    # Primary background
  bg-alt = "#181825";                # Alternative/sidebar background
  bg-elevated = "#313244";           # Cards, popups, elevated surfaces

  # Foregrounds
  fg = "#cdd6f4";                    # Primary text
  fg-muted = "#a6adc8";              # Secondary/dimmed text
  fg-subtle = "#6c7086";             # Tertiary/placeholder text

  # Accent
  accent = "#89b4fa";                # Primary accent (links, focus)
  accent-alt = "#b4befe";            # Secondary accent

  # Semantic
  error = "#f38ba8";
  warning = "#f9e2af";
  success = "#a6e3a1";
  info = "#89dceb";

  # Borders/Separators
  border = "#45475a";
  border-muted = "#313244";
}
```

### Extended Palette (Optional)

For richer themes, users can provide additional named colors:

```nix
{
  extended = {
    red = "#f38ba8";
    orange = "#fab387";
    yellow = "#f9e2af";
    green = "#a6e3a1";
    teal = "#94e2d5";
    blue = "#89b4fa";
    purple = "#cba6f7";
    pink = "#f5c2e7";

    # Surface hierarchy (for apps that need it)
    surface0 = "#313244";
    surface1 = "#45475a";
    surface2 = "#585b70";
    overlay0 = "#6c7086";
    overlay1 = "#7f849c";
  };
}
```

### Palette Presets

Ship common palettes as ready-to-use presets:

```nix
# Usage
programs.theme-switcher = {
  dark = inputs.theme-switcher.palettes.catppuccin.mocha;
  light = inputs.theme-switcher.palettes.catppuccin.latte;
};
```

Presets to include:
- Catppuccin (Mocha, Macchiato, Frappe, Latte)
- Dracula / Dracula Pro
- Nord
- Gruvbox (Dark, Light)
- Tokyo Night (Night, Storm, Day)
- One Dark / One Light
- Solarized (Dark, Light)

## App Module Design

Each app module is self-contained and follows this pattern:

```nix
# modules/apps/kitty.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.theme-switcher;
  enabled = cfg.enable && cfg.apps.kitty.enable;

  # Theme generator function
  mkTheme = palette: ''
    foreground ${palette.fg}
    background ${palette.bg}
    cursor ${palette.accent}
    # ... rest of theme
  '';
in {
  options.programs.theme-switcher.apps.kitty = {
    enable = lib.mkEnableOption "kitty theme integration";

    # App-specific options
    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra lines to append to generated theme";
    };
  };

  config = lib.mkIf enabled {
    # Generate theme files
    xdg.configFile = {
      "kitty/themes/${cfg.dark.name}.conf".text = mkTheme cfg.dark;
      "kitty/themes/${cfg.light.name}.conf".text = mkTheme cfg.light;
    };

    # Export toggle commands for the script generator
    programs.theme-switcher.internal.toggleCommands.kitty = {
      # How to apply the theme at runtime
      apply = theme: ''
        if command -v kitty &>/dev/null && [[ -S /tmp/kitty ]]; then
          kitty @ set-colors -a "$XDG_CONFIG_HOME/kitty/themes/${theme}.conf"
        fi
      '';

      # How to detect current theme (for status checks)
      detect = ''
        grep -oP 'include.*/kitty/themes/\K[^.]+' "$XDG_CONFIG_HOME/kitty/kitty.conf"
      '';
    };
  };
}
```

### App Module Checklist

Each app module must provide:

1. **Options** - `enable` + any app-specific settings
2. **Theme generator** - Function `palette -> string` producing the theme file
3. **File output** - `xdg.configFile` entries for both dark and light themes
4. **Toggle commands** - How to apply theme at runtime (if supported)
5. **Detection** - How to detect current theme (for status command)

### Planned App Modules

Phase 1 (Core):
- [ ] kitty
- [ ] foot
- [ ] hyprland (border colors, env vars)
- [ ] waybar
- [ ] gtk3/gtk4/libadwaita

Phase 2 (Extended):
- [ ] swaync
- [ ] rofi/wofi
- [ ] tmux
- [ ] fish/zsh
- [ ] lazygit
- [ ] yazi
- [ ] btop
- [ ] kvantum (Qt)
- [ ] dunst/mako

Phase 3 (Community):
- [ ] neovim (generate lua theme)
- [ ] alacritty
- [ ] wezterm
- [ ] starship
- [ ] bat
- [ ] fzf
- [ ] delta (git)
- [ ] zellij

## Toggle Script Generation

The toggle script is **generated dynamically** based on enabled apps:

```nix
# modules/toggle.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.theme-switcher;

  # Collect toggle commands from all enabled apps
  toggleCommands = lib.filterAttrs (n: v: v != null)
    cfg.internal.toggleCommands;

  # Generate the apply function
  mkApplySection = lib.concatStringsSep "\n" (lib.mapAttrsToList
    (app: cmds: ''
      # ${app}
      ${cmds.apply "$theme_name"}
    '')
    toggleCommands);

  toggle-script = pkgs.writeShellApplication {
    name = "theme-toggle";
    runtimeInputs = with pkgs; [ jq coreutils ];
    text = ''
      STATE_FILE="''${XDG_STATE_HOME:-$HOME/.local/state}/theme-switcher/state.json"
      DARK_THEME="${cfg.dark.name}"
      LIGHT_THEME="${cfg.light.name}"

      get_current_theme() {
        if [[ -f "$STATE_FILE" ]]; then
          jq -r '.theme // "dark"' "$STATE_FILE"
        else
          echo "dark"
        fi
      }

      set_theme() {
        local mode="$1"
        local theme_name

        if [[ "$mode" == "dark" ]]; then
          theme_name="$DARK_THEME"
        else
          theme_name="$LIGHT_THEME"
        fi

        # Apply to all enabled apps
        ${mkApplySection}

        # Save state
        mkdir -p "$(dirname "$STATE_FILE")"
        jq -n --arg theme "$mode" --arg name "$theme_name" \
          '{theme: $theme, name: $name, updated: now | todate}' > "$STATE_FILE"
      }

      case "''${1:-toggle}" in
        dark)  set_theme dark ;;
        light) set_theme light ;;
        toggle)
          current=$(get_current_theme)
          if [[ "$current" == "dark" ]]; then
            set_theme light
          else
            set_theme dark
          fi
          ;;
        status) get_current_theme ;;
        *) echo "Usage: theme-toggle [dark|light|toggle|status]" ;;
      esac
    '';
  };
in {
  # Internal option for apps to register their commands
  options.programs.theme-switcher.internal.toggleCommands = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        apply = lib.mkOption { type = lib.types.functionTo lib.types.str; };
        detect = lib.mkOption { type = lib.types.str; default = ""; };
      };
    });
    default = {};
    internal = true;
  };

  config.home.packages = lib.mkIf cfg.enable [ toggle-script ];
}
```

## Directory Structure

```
nix-theme-switcher/
├── flake.nix
├── flake.lock
├── README.md
├── LICENSE                      # MIT
├── docs/
│   ├── adding-apps.md          # Guide for contributors
│   └── palette-spec.md         # Palette format specification
├── modules/
│   ├── default.nix             # Main entry, imports all
│   ├── options.nix             # Core options + palette type
│   ├── toggle.nix              # Script generator
│   └── apps/
│       ├── default.nix         # Imports all app modules
│       ├── kitty.nix
│       ├── foot.nix
│       ├── hyprland.nix
│       ├── waybar.nix
│       ├── gtk.nix
│       ├── swaync.nix
│       ├── tmux.nix
│       └── ...
├── palettes/
│   ├── default.nix             # Exports all palettes
│   ├── catppuccin.nix
│   ├── dracula.nix
│   ├── nord.nix
│   ├── gruvbox.nix
│   └── ...
└── tests/
    ├── default.nix
    └── kitty-theme-test.nix
```

## Implementation Phases

### Phase 1: Foundation (MVP)

1. Set up flake structure
2. Define palette type with validation
3. Implement core options module
4. Create kitty app module (reference implementation)
5. Implement basic toggle script generator
6. Add Catppuccin palette preset
7. Write README with usage examples

**Deliverable**: Working module that themes kitty with dark/light switching

### Phase 2: Terminal Apps

1. Add foot module
2. Add alacritty module
3. Add tmux module
4. Add fish/zsh modules (shell prompt colors)
5. Add starship module
6. Refine palette type based on learnings

**Deliverable**: Full terminal theming support

### Phase 3: Desktop Environment

1. Add hyprland module (borders, env vars)
2. Add waybar module
3. Add swaync/dunst module
4. Add rofi/wofi module
5. Add GTK3/GTK4/libadwaita module
6. Add kvantum (Qt) module

**Deliverable**: Full Wayland desktop theming

### Phase 4: Developer Tools

1. Add neovim module (generate lua colorscheme)
2. Add lazygit module
3. Add yazi module
4. Add bat/delta module
5. Add fzf module
6. Add btop module

**Deliverable**: Full developer environment theming

### Phase 5: Polish & Community

1. Add more palette presets (Nord, Dracula, Gruvbox, etc.)
2. Write comprehensive documentation
3. Add CI/CD (flake check, test builds)
4. Create example configurations
5. Publish to FlakeHub or similar
6. Write blog post / announcement

## Open Questions

### 1. Palette Structure

Should we enforce a fixed structure or allow flexibility?

**Option A**: Strict semantic palette (current plan)
- Pro: Apps know what colors to expect
- Con: May not map perfectly to all color schemes

**Option B**: Loose typing with required minimum
- Pro: More flexible
- Con: App modules need more fallback logic

**Recommendation**: Start strict, loosen if needed based on feedback.

### 2. State Persistence

Where should theme state live?

**Option A**: JSON file in `~/.local/state/theme-switcher/`
- Pro: Simple, portable
- Con: Another state file to manage

**Option B**: dconf/gsettings
- Pro: Integrates with GNOME ecosystem
- Con: Heavy dependency, not portable

**Option C**: Environment variable (set in shell init)
- Pro: No files
- Con: Doesn't persist across sessions cleanly

**Recommendation**: JSON file (Option A) - simple and works everywhere.

### 3. Initial Theme on Login

How should the system know which theme to apply at session start?

**Option A**: Read from state file, apply in shell init
**Option B**: Systemd user service on login
**Option C**: Hyprland exec-once / desktop autostart

**Recommendation**: Let user configure this (document all options).

### 4. Freedesktop Dark Mode

Should we integrate with `org.freedesktop.appearance.color-scheme`?

- This is what Electron apps, Firefox, etc. read
- Requires dbus/portal integration

**Recommendation**: Yes, but as optional module (requires dconf).

### 5. Naming

Current name: `nix-theme-switcher`

Alternatives:
- `nix-theme-toggle`
- `stylix-lite` (but don't want confusion with stylix)
- `chromatic`
- `themer-nix`
- `duality` (dark/light duality)

**Recommendation**: `nix-theme-switcher` is clear and descriptive.

## Related Projects

- **stylix** - Full system theming, more opinionated, generates from wallpaper
- **nix-colors** - Provides base16 color schemes as Nix attrs
- **base16.nix** - Similar to nix-colors
- **matugen** - Generates Material You palette from wallpaper

This project differs by focusing on **runtime switching** and **explicit palettes** rather than generation or one-time application.

## Success Criteria

1. User can define dark/light palettes once
2. Themes are generated for all enabled apps automatically
3. Single `theme-toggle` command switches everything
4. Adding a new app is straightforward (one file, clear pattern)
5. Works with any color scheme, not just Catppuccin
6. Well-documented with examples

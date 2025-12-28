# Noctalia Shell Migration Plan

This document outlines a detailed plan for migrating from the current Waybar/swaync setup to Noctalia Shell while preserving the existing palette-driven theming system.

## Executive Summary

**Goal**: Adopt Noctalia for a cohesive desktop UI while maintaining:
- Catppuccin Mocha/Latte as stable base themes
- Existing palette-driven theming for terminals and TUI apps
- Vicinae as the primary launcher
- Optional Matugen exploration mode for wallpaper-based themes

## Current System Overview

### Components to Replace

| Component | Current | Noctalia Replacement |
|-----------|---------|---------------------|
| Status Bar | Waybar | Noctalia Bar |
| Notifications | swaync | Noctalia Notification + Toast |
| Dock | nwg-dock | Noctalia Dock |
| Logout Menu | wlogout | Noctalia Panels |
| OSD | Manual scripts | Noctalia OSD |
| Lock Screen | hyprlock | Noctalia LockScreen (optional) |

### Components to Keep

| Component | Reason |
|-----------|--------|
| **Vicinae** | Far more powerful than Noctalia's basic launcher (tmux sessions, project switching) |
| **theme-toggle system** | Covers more apps than Matugen (foot, k9s, lazygit, lazydocker, btop, yazi, etc.) |
| **hyprlock** | Already themed, well-configured (optional: could migrate later) |
| **Terminal themes** | Palette-generated kitty/foot themes are more customized |

### Theming Architecture Comparison

```
CURRENT SYSTEM
──────────────────────────────────────────────────────────
config.theme.palette.{dark,light}
        │
        ├──→ Waybar (CSS variables)
        ├──→ swaync (CSS)
        ├──→ kitty (palette-generated .conf)
        ├──→ foot (palette-generated .ini)
        ├──→ k9s (palette-generated skin)
        ├──→ btop (palette-generated .theme)
        ├──→ lazygit (catppuccin themes)
        ├──→ lazydocker (palette-generated)
        ├──→ yazi (catppuccin themes)
        └──→ ... 15+ apps

NOCTALIA SYSTEM
──────────────────────────────────────────────────────────
Color Source (predefined OR matugen)
        │
        ├──→ Noctalia UI (bar, dock, notifications, OSD)
        ├──→ Terminal themes (kitty, foot, ghostty - bundled)
        └──→ Custom Matugen templates (for other apps)
```

## Migration Phases

### Phase 1: Preparation (No Changes Yet)

#### 1.1 Create Catppuccin Predefined Colorscheme

Create a Nix module that generates Noctalia's colorscheme JSON from the existing palette.

**File**: `home/desktop/noctalia/colorscheme.nix`

```nix
{ config, lib, ... }:
let
  palette = config.theme.palette;

  # Map Catppuccin palette to Material Design 3 roles
  mkNoctaliaScheme = p: {
    mPrimary = p.blue;
    mOnPrimary = p.base;
    mSecondary = p.mauve;
    mOnSecondary = p.base;
    mTertiary = p.green;
    mOnTertiary = p.base;
    mError = p.red;
    mOnError = p.base;
    mSurface = p.base;
    mOnSurface = p.text;
    mSurfaceVariant = p.surface0;
    mOnSurfaceVariant = p.subtext0;
    mOutline = p.overlay0;
    mShadow = p.crust;
    mHover = p.surface1;
    mOnHover = p.text;
  };

  # Generate JSON for Noctalia
  schemeJson = {
    dark = mkNoctaliaScheme palette.dark;
    light = mkNoctaliaScheme palette.light;
  };
in {
  # Place colorscheme in Noctalia's expected location
  xdg.configFile."noctalia/colorschemes/Catppuccin/Catppuccin.json".text =
    builtins.toJSON schemeJson;
}
```

#### 1.2 Create Terminal Theme Files

Noctalia expects terminal themes in a specific structure. Generate these from the palette:

**File**: `home/desktop/noctalia/terminal-themes.nix`

```nix
{ config, lib, ... }:
let
  palette = config.theme.palette;
  s = color: lib.removePrefix "#" color;

  mkKittyTheme = p: ''
    # ${p.name} - Generated for Noctalia
    foreground ${p.text}
    background ${p.base}
    selection_foreground ${p.base}
    selection_background ${p.rosewater}
    cursor ${p.rosewater}
    cursor_text_color ${p.base}

    color0 ${p.surface1}
    color1 ${p.red}
    color2 ${p.green}
    color3 ${p.yellow}
    color4 ${p.blue}
    color5 ${p.pink}
    color6 ${p.teal}
    color7 ${p.subtext1}
    color8 ${p.surface2}
    color9 ${p.red}
    color10 ${p.green}
    color11 ${p.yellow}
    color12 ${p.blue}
    color13 ${p.pink}
    color14 ${p.teal}
    color15 ${p.subtext0}
  '';

  mkFootTheme = p: ''
    [colors]
    foreground=${s p.text}
    background=${s p.base}

    regular0=${s p.surface1}
    regular1=${s p.red}
    regular2=${s p.green}
    regular3=${s p.yellow}
    regular4=${s p.blue}
    regular5=${s p.pink}
    regular6=${s p.teal}
    regular7=${s p.subtext1}

    bright0=${s p.surface2}
    bright1=${s p.red}
    bright2=${s p.green}
    bright3=${s p.yellow}
    bright4=${s p.blue}
    bright5=${s p.pink}
    bright6=${s p.teal}
    bright7=${s p.subtext0}
  '';
in {
  xdg.configFile = {
    # Kitty themes
    "noctalia/colorschemes/Catppuccin/terminal/kitty/Catppuccin-dark.conf".text =
      mkKittyTheme palette.dark;
    "noctalia/colorschemes/Catppuccin/terminal/kitty/Catppuccin-light.conf".text =
      mkKittyTheme palette.light;

    # Foot themes
    "noctalia/colorschemes/Catppuccin/terminal/foot/Catppuccin-dark".text =
      mkFootTheme palette.dark;
    "noctalia/colorschemes/Catppuccin/terminal/foot/Catppuccin-light".text =
      mkFootTheme palette.light;
  };
}
```

#### 1.3 Create Custom Matugen Templates (For Exploration Mode)

When using wallpaper colors, these templates will theme apps Noctalia doesn't cover:

**File**: `home/desktop/noctalia/matugen-templates.nix`

```nix
{ config, ... }:
{
  # User templates configuration
  xdg.configFile."noctalia/user-templates.toml".text = ''
    # Custom Matugen templates for TUI apps
    # These are used when "Use Wallpaper Colors" is enabled

    [templates.k9s]
    input_path = "~/.config/matugen/templates/k9s-skin.yaml"
    output_path = "~/.config/k9s/skins/matugen.yaml"

    [templates.lazygit]
    input_path = "~/.config/matugen/templates/lazygit.yml"
    output_path = "~/.config/lazygit/config.yml"

    [templates.btop]
    input_path = "~/.config/matugen/templates/btop.theme"
    output_path = "~/.config/btop/themes/matugen.theme"

    [templates.lazydocker]
    input_path = "~/.config/matugen/templates/lazydocker.yml"
    output_path = "~/.config/lazydocker/config.yml"
  '';

  # Example k9s Matugen template
  xdg.configFile."matugen/templates/k9s-skin.yaml".text = ''
    k9s:
      body:
        fgColor: "{{colors.on_surface.default.hex}}"
        bgColor: "{{colors.surface.default.hex}}"
        logoColor: "{{colors.primary.default.hex}}"
      prompt:
        fgColor: "{{colors.on_surface.default.hex}}"
        bgColor: "{{colors.surface_container.default.hex}}"
        suggestColor: "{{colors.primary.default.hex}}"
      frame:
        border:
          fgColor: "{{colors.outline.default.hex}}"
          focusColor: "{{colors.primary.default.hex}}"
      # ... (expand as needed)
  '';
}
```

### Phase 2: Install Noctalia (Parallel Setup)

#### 2.1 Add Noctalia Flake Input

**File**: `flake.nix` (add to inputs)

```nix
inputs = {
  # ... existing inputs
  noctalia = {
    url = "github:noctalia-dev/noctalia-shell";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

#### 2.2 Create Noctalia Module

**File**: `home/desktop/noctalia/default.nix`

```nix
{ inputs, config, pkgs, lib, ... }:
let
  isHyprland = config.osConfig.desktop.mode == "hyprland";
in {
  imports = [
    inputs.noctalia.homeModules.default
    ./colorscheme.nix
    ./terminal-themes.nix
    ./matugen-templates.nix
  ];

  config = lib.mkIf isHyprland {
    programs.noctalia-shell = {
      enable = true;

      # Use systemd for auto-start
      systemd.enable = true;

      settings = {
        # Use predefined Catppuccin scheme by default
        colorScheme = {
          useWallpaperColors = false;  # Stable mode
          predefinedScheme = "Catppuccin";
          darkMode = true;  # Default to dark
        };

        # Bar configuration
        bar = {
          enable = true;
          position = "top";
          # Modules similar to current waybar setup
        };

        # Dock configuration
        dock = {
          enable = true;
          position = "bottom";
        };

        # Notifications
        notifications = {
          enable = true;
        };

        # OSD
        osd = {
          enable = true;
        };

        # Disable Noctalia's launcher (keep Vicinae)
        launcher = {
          enable = false;
        };
      };
    };
  };
}
```

#### 2.3 Integrate with Hyprland

Update Hyprland to use Noctalia and keep Vicinae:

**File**: `home/desktop/hyprland/settings/bindings.nix` (modify)

```nix
# Keep Vicinae binding
"$mod, D" = "exec, vicinae";

# Optional: Add Noctalia panel toggle
"$mod, A" = "exec, noctalia-shell --toggle-panel";
```

### Phase 3: Parallel Testing

Run Noctalia alongside existing setup to verify:

#### 3.1 Test Checklist

- [ ] Noctalia bar displays correctly
- [ ] Dark/light theme switching works
- [ ] Notifications appear properly
- [ ] OSD (volume/brightness) works
- [ ] Dock shows running apps
- [ ] Vicinae still launches with $mod+D
- [ ] Terminal themes match Catppuccin
- [ ] hyprlock still works

#### 3.2 Theme Toggle Integration

Update theme-toggle to also switch Noctalia's mode:

**Add to** `home/desktop/hyprland/scripts/sh/theme-toggle.sh`:

```bash
# Update Noctalia dark/light mode
update_noctalia() {
  local theme="$1"
  local dark_mode

  if [[ $theme == "light" ]]; then
    dark_mode="false"
  else
    dark_mode="true"
  fi

  # Noctalia uses dbus for runtime theme switching
  if command -v noctalia-shell &>/dev/null; then
    dbus-send --session --dest=dev.noctalia.shell \
      /dev/noctalia/shell dev.noctalia.shell.SetDarkMode \
      boolean:"$dark_mode" 2>/dev/null || true
  fi
}
```

### Phase 4: Remove Old Components

Once Noctalia is stable, remove replaced components:

#### 4.1 Components to Remove

```nix
# Remove from imports/configuration:
- home/desktop/hyprland/waybar/       # Replaced by Noctalia Bar
- home/desktop/hyprland/swaync/       # Replaced by Noctalia Notifications
- home/desktop/hyprland/nwg-dock/     # Replaced by Noctalia Dock
- home/desktop/hyprland/utils/wlogout.nix  # Replaced by Noctalia Panels
```

#### 4.2 Keep These

```nix
# Keep:
- home/desktop/hyprland/vicinae/      # Primary launcher
- home/desktop/hyprland/utils/screen-lock.nix  # hyprlock (or migrate later)
- home/desktop/theme/                 # Palette system
- home/terminal/btop.nix              # Palette-driven themes
- home/terminal/lazydocker.nix        # Palette-driven themes
- home/kubernetes/default.nix         # k9s palette-driven themes
- home/git/lazygit.nix                # Keep, themed by theme-toggle
```

### Phase 5: Optimization

#### 5.1 Cleanup theme-toggle.sh

Remove functions for replaced components:
- `update_waybar()` - No longer needed
- `update_swaync()` - No longer needed
- `signal_waybar()` - No longer needed

Add:
- `update_noctalia()` - Dark/light mode switching

#### 5.2 Final Directory Structure

```
home/desktop/
├── noctalia/
│   ├── default.nix           # Main Noctalia config
│   ├── colorscheme.nix       # Catppuccin scheme generator
│   ├── terminal-themes.nix   # Terminal theme generator
│   └── matugen-templates.nix # Templates for exploration mode
├── hyprland/
│   ├── vicinae/              # KEEP - Primary launcher
│   ├── scripts/
│   │   └── theme-toggle.nix  # Updated for Noctalia
│   └── settings/             # Hyprland config
└── theme/
    ├── palette.nix           # KEEP - Source of truth
    └── catppuccin.nix        # KEEP - Qt/GTK theming
```

## Rollback Plan

If migration fails, revert by:

1. Set `programs.noctalia-shell.enable = false;`
2. Re-enable waybar/swaync imports
3. Run `nh home switch .`

Keep old configs in a `_deprecated/` folder during migration for easy rollback.

## Timeline Estimate

| Phase | Description | Complexity |
|-------|-------------|------------|
| Phase 1 | Preparation (create modules) | Medium |
| Phase 2 | Install Noctalia parallel | Low |
| Phase 3 | Testing | Low |
| Phase 4 | Remove old components | Low |
| Phase 5 | Optimization | Low |

## Open Questions

1. **Lock screen**: Keep hyprlock or migrate to Noctalia's lock screen?
2. **Exploration mode**: How often would you actually use wallpaper-derived colors?
3. **Noctalia stability**: Is it stable enough for daily use on NixOS unstable?

## References

- [Noctalia Documentation](https://docs.noctalia.dev)
- [Noctalia GitHub](https://github.com/noctalia-dev/noctalia-shell)
- [Noctalia Colorschemes](https://github.com/noctalia-dev/noctalia-colorschemes)
- [Matugen Documentation](https://github.com/InioX/matugen)
- [Material Design 3 Color System](https://m3.material.io/styles/color/overview)

# NixOS Configuration Refactoring Plan

## Overview

This document outlines a comprehensive refactoring strategy for the NixOS configuration repository, moving from the current structure to a more maintainable, scalable hybrid approach that balances structural clarity with conditional logic efficiency.

## Current Issues Identified

### High Priority Issues

- **Typo**: `nixos/virutalization/` → should be `virtualization`
- **Package duplication**: Firefox defined in both `nixos/packages.nix` and `home/browsers/`
- **Inconsistent stateVersion**: Hardcoded across multiple files
- **Profile inconsistency**: `flake.nix:48` uses `profile.type` instead of `profile`

### Medium Priority Issues

- **Complex Hyprland structure**: Deep nested hierarchy with 8 subdirectories
- **Hardcoded monitor serials**: Samsung monitor IDs repeated 8 times in kanshi config
- **Inconsistent conditional patterns**: Mix of `osConfig` and local `config` usage
- **Duplicate shell aliases**: `naspi-rebuild-switch` defined in both ThinkPad hosts

## Target Architecture

### Design Principles

1. **Profile Clarity**: Work = business tools only, Personal = development + personal tools
2. **Hybrid Structure**: Files for complex configs, conditionals for simple logic
3. **Clear Separation**: NixOS (system) vs Home Manager (user) boundaries
4. **Scalable Hosts**: Template-based approach for easy machine addition

### Target Directory Structure

```
nix-config/
├── flake.nix
├── options.nix
├── lib/
│   └── default.nix
│
├── nixos/                  # System configurations
│   ├── default.nix
│   ├── core.nix           # Boot, users, locale, networking
│   ├── desktop/           # Desktop environments
│   │   ├── default.nix    # Conditional loader
│   │   ├── kde.nix        # KDE system config
│   │   ├── hyprland.nix   # Hyprland system config
│   │   └── shared.nix     # Common desktop (audio, fonts, display)
│   ├── hardware.nix       # All hardware types with conditionals
│   ├── packages.nix       # System packages with conditionals
│   └── services.nix       # Virtualization, security, etc.
│
├── home/                   # User configurations
│   ├── default.nix
│   ├── apps/              # Applications
│   │   ├── default.nix    # Conditional loader + simple apps
│   │   ├── browsers.nix   # Firefox + Chrome configs
│   │   ├── editors.nix    # Neovim + VSCode + configs
│   │   └── development.nix # Git + Docker + dev tools (always available)
│   ├── desktop/
│   │   ├── default.nix    # Conditional loader
│   │   ├── kde.nix        # Plasma-manager + KDE apps
│   │   ├── hyprland.nix   # Hyprland config + services
│   │   └── shared.nix     # GTK, fonts, cursors
│   ├── terminal.nix       # All terminal tools
│   └── packages.nix       # User packages with conditionals
│
└── hosts/                  # Host-specific configurations
    ├── common.nix         # Shared host configuration
    ├── work-laptop/       # KDE default + Hyprland specialization
    ├── personal-desktop/  # Hyprland only
    └── server/            # Minimal server setup
```

## Profile Strategy

### Work Profile

**Purpose**: Business productivity and corporate requirements
**Desktop**: KDE (default) + Hyprland (specialization)
**Packages**:

- Communication: Slack, Zoom, Teams
- Cloud/DevOps: AWS CLI, Kubectl, Terraform
- Corporate tools only

### Personal Profile

**Purpose**: Personal development and creative work
**Desktop**: Hyprland only
**Packages**:

- Development tools: Git, Docker, Node.js, Python, Rust, Go
- Creative apps: OBS, media tools
- Personal productivity tools

### Development Tools Strategy

- **Always available**: Development happens on personal time too
- **Smart configuration**: Git email switches based on profile
- **Work additions**: Corporate-specific tools (AWS configs, enterprise tools)

### Hardware-Specific Configuration Strategy

For hardware-specific configurations (e.g., EasyEffects profiles for specific ThinkPad models):

**Enhanced Options System**:

```nix
# options.nix - Add hardware detection
hardware.laptop.model = lib.mkOption {
  type = lib.types.enum ["thinkpad-p14s-g4" "thinkpad-p14s-g5" "other"];
  default = "other";
  description = "Specific laptop model for hardware optimizations";
};
```

**Conditional Hardware Loading**:

```nix
# home/apps/default.nix
{ osConfig, lib, ... }: {
  imports = lib.optionals
    (builtins.elem osConfig.hardware.laptop.model ["thinkpad-p14s-g4" "thinkpad-p14s-g5"])
    [ ./audio/easyeffects-thinkpad.nix ];
}

# home/apps/audio/easyeffects-thinkpad.nix
{ pkgs, ... }: {
  services.easyeffects = {
    enable = true;
    preset = "thinkpad-p14s-optimized";
  };

  xdg.configFile."easyeffects/output/thinkpad-p14s-optimized.json".source =
    ./presets/thinkpad-p14s-g4-g5.json;
}
```

This approach enables clean hardware-specific configurations while maintaining modularity.

## Implementation Strategy

### Phase 1: Foundation Fixes (Low Risk)

**Estimated Time**: 1-2 hours
**Risk Level**: Low

1. **Fix typo**: Rename `virutalization` → `virtualization`
2. **Add stateVersion to options.nix**:
   ```nix
   stateVersion = lib.mkOption {
     type = lib.types.str;
     default = "23.05";
     description = "NixOS state version";
   };
   ```
3. **Add hardware detection to options.nix**:
   ```nix
   hardware.laptop.model = lib.mkOption {
     type = lib.types.enum ["thinkpad-p14s-g4" "thinkpad-p14s-g5" "other"];
     default = "other";
     description = "Specific laptop model for hardware optimizations";
   };
   ```
4. **Fix profile reference**: `flake.nix:48` `profile.type` → `profile`
5. **Remove Firefox duplication**: Keep only in `home/browsers/`

### Phase 2: Structure Setup (Medium Risk)

**Estimated Time**: 3-4 hours
**Risk Level**: Medium

1. **Create new directory structure**
2. **Implement conditional loaders**:
   ```nix
   # Example: home/apps/default.nix
   { osConfig, lib, ... }: {
     imports = [
       ./browsers.nix
       ./editors.nix
       ./development.nix  # Always available
     ];

     home.packages = with pkgs;
       [ core-apps ]
       ++ lib.optionals (osConfig.profile == "work") [
         slack zoom-us awscli2 kubectl
       ];
   }
   ```

### Phase 3: Migration & Consolidation (Higher Risk)

**Estimated Time**: 4-6 hours
**Risk Level**: Medium-High

1. **Migrate existing configs** to new structure
2. **Consolidate duplicate configurations**
3. **Implement smart conditionals**
4. **Create host templates**
5. **Update host configurations**

### Phase 4: Advanced Features (Optional)

**Estimated Time**: 2-3 hours
**Risk Level**: Low

1. **Parameterize monitor configurations**
2. **Create shared shell aliases module**
3. **Implement host templates**
4. **Add validation helpers**

## Hybrid Rules

### Use Separate Files When:

- Complex configuration (>50 lines per condition)
- Many program options (browsers, editors with extensive settings)
- Desktop environments (different enough to warrant separation)
- Host-specific configurations (always separate)

### Use Conditional Logic When:

- Simple package lists
- Small configuration differences
- Related functionality (terminal tools)
- Feature flags

## Safety Measures

### Testing Strategy

1. **Backup current config**: `git branch refactor-backup`
2. **Test each phase**: Use `nh os test` before applying
3. **Incremental approach**: Apply changes in small batches
4. **Rollback plan**: Keep specializations for easy rollback

### Validation Commands

```bash
# Test without applying
nh os test

# Build without specializations
nh os build -S

# Apply changes
nh os switch

# Format code
treefmt
```

## Expected Benefits

### Maintainability

- **30% reduction** in code duplication
- **Clear ownership** of configurations
- **Consistent patterns** across all modules

### Scalability

- **Template-based** host creation
- **Profile-aware** conditional loading
- **Easy addition** of new machines/users

### Usability

- **Logical grouping** of related functionality
- **Reduced mental overhead** for navigation
- **Clear separation** of concerns

## Migration Checklist

### Pre-Migration

- [ ] Backup current configuration
- [ ] Document current host-specific settings
- [ ] Test current configuration builds successfully

### Phase 1: Foundation

- [ ] Fix directory typo
- [ ] Add stateVersion option
- [ ] Fix profile reference
- [ ] Remove package duplication
- [ ] Test builds

### Phase 2: Structure

- [ ] Create new directory structure
- [ ] Implement conditional loaders
- [ ] Test new structure
- [ ] Validate all conditionals work

### Phase 3: Migration

- [ ] Migrate nixos configs
- [ ] Migrate home configs
- [ ] Update host configurations
- [ ] Test all machines build
- [ ] Test specializations work

### Phase 4: Validation

- [ ] Test all profiles (work/personal)
- [ ] Test all desktop environments
- [ ] Test all machine types
- [ ] Verify no functionality lost
- [ ] Format all code

### Post-Migration

- [ ] Update documentation
- [ ] Create host templates
- [ ] Document new patterns
- [ ] Archive old structure

## Rollback Plan

If issues arise during migration:

1. **Immediate rollback**: `git checkout refactor-backup`
2. **Partial rollback**: Revert specific commits
3. **Specialization fallback**: Use existing specializations
4. **Incremental fix**: Address issues in small batches

## Success Criteria

- [ ] All current functionality preserved
- [ ] Reduced code duplication
- [ ] Consistent conditional patterns
- [ ] Successful builds for all hosts
- [ ] Working specializations
- [ ] Clean, formatted codebase
- [ ] Updated documentation

---

_This plan provides a systematic approach to refactoring while maintaining system stability and functionality._


# ZSH to Fish Shell Migration Plan

## Overview

This document outlines the migration plan from Zsh to Fish shell for the nix-config repository. Fish shell provides modern shell features out-of-the-box with better syntax highlighting, autocompletion, and web-based configuration.

## Current Zsh Configuration Analysis

### Core Features in Use
- **Oh My Zsh**: Framework with plugins (git, python, docker, docker-compose, poetry, aws, localstack, golang)
- **Plugins**: 
  - `forgit` - Interactive git commands with fzf
  - `zsh-vi-mode` - Vi-style key bindings
- **Auto-suggestions**: Command completion suggestions
- **Syntax highlighting**: Command syntax highlighting
- **History**: 10,000 commands stored in XDG data directory
- **Custom functions**: `auto-ls-ll` for automatic directory listing

### Tools Integration
- **Zoxide**: Smart directory navigation
- **FZF**: Fuzzy finder with custom keybindings
- **Eza**: Modern ls replacement with icons and git integration
- **Starship**: Cross-shell prompt
- **Yazi**: File manager with shell integration

### Environment & Aliases
- Custom aliases: `ll`, `tree`, `update`
- Work-specific aliases loaded from `/etc/agenix/work_aliases.zsh`
- Host environment variables from `/etc/agenix/host_env.env`
- Locale settings (UTF-8)

## Migration Strategy

### Phase 1: Basic Fish Setup
1. **Install Fish**: Add fish shell to home packages
2. **Basic Configuration**: Set up fish as default shell
3. **Essential Aliases**: Migrate core aliases (`ll`, `tree`, `update`)
4. **History Migration**: Configure fish history settings

### Phase 2: Tool Integration
1. **Zoxide**: Enable fish integration (`enableFishIntegration = true`)
2. **FZF**: Configure fzf for fish with existing options
3. **Starship**: Already cross-shell compatible
4. **Yazi**: Enable fish integration
5. **Eza**: Ensure aliases work correctly in fish

### Phase 3: Advanced Features
1. **Vi Mode**: Configure fish vi-mode (built-in)
2. **Custom Functions**: 
   - Convert `auto-ls-ll` function to fish syntax
   - Implement directory change hooks for auto-ls
3. **Autocompletion**: Configure fish completions for tools
4. **Syntax Highlighting**: Fish has this built-in

### Phase 4: Plugin Equivalents
1. **Git Integration**: Use fish's built-in git features or fisher plugins
2. **Docker/Python/AWS**: Find fish equivalents or create custom functions
3. **Forgit**: Check if it supports fish or find alternatives
4. **Work Environment**: Adapt work aliases and env loading for fish syntax

### Phase 5: Cleanup & Testing
1. **Test all functionality**: Ensure all commands and tools work
2. **Performance comparison**: Verify fish startup time
3. **Backup zsh config**: Keep zsh config as fallback initially
4. **Update documentation**: Update CLAUDE.md with fish information

## Implementation Details

### File Structure Changes
```
home/terminal/
├── default.nix        # Update imports
├── fish/              # New fish configuration
│   └── default.nix    # Fish-specific config
├── zsh/               # Keep as backup initially
│   └── default.nix
└── ...
```

### Key Configuration Mappings

| Zsh Feature | Fish Equivalent |
|-------------|-----------------|
| `oh-my-zsh` | Built-in features + fisher plugins |
| `autosuggestion` | Built-in autosuggestions |
| `syntaxHighlighting` | Built-in syntax highlighting |
| `shellAliases` | `programs.fish.shellAliases` |
| `zsh-vi-mode` | `fish_vi_key_bindings` (built-in) |
| Custom functions | Fish functions in `functions/` |
| `initContent` | `programs.fish.interactiveShellInit` |
| `loginExtra` | `programs.fish.loginShellInit` |

### Environment Loading Strategy
Fish syntax for loading work environment:
```fish
# Work aliases
if test -f /etc/agenix/work_aliases.fish
    echo "Loading Work Aliases"
    source /etc/agenix/work_aliases.fish
end

# Host environment
if test -f /etc/agenix/host_env.env
    echo "Loading Host Env"
    # Fish can source bash-style env files with some adaptation
end
```

### Custom Function Migration
```fish
# auto-ls-ll function in fish
function auto-ls-ll
    eza -l --icons --git
end

# Directory change hook
function __auto_ls --on-variable PWD
    if test "$AUTO_LS_COMMANDS" = "ll"
        auto-ls-ll
    end
end
```

## Migration Risks & Mitigation

### Risks
1. **Oh-My-Zsh Plugin Dependencies**: Some functionality might be lost
2. **Custom Script Compatibility**: Work aliases might need conversion
3. **Vi-mode Differences**: Fish vi-mode might behave differently
4. **Environment Variable Loading**: Bash-style env files might need adaptation

### Mitigation Strategies
1. **Gradual Migration**: Keep both shells available during transition
2. **Test Environment**: Test all functionality in a separate branch
3. **Plugin Research**: Find fish alternatives for missing oh-my-zsh plugins
4. **Script Conversion**: Convert bash/zsh scripts to fish syntax where needed
5. **Fallback Plan**: Keep zsh configuration as backup

## Success Criteria

- [ ] All current aliases and functions work
- [ ] Tool integrations (zoxide, fzf, eza, yazi) function correctly  
- [ ] Vi-mode works as expected
- [ ] Work environment loading works
- [ ] History and autocompletion work
- [ ] Startup time is equal or better than zsh
- [ ] All git workflows remain functional
- [ ] Docker and development tools work correctly

## Timeline

- **Week 1**: Phase 1 & 2 (Basic setup and tool integration)
- **Week 2**: Phase 3 & 4 (Advanced features and plugins)
- **Week 3**: Phase 5 (Testing and cleanup)
- **Week 4**: Full migration and zsh config removal

## Resources

- [Fish Shell Documentation](https://fishshell.com/docs/current/)
- [Fisher Plugin Manager](https://github.com/jorgebucaran/fisher)
- [Fish Vi-mode](https://fishshell.com/docs/current/interactive.html#vi-mode)
- [Home Manager Fish Options](https://nix-community.github.io/home-manager/options.html#opt-programs.fish.enable)

## Notes

- Fish has excellent defaults, reducing configuration complexity
- Web-based configuration available via `fish_config`
- Better error messages and user-friendly syntax
- No need for complex plugin managers - built-in package management
- Consider using `fisher` for additional plugins if needed
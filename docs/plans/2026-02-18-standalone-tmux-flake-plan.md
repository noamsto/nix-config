# Standalone Tmux Flake Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract the tmux configuration from nix-config into a standalone flake at `github:noamsto/tmux-config` that works with `nix run`.

**Architecture:** A Nix flake using flake-parts that builds a wrapped tmux binary. The wrapper passes `-f <generated-tmux.conf>` and puts all helper scripts in PATH. Plugins are loaded via `run-shell` in the generated config. No Home Manager required.

**Tech Stack:** Nix flakes, flake-parts, makeWrapper, writeShellScriptBin, tmux 3.4+

**Source repo:** `/home/noams/nix-config` (files to copy from)
**Target repo:** New directory, will become `github:noamsto/tmux-config`

---

### Task 1: Create repo skeleton and flake.nix

**Files:**
- Create: `~/tmux-config/flake.nix`
- Create: `~/tmux-config/.gitignore`

**Step 1: Create the repo directory and init git**

```bash
mkdir -p ~/tmux-config && cd ~/tmux-config && git init
```

**Step 2: Create `.gitignore`**

```
result
.direnv
```

**Step 3: Create `flake.nix`**

The flake uses flake-parts and exposes two packages: `default` (tmux-wrapped) and `wt`.

```nix
{
  description = "Opinionated tmux configuration with Claude Code integration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];

      perSystem = {pkgs, lib, ...}: let
        tmuxConfig = import ./config/tmux.conf.nix {inherit pkgs lib;};
      in {
        packages = {
          default = tmuxConfig.tmux-wrapped;
          wt = import ./wt {inherit pkgs;};
        };
      };
    };
}
```

**Step 4: Stage and verify flake structure**

```bash
git add -A && nix flake check
```

This will fail (missing files) — that's expected. Just verify the flake parses.

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: initial flake skeleton"
```

---

### Task 2: Copy scripts from nix-config

**Files:**
- Create: `~/tmux-config/scripts/claude-status.sh` (copy from nix-config)
- Create: `~/tmux-config/scripts/claude-status-update.sh`
- Create: `~/tmux-config/scripts/tmux-reflow-windows.sh`
- Create: `~/tmux-config/scripts/tmux-session-picker.sh`
- Create: `~/tmux-config/scripts/tmux-window-picker.sh`
- Create: `~/tmux-config/scripts/tmux-branch-display.sh`
- Create: `~/tmux-config/scripts/tmux-dir-display.sh`
- Create: `~/tmux-config/scripts/tmux-set-pane-border.sh`

**Step 1: Copy all 8 scripts**

```bash
mkdir -p ~/tmux-config/scripts
for s in claude-status claude-status-update tmux-reflow-windows tmux-session-picker tmux-window-picker tmux-branch-display tmux-dir-display tmux-set-pane-border; do
  cp ~/nix-config/home/terminal/tmux/scripts/${s}.sh ~/tmux-config/scripts/
done
```

**Step 2: Run shellcheck on all scripts**

```bash
shellcheck ~/tmux-config/scripts/*.sh
```

Fix any issues (there shouldn't be any since these are already checked).

**Step 3: Commit**

```bash
cd ~/tmux-config && git add scripts/ && git commit -m "feat: add helper scripts"
```

---

### Task 3: Copy wt tool

**Files:**
- Create: `~/tmux-config/wt/wt.sh`
- Create: `~/tmux-config/wt/default.nix`

**Step 1: Copy wt files**

```bash
mkdir -p ~/tmux-config/wt
cp ~/nix-config/home/terminal/wt/wt.sh ~/tmux-config/wt/
```

**Step 2: Create `wt/default.nix`**

```nix
{pkgs}:
pkgs.writeShellApplication {
  name = "wt";
  runtimeInputs = with pkgs; [git tmux gum zoxide];
  text = builtins.readFile ./wt.sh;
}
```

**Step 3: Verify wt builds**

```bash
cd ~/tmux-config && git add -A && nix build .#wt
```

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: add wt (git worktree) tool"
```

---

### Task 4: Create the tmux config generator

This is the core task. The file `config/tmux.conf.nix` returns `{ tmux-wrapped, tmuxConf }` — the wrapped binary and the config file.

**Files:**
- Create: `~/tmux-config/config/tmux.conf.nix`

**Step 1: Create `config/tmux.conf.nix`**

This file must:
1. Define custom plugin builds (catppuccin, nerd-font-window-name)
2. Define the nerd font YAML config
3. Build all 8 scripts as `writeShellScriptBin` packages
4. Generate the tmux.conf with all Nix store paths interpolated
5. Create the wrapped tmux binary

Key Nix interpolations in the config (4 total):
- `${continuum}/share/tmux-plugins/continuum/scripts/continuum_save.sh` — status-format[0]
- `${lib.getExe pkgs.gum}` — sesh popup keybinding (REMOVE — sesh not included)
- `${tmux-nerd-font-window-name}/share/...` — run-shell for nerd font plugin
- `${pkgs.tmuxPlugins.fingers}/share/...` — run-shell for fingers plugin

Config sections to REMOVE from nix-config's extraConfig:
- `bind-key "K"` sesh popup (references `sesh` and `gum`)
- `bind-key "S"` sesh fzf picker (references `sesh`, `fzf-tmux`, `sesh-preview`, `fd`)
- `bind -n M-b` sidebar toggle (references `tmux-sidebar`)

```nix
{pkgs, lib}: let
  # --- Custom plugins ---
  catppuccin = pkgs.tmuxPlugins.mkTmuxPlugin rec {
    pluginName = "catppuccin";
    version = "2.1.3";
    src = pkgs.fetchFromGitHub {
      owner = "catppuccin";
      repo = "tmux";
      rev = "v${version}";
      sha256 = "0v3vji240mykfxf573kpwjmnswil0f9j7srqlhq74ca9ar1h5k92";
    };
    meta = with lib; {
      description = "Catppuccin theme for Tmux";
      homepage = "https://github.com/catppuccin/tmux";
      license = licenses.mit;
      platforms = platforms.all;
    };
  };

  nerd-font-wn = pkgs.tmuxPlugins.mkTmuxPlugin {
    pluginName = "tmux-nerd-font-window-name";
    version = "2025-03-21";
    src = pkgs.fetchFromGitHub {
      owner = "joshmedeski";
      repo = "tmux-nerd-font-window-name";
      rev = "9a66e18972de25c0bb3a58b7422d6e6555f166ba";
      sha256 = "sha256-X4Li6xkxKjqac7xedCNzzSoW7wT6N2oqVKIx7TFay64=";
    };
  };

  # --- Nerd font YAML config ---
  yamlFormat = pkgs.formats.yaml {};
  nerdFontConfig = yamlFormat.generate "tmux-nerd-font-window-name.yml" {
    config = {
      fallback-icon = "";
      multi-pane-icon = "";
      show-name = false;
      icon-position = "left";
    };
    icons = {
      claude = "🤖";
      ".claude-wrapper_" = "🤖";
      nh = "❄️";
      nix = "❄️";
      fish = "🐟";
      process-compose = "⚙️";
      amp = "🧠";
    };
  };

  # --- Helper scripts ---
  mkScript = name: pkgs.writeShellScriptBin name (builtins.readFile ../scripts/${name}.sh);
  scriptNames = [
    "claude-status"
    "claude-status-update"
    "tmux-reflow-windows"
    "tmux-session-picker"
    "tmux-window-picker"
    "tmux-branch-display"
    "tmux-dir-display"
    "tmux-set-pane-border"
  ];
  scripts = map mkScript scriptNames;

  # --- Plugins from nixpkgs ---
  inherit (pkgs) tmuxPlugins;

  # --- Plugin configs (loaded before extraConfig by HM; we inline them) ---
  pluginConfigs = ''
    # catppuccin
    if-shell '[ -z "#{@catppuccin_flavor}" ]' 'set -g @catppuccin_flavor mocha'
    set -g @catppuccin_status_background 'none'
    set -g @catppuccin_window_status_style 'none'
    set -g @catppuccin_window_flags 'icon'
    set -g @catppuccin_window_flags_icon_last " 󰖰"
    set -g @catppuccin_window_flags_icon_current " 󰖯"
    set -g @catppuccin_window_flags_icon_zoom " 󰁌"
    set -g @catppuccin_window_flags_icon_mark " 󰃀"
    set -g @catppuccin_window_flags_icon_silent " 󰂛"
    set -g @catppuccin_window_flags_icon_activity " 󱅫"
    set -g @catppuccin_window_flags_icon_bell " 󰂞"
    set -g @catppuccin_pane_status_enabled 'off'
    set -g @catppuccin_pane_border_status 'off'

    # resurrect
    set -g @resurrect-strategy-vim 'session'
    set -g @resurrect-strategy-nvim 'session'
    set -g @resurrect-capture-pane-contents 'on'

    # continuum
    set -g @continuum-restore 'on'
    set -g @continuum-save-interval '10'
  '';

  # --- Plugin run-shell lines ---
  # Home Manager normally generates these from the plugins list.
  # We do it manually here. Order matters: sensible first, then theme, then others.
  pluginRunShells = ''
    run-shell ${tmuxPlugins.sensible.rtp}
    run-shell ${tmuxPlugins.better-mouse-mode.rtp}
    run-shell ${catppuccin.rtp}
    run-shell ${tmuxPlugins.resurrect.rtp}
    run-shell ${tmuxPlugins.vim-tmux-navigator.rtp}
    run-shell ${tmuxPlugins.tmux-fzf.rtp}
    run-shell ${tmuxPlugins.continuum.rtp}
  '';

  # --- Generated tmux.conf ---
  tmuxConf = pkgs.writeText "tmux.conf" ''
    # === Base Settings ===
    set -g default-terminal "tmux-256color"
    set -g history-limit 1500000
    set -g base-index 1
    setw -g pane-base-index 1

    # === Plugin Configs (must be set before run-shell) ===
    ${pluginConfigs}

    # === Plugin Loading ===
    ${pluginRunShells}

    # === Main Config ===
    set -g mouse on
    set -g window-size smallest
    set -g aggressive-resize on

    # Vi mode
    set-window-option -g mode-keys vi
    bind-key -T copy-mode-vi v send-keys -X begin-selection
    bind-key -T copy-mode-vi C-v send-keys -X rectangle-toggle
    bind-key -T copy-mode-vi y send-keys -X copy-selection-and-cancel

    # Smart pane splitting (inherit current path)
    bind '"' split-window -v -c "#{pane_current_path}"
    bind % split-window -h -c "#{pane_current_path}"
    bind c new-window -c "#{pane_current_path}"

    # Resize panes
    bind -r -T prefix M-Up    resize-pane -U 5
    bind -r -T prefix M-Down  resize-pane -D 5
    bind -r -T prefix M-Left  resize-pane -L 5
    bind -r -T prefix M-Right resize-pane -R 5

    # Alt-shift window navigation
    bind -n M-H previous-window
    bind -n M-L next-window

    # Session/window pickers (wrappers pre-compute claude status)
    bind s run-shell 'tmux-session-picker'
    bind w run-shell 'tmux-window-picker'

    # New session prompt
    bind N command-prompt -p "New session name:" "new-session -s '%%'"

    bind-key x kill-pane
    bind-key & confirm-before -p "kill-window #W? (y/n)" kill-window
    set -g detach-on-destroy off

    # Vim-tmux navigation (respects zoom)
    is_vim="ps -o state= -o comm= -t '#{pane_tty}' | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|l?n?vim?x?|fzf)(diff)?$'"
    bind-key -n C-h if-shell "$is_vim" "send-keys C-h" "if-shell '[ #{window_zoomed_flag} -eq 0 ]' 'select-pane -L'"
    bind-key -n C-j if-shell "$is_vim" "send-keys C-j" "if-shell '[ #{window_zoomed_flag} -eq 0 ]' 'select-pane -D'"
    bind-key -n C-k if-shell "$is_vim" "send-keys C-k" "if-shell '[ #{window_zoomed_flag} -eq 0 ]' 'select-pane -U'"
    bind-key -n C-l if-shell "$is_vim" "send-keys C-l" "if-shell '[ #{window_zoomed_flag} -eq 0 ]' 'select-pane -R'"

    # Window titles
    set-option -g set-titles on
    set-option -g set-titles-string "#S / #{pane_current_command}"

    # === Status Bar (Catppuccin + multi-line) ===
    set -g allow-rename off
    set -g status-position top
    set -g status-interval 1
    set -g status-style "bg=#{@thm_bg}"

    # Multi-line status bar (tmux 3.4+)
    set -g status 2
    set -g @window_split 999
    set -g @window_split2 999

    # Icon variables
    set -g @icon_session ""
    set -g @icon_branch ""
    set -g @icon_dir ""

    # Line 0: Session / Branch / Dir (left) | Claude status (right)
    set -g status-format[0] "#(${tmuxPlugins.continuum}/share/tmux-plugins/continuum/scripts/continuum_save.sh)#[align=left,bg=#{@thm_bg}]#{?client_prefix,#[fg=#{@thm_red}#,bold],#[fg=#{@thm_mauve}]} #{@icon_session} #S  #[fg=#{@thm_blue},bold]#{@icon_branch} #(tmux-branch-display '#{@branch}' '#{pane_current_path}')  #[fg=#{@thm_subtext_0},nobold]#{@icon_dir} #(tmux-dir-display '#{@branch}' '#{pane_current_path}') #[align=right,fg=#{@thm_overlay_1}]#(claude-status --session '#{session_name}' --format icon-color) "

    # Lines 1-3: Window list (dynamically generated by tmux-reflow-windows hook)
    set -g status-format[1] "#[align=left,bg=#{@thm_bg}]#[fg=#{@thm_overlay_1}] ╰─ #{W:#[range=window|#{window_index}]#{?window_active,#[fg=#{@thm_green}#,bold]#{window_index}: #{window_name},#[fg=#{@thm_subtext_0}#,nobold]#{window_index}: #[fg=#{@thm_fg}]#{window_name}}#{?window_zoomed_flag, 󰁌,}#(claude-status --window '#{session_name}:#{window_index}')#[norange]#{?window_end_flag,, #[fg=#{@thm_subtext_0}#,nobold]│ }}"
    set -g status-format[2] ""
    set -g status-format[3] ""

    # Hooks to reflow windows across status lines
    set-hook -g window-linked      'run-shell "tmux-reflow-windows #{session_name} #{client_width}"'
    set-hook -g window-unlinked    'run-shell "tmux-reflow-windows #{session_name} #{client_width}"'
    set-hook -g window-renamed     'run-shell "tmux-reflow-windows #{session_name} #{client_width}"'
    set-hook -g client-resized     'run-shell "tmux-reflow-windows #{session_name} #{client_width}"'
    set-hook -g after-new-session   'run-shell "tmux-reflow-windows #{session_name} #{client_width}"'
    set-hook -g client-session-changed 'run-shell "tmux-reflow-windows #{session_name} #{client_width}"'

    # Pane borders
    setw -g pane-border-status top
    setw -g pane-border-format "━━━━━"
    setw -g pane-active-border-style "bg=#{@thm_bg},fg=#{@thm_mauve}"
    setw -g pane-border-style "bg=#{@thm_bg},fg=#{@thm_overlay_1}"
    setw -g pane-border-lines heavy

    # Pane background: dim inactive
    set -g window-style "fg=#{@thm_text},bg=#{@thm_mantle}"
    set -g window-active-style "fg=#{@thm_text},bg=#{@thm_bg}"

    # Pane scrollbars (tmux 3.6+) - disabled
    set -g pane-scrollbars off

    # Prompt cursor styling (tmux 3.6+)
    set -g prompt-cursor-style "blinking-bar"
    set -g prompt-cursor-colour "colour183"

    # Window naming: nerd font icon + branch or dir name
    set -wg automatic-rename on
    set -g automatic-rename-format "#{window_icon} #{?#{@branch},#{=20:@branch}#{?#{==:#{=20:@branch},#{@branch}},,…},#{b:pane_current_path}}"

    # Nerd font window name plugin
    run-shell ${nerd-font-wn}/share/tmux-plugins/tmux-nerd-font-window-name/tmux-nerd-font-window-name.tmux

    # tmux-fingers (smart copy)
    set -g @fingers-hint-style "fg=colour234,bg=colour183,bold"
    set -g @fingers-highlight-style "fg=colour216,bg=colour236"
    set -g @fingers-selected-hint-style "fg=colour234,bg=colour151,bold"
    set -g @fingers-selected-highlight-style "fg=colour116,bg=colour236"
    set -g @fingers-pattern-0 "[A-Z]{2,}-[0-9]+"
    set -g @fingers-pattern-1 "[a-z][a-z_]*_[0-9a-hjkmnp-tv-z]{26}"
    set -g @fingers-pattern-2 "sha256-[A-Za-z0-9+/]{43}="
    set -g @fingers-pattern-3 "sha256:[0-9a-z]{52}"
    run-shell ${tmuxPlugins.fingers}/share/tmux-plugins/tmux-fingers/tmux-fingers.tmux

    # Reload config on first attach (workaround for tmux-fingers colors)
    set-hook -g client-attached[99] 'source-file ~/.config/tmux/tmux.conf'

    # Set pane-border-format with expanded colors (must run after catppuccin loads)
    run-shell "tmux-set-pane-border"
  '';

  # --- XDG config directory for nerd font YAML ---
  # The nerd font plugin reads from ~/.config/tmux/tmux-nerd-font-window-name.yml
  # We create a wrapper that sets XDG_CONFIG_HOME to include our config
  nerdFontConfigDir = pkgs.runCommand "tmux-nerd-font-config" {} ''
    mkdir -p $out/tmux
    cp ${nerdFontConfig} $out/tmux/tmux-nerd-font-window-name.yml
  '';

  # --- Wrapped tmux binary ---
  tmux-wrapped = pkgs.symlinkJoin {
    name = "tmux-wrapped";
    paths = [pkgs.tmux];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/tmux \
        --add-flags "-f ${tmuxConf}" \
        --prefix PATH : ${lib.makeBinPath scripts} \
        --set-default XDG_CONFIG_DIRS ${nerdFontConfigDir}
    '';
  };
in {
  inherit tmux-wrapped tmuxConf;
}
```

**Important notes for the implementor:**
- The `pluginRunShells` section uses `.rtp` which is the standard tmuxPlugins attribute for the run-shell path. Verify this works — if not, use the explicit `${plugin}/share/tmux-plugins/${name}/${name}.tmux` pattern.
- The `client-attached[99]` hook references `~/.config/tmux/tmux.conf` which won't exist for wrapped users. This line needs adjustment — either remove it or change to `source-file ${tmuxConf}` (but that means Nix store path in the hook, which is fine).
- `XDG_CONFIG_DIRS` is used so the nerd font plugin finds its YAML config. Test that it actually reads from `XDG_CONFIG_DIRS/tmux/` and not `XDG_CONFIG_HOME/tmux/`.

**Step 2: Verify the config generates**

```bash
cd ~/tmux-config && git add -A && nix build .
```

**Step 3: Test basic tmux launch**

```bash
./result/bin/tmux new -s test
```

Verify:
- Status bar renders (catppuccin theme, icons)
- `Prefix+s` opens session picker
- `Prefix+w` opens window picker
- Window names show nerd font icons

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: tmux config generator with wrapped binary"
```

---

### Task 5: Test and fix plugin loading order

**Goal:** Verify all plugins load correctly and fix any ordering issues.

**Step 1: Launch tmux and check for errors**

```bash
cd ~/tmux-config && nix build . && ./result/bin/tmux new -s test
```

Inside tmux:
```
Prefix + : show-messages
```

Look for errors about missing plugins, failed run-shell commands, or unresolved format strings.

**Step 2: Verify .rtp attribute exists**

If `.rtp` doesn't work for any plugin, check available attributes:

```bash
nix eval --raw 'nixpkgs#tmuxPlugins.sensible.rtp' 2>/dev/null || echo "no .rtp"
```

If `.rtp` is not available, replace with explicit path pattern:
```
${plugin}/share/tmux-plugins/${pluginName}/${pluginName}.tmux
```

**Step 3: Fix the client-attached hook**

The `client-attached[99]` hook sources `~/.config/tmux/tmux.conf` which doesn't exist. Change it to source the generated config or remove it. In `config/tmux.conf.nix`, replace:

```
set-hook -g client-attached[99] 'source-file ~/.config/tmux/tmux.conf'
```

with:

```
set-hook -g client-attached[99] 'run-shell "tmux source-file ${tmuxConf} 2>/dev/null || true"'
```

But since `tmuxConf` is a Nix interpolation, this needs to be in the Nix string, not in the tmux.conf literal. The Nix `writeText` call will interpolate it correctly.

**Step 4: Test nerd font YAML config loading**

Verify icons appear on windows. If not, check if the plugin reads `XDG_CONFIG_DIRS` or `XDG_CONFIG_HOME`:

```bash
# Inside tmux, open a new window running fish
Prefix + c
# Check if the window icon changes to 🐟
```

If not working, may need to use `--set XDG_CONFIG_HOME` instead of `--set-default XDG_CONFIG_DIRS`, or symlink the YAML file differently.

**Step 5: Commit fixes**

```bash
git add -A && git commit -m "fix: plugin loading and config paths"
```

---

### Task 6: Write README with CC hooks documentation

**Files:**
- Create: `~/tmux-config/README.md`

**Step 1: Write README**

Include:
- Quick start (`nix run github:noamsto/tmux-config`)
- Installation (`nix profile install`)
- Features list
- Claude Code hooks setup (full JSON to paste into `~/.claude/settings.json`)
- wt tool description and install
- Requirements (Nerd Font terminal, tmux 3.4+)

The CC hooks JSON should look like (using bare command names since they're in PATH):

```json
{
  "hooks": {
    "Startup": [{ "hooks": [{ "type": "command", "command": "claude-status-update cleanup" }, { "type": "command", "command": "claude-status-update idle" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "claude-status-update processing" }] }],
    "Stop": [{ "hooks": [{ "type": "command", "command": "claude-status-update done" }] }],
    "PreToolUse": [{ "hooks": [{ "type": "command", "command": "claude-status-update processing" }] }],
    "PostToolUse": [{ "hooks": [{ "type": "command", "command": "claude-status-update processing" }] }],
    "Notification": [
      { "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "claude-status-update waiting" }] },
      { "matcher": "idle_prompt", "hooks": [{ "type": "command", "command": "claude-status-update idle" }] }
    ],
    "PreCompact": [{ "hooks": [{ "type": "command", "command": "claude-status-update compacting" }] }],
    "SessionEnd": [{ "hooks": [{ "type": "command", "command": "claude-status-update clear" }] }]
  }
}
```

**Note:** Verify this JSON against the actual hooks in `~/nix-config/home/ai/claude-code/default.nix` — the Nix config uses matchers like `"startup"`, `"resume"`, `"clear"` which may map to different hook types. Extract the exact structure.

**Step 2: Commit**

```bash
git add README.md && git commit -m "docs: add README with usage and CC hooks setup"
```

---

### Task 7: Create GitHub repo and push

**Step 1: Create the repo on GitHub**

```bash
cd ~/tmux-config
gh repo create noamsto/tmux-config --public --description "Opinionated tmux configuration with Claude Code integration" --source .
```

**Step 2: Push**

```bash
git push -u origin main
```

**Step 3: Test from GitHub**

```bash
nix run github:noamsto/tmux-config -- new -s test-remote
```

**Step 4: Verify wt works too**

```bash
nix run github:noamsto/tmux-config#wt -- --help
```

---

### Task 8: Update nix-config to use the new flake (optional)

This is a future task — once the standalone flake is stable, nix-config could import from it instead of maintaining its own copy. Skip this for now.

---

## Known Risks and Gotchas

1. **`.rtp` attribute on tmux plugins**: Not all plugins may expose `.rtp`. Fallback to explicit store paths.

2. **XDG_CONFIG_DIRS vs XDG_CONFIG_HOME**: The nerd font plugin might only check `XDG_CONFIG_HOME`. Test carefully.

3. **Plugin load order**: catppuccin must load before the status-format references `@thm_*` variables. The `pluginRunShells` ordering handles this but test it.

4. **Fingers reload workaround**: The `client-attached[99]` hook sources the config to fix fingers colors. In the wrapper, the config path is a Nix store path — make sure this works.

5. **tmux server persistence**: If users have an existing tmux server running with a different config, `nix run` may connect to it instead of starting fresh. Document: `tmux kill-server` first.

6. **Missing runtime deps**: Scripts call `git`, `tmux`, `gum`, `date`, `grep` etc. by name from PATH. The wrapper only adds our scripts to PATH, not all tools. `git` and `gum` must be in the user's system PATH. Document this requirement or add them to the wrapper.

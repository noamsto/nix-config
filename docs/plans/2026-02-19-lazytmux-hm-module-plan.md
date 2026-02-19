# lazytmux HM Module + nix-config Integration Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Home Manager module to lazytmux, update status bar and session picker, then integrate into nix-config replacing the old tmux module.

**Architecture:** lazytmux exposes `homeManagerModules.default` from its flake. nix-config imports it like other HM modules (vicinae, hyprdynamicmonitors pattern). The module provides `programs.lazytmux` options for the wrapped binary, wt tool, and optional startup service.

**Tech Stack:** Nix (flake-parts, Home Manager module system), bash (tmux scripts)

**Repos:**
- lazytmux: `/home/noams/Data/git/lazytmux`
- nix-config: `/home/noams/nix-config`

---

### Task 1: Create HM module in lazytmux

**Files:**
- Create: `/home/noams/Data/git/lazytmux/modules/home-manager.nix`

**Step 1: Create the module file**

```nix
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.lazytmux;
  tmuxConfig = import ../config/tmux.conf.nix {inherit pkgs lib;};
  wtPkg = import ../wt {inherit pkgs;};
in {
  options.programs.lazytmux = {
    enable = lib.mkEnableOption "lazytmux - opinionated tmux configuration";

    wt = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to install the wt (git worktree manager) tool";
      };
    };

    startupSession = {
      enable = lib.mkEnableOption "systemd service to start a tmux session on login";

      name = lib.mkOption {
        type = lib.types.str;
        default = "main";
        description = "Name of the tmux session to create on login";
      };

      directory = lib.mkOption {
        type = lib.types.str;
        default = "~";
        description = "Starting directory for the session";
      };

      terminal = {
        term = lib.mkOption {
          type = lib.types.str;
          default = "xterm-256color";
          description = "TERM value for the tmux session";
        };

        colorterm = lib.mkOption {
          type = lib.types.str;
          default = "truecolor";
          description = "COLORTERM value";
        };

        termProgram = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "TERM_PROGRAM value (e.g. 'kitty')";
        };

        terminfoPath = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Path to terminfo directory (e.g. pkgs.kitty + '/share/terminfo')";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages =
      [tmuxConfig.tmux-wrapped]
      ++ lib.optionals cfg.wt.enable [wtPkg];

    systemd.user.services.tmux-startup = lib.mkIf cfg.startupSession.enable {
      Unit = {
        Description = "Start tmux server on login";
        After = ["graphical-session.target"];
        Wants = ["graphical-session.target"];
      };

      Service = let
        tmux-bin = "${lib.getExe tmuxConfig.tmux-wrapped}";
      in {
        Type = "forking";
        ExecStartPre = "${lib.getExe' pkgs.systemd "systemctl"} --user import-environment DISPLAY WAYLAND_DISPLAY XDG_SESSION_TYPE XDG_SESSION_DESKTOP XDG_CURRENT_DESKTOP COLORTERM TERM TERMINFO";
        ExecStart = "-${tmux-bin} new -s ${cfg.startupSession.name} -c ${cfg.startupSession.directory} -d";
        RemainAfterExit = true;
        TimeoutStopSec = "5s";
        Environment =
          [
            "COLORTERM=${cfg.startupSession.terminal.colorterm}"
            "TERM=${cfg.startupSession.terminal.term}"
            "TMUX_TMPDIR=%t"
          ]
          ++ lib.optionals (cfg.startupSession.terminal.termProgram != "") [
            "TERM_PROGRAM=${cfg.startupSession.terminal.termProgram}"
          ]
          ++ lib.optionals (cfg.startupSession.terminal.terminfoPath != null) [
            "TERMINFO=${cfg.startupSession.terminal.terminfoPath}"
          ];
      };

      Install = {
        WantedBy = ["graphical-session.target"];
      };
    };
  };
}
```

**Step 2: Verify the file parses**

Run: `cd /home/noams/Data/git/lazytmux && nix eval --expr 'builtins.typeOf (import ./modules/home-manager.nix)'`
Expected: `"lambda"`

**Step 3: Commit**

```bash
cd /home/noams/Data/git/lazytmux
git add modules/home-manager.nix
git commit -m "feat: add Home Manager module with programs.lazytmux options"
```

---

### Task 2: Expose HM module in lazytmux flake.nix

**Files:**
- Modify: `/home/noams/Data/git/lazytmux/flake.nix`

**Step 1: Update flake.nix to expose homeManagerModules**

The flake currently only has `perSystem` outputs. Add a `flake` section for the HM module:

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

      flake = {
        homeManagerModules.default = import ./modules/home-manager.nix;
      };
    };
}
```

**Step 2: Verify the flake checks pass**

Run: `cd /home/noams/Data/git/lazytmux && nix flake check`
Expected: Passes (HM modules don't get evaluated during check, but flake structure is valid)

**Step 3: Commit**

```bash
cd /home/noams/Data/git/lazytmux
git add flake.nix
git commit -m "feat: expose homeManagerModules.default in flake outputs"
```

---

### Task 3: Update status bar - move claude status left, add app info right

**Files:**
- Modify: `/home/noams/Data/git/lazytmux/config/tmux.conf.nix:242-243`

**Step 1: Update status-format[0]**

In `config/tmux.conf.nix`, replace the line 243 `status-format[0]` with:

Old (line 243):
```
set -g status-format[0] "#(${tmuxPlugins.continuum}/.../continuum_save.sh)#[align=left,bg=#{@thm_bg}]#{?client_prefix,#[fg=#{@thm_red}#,bold],#[fg=#{@thm_mauve}]} #{@icon_session} #S  #[fg=#{@thm_blue},bold]#{@icon_branch} #(tmux-branch-display '#{@branch}' '#{pane_current_path}')  #[fg=#{@thm_subtext_0},nobold]#{@icon_dir} #(tmux-dir-display '#{@branch}' '#{pane_current_path}') #[align=right,fg=#{@thm_overlay_1}]#(claude-status --session '#{session_name}' --format icon-color) "
```

New:
```
set -g status-format[0] "#(${tmuxPlugins.continuum}/.../continuum_save.sh)#[align=left,bg=#{@thm_bg}]#{?client_prefix,#[fg=#{@thm_red}#,bold],#[fg=#{@thm_mauve}]} #{@icon_session} #S  #[fg=#{@thm_blue},bold]#{@icon_branch} #(tmux-branch-display '#{@branch}' '#{pane_current_path}')  #[fg=#{@thm_subtext_0},nobold]#{@icon_dir} #(tmux-dir-display '#{@branch}' '#{pane_current_path}')  #[fg=#{@thm_overlay_1}]#(claude-status --session '#{session_name}' --format icon-color) #[align=right,fg=#{@thm_subtext_0}]#{window_name} #{pane_current_command} "
```

Changes:
1. Claude status moves to left side (after dir, before `#[align=right]`)
2. Right side shows `#{window_name}` (nerd font icon) + `#{pane_current_command}` (process name)

**Step 2: Build and verify**

Run: `cd /home/noams/Data/git/lazytmux && nix build`
Expected: Builds successfully

**Step 3: Commit**

```bash
cd /home/noams/Data/git/lazytmux
git add config/tmux.conf.nix
git commit -m "feat: move claude status to left, show app icon+name on right"
```

---

### Task 4: Update session picker format

**Files:**
- Modify: `/home/noams/Data/git/lazytmux/scripts/tmux-session-picker.sh`

**Step 1: Update the session picker script**

Replace the entire file:

```bash
#!/usr/bin/env bash
# Session picker wrapper that pre-computes claude status before opening choose-tree
# This avoids tmux's #() caching issue where first-time commands return empty

set -euo pipefail

# Read icon variables from tmux
icon_session=$(tmux show -gv @icon_session 2>/dev/null || echo "")
icon_dir=$(tmux show -gv @icon_dir 2>/dev/null || echo "")
icon_branch=$(tmux show -gv @icon_branch 2>/dev/null || echo "")

# Pre-compute claude status for each session into @claude_status user variable
while IFS= read -r sess; do
  [[ -n $sess ]] || continue
  status=$(claude-status --session "$sess" --format icon-color 2>/dev/null || true)
  tmux set -t "$sess" @claude_status "$status"
done < <(tmux list-sessions -F '#{session_name}')

# Store icons as tmux vars so they're available in format strings
tmux set -g @picker_icon_session "$icon_session"
tmux set -g @picker_icon_dir "$icon_dir"
tmux set -g @picker_icon_branch "$icon_branch"

# Open choose-tree using #{?window_format,...,session_format} to distinguish rows
# Session rows: [session icon] name  [dir icon] path  [claude status]
# Window rows:  index: [app icon] name  [branch icon] branch (when @branch is set)
tmux choose-tree -Zs -O name \
  -F '#{?window_format,#{window_index}: #{window_name}#{?#{@branch}, #{@picker_icon_branch} #{=20:@branch},},#{@picker_icon_session} #{session_name}  #{@picker_icon_dir} #{=30:session_path}  #{@claude_status}}' \
  'switch-client -t "%1"'
```

**Step 2: Verify script syntax**

Run: `shellcheck /home/noams/Data/git/lazytmux/scripts/tmux-session-picker.sh`
Expected: No errors

**Step 3: Commit**

```bash
cd /home/noams/Data/git/lazytmux
git add scripts/tmux-session-picker.sh
git commit -m "feat: session picker shows icons, dir path, and claude status"
```

---

### Task 5: Update window picker format

**Files:**
- Modify: `/home/noams/Data/git/lazytmux/scripts/tmux-window-picker.sh`

**Step 1: Update the window picker script**

Replace the entire file:

```bash
#!/usr/bin/env bash
# Window picker wrapper that pre-computes claude status before opening choose-tree
# This avoids tmux's #() caching issue where first-time commands return empty

set -euo pipefail

# Read icon variables from tmux
icon_branch=$(tmux show -gv @icon_branch 2>/dev/null || echo "")
icon_dir=$(tmux show -gv @icon_dir 2>/dev/null || echo "")
icon_session=$(tmux show -gv @icon_session 2>/dev/null || echo "")

# Pre-compute claude status for each window into @claude_win_status user variable
while IFS=$'\t' read -r sess_name win_idx; do
  [[ -n $win_idx ]] || continue
  target="${sess_name}:${win_idx}"
  status=$(claude-status --window "$target" 2>/dev/null || true)
  tmux set -w -t "$target" @claude_win_status "$status"
done < <(tmux list-windows -a -F '#{session_name}	#{window_index}')

# Store icons as tmux vars for format strings
tmux set -g @picker_icon_branch "$icon_branch"
tmux set -g @picker_icon_dir "$icon_dir"
tmux set -g @picker_icon_session "$icon_session"

# Open choose-tree with windows expanded
# Session rows: [session icon] name  [dir icon] path
# Window rows:  index: [app icon] name [zoomed] [branch icon] branch [claude status]
tmux choose-tree -Zw -O name \
  -F '#{?window_format,#{window_index}: #{window_name}#{?window_zoomed_flag, 󰁌,}#{?#{@branch}, #{@picker_icon_branch} #{=30:@branch},} #{@claude_win_status},#{@picker_icon_session} #{session_name}  #{@picker_icon_dir} #{=30:session_path}}' \
  'switch-client -t "%1"'
```

**Step 2: Verify script syntax**

Run: `shellcheck /home/noams/Data/git/lazytmux/scripts/tmux-window-picker.sh`
Expected: No errors

**Step 3: Commit**

```bash
cd /home/noams/Data/git/lazytmux
git add scripts/tmux-window-picker.sh
git commit -m "feat: window picker shows icons, branch, and claude status per window"
```

---

### Task 6: Push lazytmux changes

**Step 1: Push all commits**

Run: `cd /home/noams/Data/git/lazytmux && git push`

---

### Task 7: Add lazytmux flake input to nix-config

**Files:**
- Modify: `/home/noams/nix-config/flake.nix:191` (after `wrappers` input)

**Step 1: Add the input**

Add after the `wrappers.url` line (line 190):

```nix
    lazytmux = {
      url = "github:noamsto/lazytmux";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

**Step 2: Update flake.lock**

Run: `cd /home/noams/nix-config && nix flake update lazytmux`
Expected: `flake.lock` updated with lazytmux input

**Step 3: Commit**

```bash
cd /home/noams/nix-config
git add flake.nix flake.lock
git commit -m "feat: add lazytmux flake input"
```

---

### Task 8: Configure lazytmux HM module in nix-config

**Files:**
- Modify: `/home/noams/nix-config/home/terminal/default.nix:13-18`

**Step 1: Replace tmux/wt imports with lazytmux config**

In `home/terminal/default.nix`, change the imports list to remove `./tmux` and `./wt`, and add the lazytmux HM module import + configuration:

Old lines 13-19:
```nix
  imports = [
    ./foot
    ./kitty
    ./fish
    ./tmux
    ./wt
    ./process_compose
```

New:
```nix
  imports = [
    inputs.lazytmux.homeManagerModules.default
    ./foot
    ./kitty
    ./fish
    ./process_compose
```

The file takes `inputs` from `...` args — verify it's available. Check the module argument list at the top of the file: `{ lib, osConfig, pkgs, ... }`. The `inputs` comes through `extraSpecialArgs` in `flake-modules/home-manager.nix:18`. Add `inputs` to the arg list:

Old line 1-6:
```nix
{
  lib,
  osConfig,
  pkgs,
  ...
}: let
```

New:
```nix
{
  inputs,
  lib,
  osConfig,
  pkgs,
  ...
}: let
```

**Step 2: Add lazytmux program configuration**

After the `imports` block and before `programs = {`, add:

```nix
  programs.lazytmux = {
    enable = true;
    wt.enable = true;
    startupSession = {
      enable = true;
      name = "nix-config";
      directory = "%h/nix-config";
      terminal = {
        term = "xterm-kitty";
        colorterm = "truecolor";
        termProgram = "kitty";
        terminfoPath = "${pkgs.kitty}/share/terminfo";
      };
    };
  };
```

**Step 3: Commit**

```bash
cd /home/noams/nix-config
git add home/terminal/default.nix
git commit -m "feat: configure lazytmux HM module replacing inline tmux config"
```

---

### Task 9: Delete old tmux and wt modules from nix-config

**Files:**
- Delete: `/home/noams/nix-config/home/terminal/tmux/` (entire directory)
- Delete: `/home/noams/nix-config/home/terminal/wt/` (entire directory)

**Step 1: Remove old directories**

Run:
```bash
cd /home/noams/nix-config
gtrash put home/terminal/tmux home/terminal/wt
```

**Step 2: Verify the build works**

Run: `cd /home/noams/nix-config && git add -A && nix flake check`
Expected: Passes

**Step 3: Test HM build**

Run: `cd /home/noams/nix-config && nh home build .`
Expected: Builds successfully

**Step 4: Commit**

```bash
cd /home/noams/nix-config
git add -A
git commit -m "refactor: remove old tmux and wt modules (replaced by lazytmux)"
```

---

### Task 10: Apply and verify

**Step 1: Switch Home Manager**

Run: `cd /home/noams/nix-config && nh home switch .`
Expected: Switches successfully

**Step 2: Verify tmux works**

Run: `tmux -V` — should show tmux version
Run: `which wt` — should point to nix store path
Run: `tmux new -s test -d && tmux kill-session -t test` — basic session test

**Step 3: Verify startup service**

Run: `systemctl --user status tmux-startup`
Expected: Active or shows loaded configuration

**Step 4: Test session picker**

Open tmux, press `prefix+s` — should show new format with icons, dir path, claude status

**Step 5: Test status bar**

Verify line 0 shows claude status on left and app icon+name on right

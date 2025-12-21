{pkgs}: {
  sesh-new = pkgs.writeShellScriptBin "sesh-new" (builtins.readFile ./scripts/sesh-new.sh);
  sesh-kill = pkgs.writeShellScriptBin "sesh-kill" (builtins.readFile ./scripts/sesh-kill.sh);
  sesh-list-grouped = pkgs.writeShellScriptBin "sesh-list-grouped" (builtins.readFile ./scripts/sesh-list-grouped.sh);
  sesh-icon = pkgs.writeShellScriptBin "sesh-icon" (builtins.readFile ./scripts/sesh-icon.sh);
  sesh-preview = pkgs.writeShellScriptBin "sesh-preview" (builtins.readFile ./scripts/sesh-preview.sh);
  sesh-extract-name = pkgs.writeShellScriptBin "sesh-extract-name" (builtins.readFile ./scripts/sesh-extract-name.sh);
  worktree-session-hook = pkgs.writeShellScriptBin "worktree-session-hook" (builtins.readFile ./scripts/worktree-session-hook.sh);

  # Claude status integration for tmux
  claude-status-update = pkgs.writeShellScriptBin "claude-status-update" (builtins.readFile ./scripts/claude-status-update.sh);
  claude-tmux-indicator = pkgs.writeShellScriptBin "claude-tmux-indicator" (builtins.readFile ./scripts/claude-tmux-indicator.sh);
  claude-session-status = pkgs.writeShellScriptBin "claude-session-status" (builtins.readFile ./scripts/claude-session-status.sh);
  claude-priority-window = pkgs.writeShellScriptBin "claude-priority-window" (builtins.readFile ./scripts/claude-priority-window.sh);

  # Session sidebar
  tmux-sidebar = pkgs.writeShellScriptBin "tmux-sidebar" (builtins.readFile ./scripts/tmux-sidebar.sh);
  tmux-sidebar-tui = pkgs.writeShellScriptBin "tmux-sidebar-tui" (builtins.readFile ./scripts/tmux-sidebar-tui.sh);

  # Pane border styling
  tmux-set-pane-border = pkgs.writeShellScriptBin "tmux-set-pane-border" (builtins.readFile ./scripts/tmux-set-pane-border.sh);
}

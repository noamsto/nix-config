{pkgs}: {
  sesh-new = pkgs.writeShellScriptBin "sesh-new" (builtins.readFile ./scripts/sesh-new.sh);
  sesh-kill = pkgs.writeShellScriptBin "sesh-kill" (builtins.readFile ./scripts/sesh-kill.sh);
  sesh-list-grouped = pkgs.writeShellScriptBin "sesh-list-grouped" (builtins.readFile ./scripts/sesh-list-grouped.sh);
  sesh-icon = pkgs.writeShellScriptBin "sesh-icon" (builtins.readFile ./scripts/sesh-icon.sh);
  sesh-preview = pkgs.writeShellScriptBin "sesh-preview" (builtins.readFile ./scripts/sesh-preview.sh);
  sesh-extract-name = pkgs.writeShellScriptBin "sesh-extract-name" (builtins.readFile ./scripts/sesh-extract-name.sh);

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

  # Status bar helpers
  tmux-branch-display = pkgs.writeShellScriptBin "tmux-branch-display" (builtins.readFile ./scripts/tmux-branch-display.sh);
  tmux-dir-display = pkgs.writeShellScriptBin "tmux-dir-display" (builtins.readFile ./scripts/tmux-dir-display.sh);
  tmux-branch-dir-display = pkgs.writeShellScriptBin "tmux-branch-dir-display" (builtins.readFile ./scripts/tmux-branch-dir-display.sh);
  tmux-window-branch-display = pkgs.writeShellScriptBin "tmux-window-branch-display" (builtins.readFile ./scripts/tmux-window-branch-display.sh);
  tmux-update-window-name = pkgs.writeShellScriptBin "tmux-update-window-name" (builtins.readFile ./scripts/tmux-update-window-name.sh);
}

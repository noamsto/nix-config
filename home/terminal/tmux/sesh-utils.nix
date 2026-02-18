{pkgs}: {
  sesh-new = pkgs.writeShellScriptBin "sesh-new" (builtins.readFile ./scripts/sesh-new.sh);
  sesh-kill = pkgs.writeShellScriptBin "sesh-kill" (builtins.readFile ./scripts/sesh-kill.sh);
  sesh-list-grouped = pkgs.writeShellScriptBin "sesh-list-grouped" (builtins.readFile ./scripts/sesh-list-grouped.sh);
  sesh-icon = pkgs.writeShellScriptBin "sesh-icon" (builtins.readFile ./scripts/sesh-icon.sh);
  sesh-preview = pkgs.writeShellScriptBin "sesh-preview" (builtins.readFile ./scripts/sesh-preview.sh);
  sesh-extract-name = pkgs.writeShellScriptBin "sesh-extract-name" (builtins.readFile ./scripts/sesh-extract-name.sh);

  # Claude status integration for tmux
  claude-status-update = pkgs.writeShellScriptBin "claude-status-update" (builtins.readFile ./scripts/claude-status-update.sh);
  claude-status = pkgs.writeShellScriptBin "claude-status" (builtins.readFile ./scripts/claude-status.sh);

  # Session sidebar
  tmux-sidebar = pkgs.writeShellScriptBin "tmux-sidebar" (builtins.readFile ./scripts/tmux-sidebar.sh);
  tmux-sidebar-tui = pkgs.writeShellScriptBin "tmux-sidebar-tui" (builtins.readFile ./scripts/tmux-sidebar-tui.sh);

  # Pane border styling
  tmux-set-pane-border = pkgs.writeShellScriptBin "tmux-set-pane-border" (builtins.readFile ./scripts/tmux-set-pane-border.sh);

  # Pickers
  tmux-session-picker = pkgs.writeShellScriptBin "tmux-session-picker" (builtins.readFile ./scripts/tmux-session-picker.sh);
  tmux-window-picker = pkgs.writeShellScriptBin "tmux-window-picker" (builtins.readFile ./scripts/tmux-window-picker.sh);

  # Status bar helpers
  tmux-branch-display = pkgs.writeShellScriptBin "tmux-branch-display" (builtins.readFile ./scripts/tmux-branch-display.sh);
  tmux-dir-display = pkgs.writeShellScriptBin "tmux-dir-display" (builtins.readFile ./scripts/tmux-dir-display.sh);

  # Window list overflow
  tmux-reflow-windows = pkgs.writeShellScriptBin "tmux-reflow-windows" (builtins.readFile ./scripts/tmux-reflow-windows.sh);
}

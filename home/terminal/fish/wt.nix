{pkgs, ...}: {
  # Git worktree + tmux session manager
  xdg.configFile = {
    # Main wt function
    "fish/functions/wt.fish".source = ./functions/wt.fish;

    # Fish completions for wt command
    "fish/completions/wt.fish".text = ''
      # Completions for wt (worktree manager)

      # Flags
      complete -c wt -f -s y -l yes -d 'Skip confirmation prompts'
      complete -c wt -f -s m -l move -d 'Move current window to new session'
      complete -c wt -f -s q -l quiet -d 'Quiet mode (only output path)'

      # Subcommands
      complete -c wt -f -n '__fish_use_subcommand' -a 'list' -d 'List worktrees'
      complete -c wt -f -n '__fish_use_subcommand' -a 'ls' -d 'List worktrees (alias)'
      complete -c wt -f -n '__fish_use_subcommand' -a 'remove' -d 'Remove worktree + session'
      complete -c wt -f -n '__fish_use_subcommand' -a 'rm' -d 'Remove worktree + session (alias)'
      complete -c wt -f -n '__fish_use_subcommand' -a 'help' -d 'Show help'

      # Complete existing worktree branches
      function __wt_list_worktree_branches
          if git rev-parse --git-dir >/dev/null 2>&1
              set -l repo_root (git rev-parse --show-toplevel)
              git -C "$repo_root" worktree list 2>/dev/null | while read -l line
                  if string match -rq '\[(.+)\]$' -- $line
                      set -l branch (string match -r '\[(.+)\]$' -- $line)[2]
                      echo $branch
                  end
              end
          end
      end

      # Complete all branches (for smart mode: existing worktrees + available branches)
      function __wt_list_all_branches
          if git rev-parse --git-dir >/dev/null 2>&1
              set -l repo_root (git rev-parse --show-toplevel)

              # Existing worktrees first (likely what user wants to switch to)
              __wt_list_worktree_branches

              # Then available branches (not in worktrees)
              set -l used_branches (__wt_list_worktree_branches)

              for branch in (git -C "$repo_root" branch --format='%(refname:short)' 2>/dev/null)
                  if not contains $branch $used_branches
                      echo $branch
                  end
              end

              for branch in (git -C "$repo_root" branch -r --format='%(refname:short)' 2>/dev/null)
                  set -l short_name (string replace -r '^origin/' "" -- $branch)
                  if test "$short_name" != "HEAD"; and not contains $short_name $used_branches
                      echo $short_name
                  end
              end | sort -u
          end
      end

      # Branch completions for remove (only existing worktrees)
      complete -c wt -f -n '__fish_seen_subcommand_from remove rm' -a '(__wt_list_worktree_branches)'

      # Branch completions for smart mode (all branches, shown at top level)
      complete -c wt -f -n '__fish_use_subcommand' -a '(__wt_list_all_branches)'
    '';
  };
}

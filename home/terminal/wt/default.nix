{pkgs, ...}: let
  wt = pkgs.writeShellApplication {
    name = "wt";
    runtimeInputs = with pkgs; [git tmux gum zoxide];
    text = builtins.readFile ./wt.sh;
  };
in {
  home.packages = [wt];

  # Fish completions (keep existing functionality)
  xdg.configFile."fish/completions/wt.fish".text = ''
    # Completions for wt (worktree manager)

    # Flags
    complete -c wt -f -s y -l yes -d 'Skip confirmation prompts'
    complete -c wt -f -s q -l quiet -d 'Quiet mode (only output path)'

    # Subcommands
    complete -c wt -f -n '__fish_use_subcommand' -a 'list' -d 'List worktrees'
    complete -c wt -f -n '__fish_use_subcommand' -a 'ls' -d 'List worktrees (alias)'
    complete -c wt -f -n '__fish_use_subcommand' -a 'remove' -d 'Remove worktree + window'
    complete -c wt -f -n '__fish_use_subcommand' -a 'rm' -d 'Remove worktree + window (alias)'
    complete -c wt -f -n '__fish_use_subcommand' -a 'clean' -d 'Remove merged worktrees'
    complete -c wt -f -n '__fish_use_subcommand' -a 'prune' -d 'Remove merged worktrees (alias)'
    complete -c wt -f -n '__fish_use_subcommand' -a 'z' -d 'Fuzzy find worktree'
    complete -c wt -f -n '__fish_use_subcommand' -a 'main' -d 'Switch to main worktree'
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

    # Branch completions for remove and z (only existing worktrees)
    complete -c wt -f -n '__fish_seen_subcommand_from remove rm z' -a '(__wt_list_worktree_branches)'

    # Branch completions for smart mode (all branches, shown at top level)
    complete -c wt -f -n '__fish_use_subcommand' -a '(__wt_list_all_branches)'
  '';

  # Bash completions
  xdg.configFile."bash/completions/wt.bash".text = ''
    # Bash completions for wt (worktree manager)

    _wt_list_worktree_branches() {
        if git rev-parse --git-dir >/dev/null 2>&1; then
            local repo_root
            repo_root=$(git rev-parse --show-toplevel)
            git -C "$repo_root" worktree list 2>/dev/null | sed -n 's/.*\[\(.*\)\]$/\1/p'
        fi
    }

    _wt_list_all_branches() {
        if git rev-parse --git-dir >/dev/null 2>&1; then
            local repo_root
            repo_root=$(git rev-parse --show-toplevel)

            # Existing worktrees first
            _wt_list_worktree_branches

            # Local branches not in worktrees
            local used_branches
            used_branches=$(_wt_list_worktree_branches | tr '\n' '|')
            git -C "$repo_root" branch --format='%(refname:short)' 2>/dev/null | grep -vE "^($used_branches)$" 2>/dev/null || true

            # Remote branches (without origin/ prefix)
            git -C "$repo_root" branch -r --format='%(refname:short)' 2>/dev/null | \
                sed 's|^origin/||' | \
                grep -v '^HEAD$' | \
                grep -vE "^($used_branches)$" 2>/dev/null | \
                sort -u || true
        fi
    }

    _wt() {
        local cur prev words cword
        _init_completion || return

        local subcommands="list ls remove rm clean prune z main help"
        local flags="-y --yes -q --quiet"

        case "$prev" in
            remove|rm|z)
                COMPREPLY=($(compgen -W "$(_wt_list_worktree_branches)" -- "$cur"))
                return
                ;;
        esac

        if [[ $cword -eq 1 ]]; then
            # First argument: subcommands, flags, or branches
            COMPREPLY=($(compgen -W "$subcommands $flags $(_wt_list_all_branches)" -- "$cur"))
        elif [[ "$cur" == -* ]]; then
            # Flag completion
            COMPREPLY=($(compgen -W "$flags" -- "$cur"))
        else
            # Branch completion for smart mode
            COMPREPLY=($(compgen -W "$(_wt_list_all_branches)" -- "$cur"))
        fi
    }

    complete -F _wt wt
  '';

  # Source bash completions in bashrc
  programs.bash.initExtra = ''
    # Load wt completions
    if [[ -f "$HOME/.config/bash/completions/wt.bash" ]]; then
        source "$HOME/.config/bash/completions/wt.bash"
    fi
  '';
}

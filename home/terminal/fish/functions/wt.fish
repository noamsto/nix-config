function wt --description 'Git worktree + tmux session manager'
    # Parse flags
    set -l skip_prompt false
    set -l move_window false
    set -l quiet false
    set -l args

    for arg in $argv
        # Handle combined short flags like -ymq
        if string match -rq '^-[ymq]+$' -- $arg
            if string match -q '*y*' -- $arg
                set skip_prompt true
            end
            if string match -q '*m*' -- $arg
                set move_window true
            end
            if string match -q '*q*' -- $arg
                set quiet true
            end
        else
            switch $arg
                case -y --yes
                    set skip_prompt true
                case -m --move
                    set move_window true
                case -q --quiet
                    set quiet true
                case '*'
                    set -a args $arg
            end
        end
    end

    set -l subcommand $args[1]

    switch "$subcommand"
        case list ls
            __wt_list
        case remove rm
            __wt_remove $args[2..-1]
        case main
            __wt_main $skip_prompt $move_window $quiet
        case help -h --help ""
            __wt_help
        case "*"
            # Smart mode: branch name given directly
            if test -n "$subcommand"
                __wt_smart $skip_prompt $move_window $quiet $subcommand
            else
                __wt_help
            end
    end
end

function __wt_help
    echo "Git Worktree + Tmux Session Manager"
    echo ""
    echo "Usage:"
    echo "  wt <branch>           Smart switch/create (prompts before creating)"
    echo "  wt -y <branch>        Skip prompts"
    echo "  wt -m <branch>        Move current window to new session"
    echo "  wt -q <branch>        Quiet mode (only output path)"
    echo "  wt -ymq <branch>      Combine flags (for Claude/scripts)"
    echo "  wt main               Switch to root repository session"
    echo "  wt list               List all worktrees"
    echo "  wt remove <branch>    Remove worktree + kill session"
    echo "  wt help               Show this help"
    echo ""
    echo "Smart mode:"
    echo "  • Worktree exists     → switch to session"
    echo "  • Branch exists       → prompt to create worktree"
    echo "  • Branch not found    → prompt to create new branch"
    echo ""
    echo "Claude usage:  cd \"\$(wt -ymq feature-x)\""
    echo ""
    echo "Session names: repo-name/branch-name"
    echo "Worktree location: .worktrees/<branch-name>"
end

# Smart worktree handler with prompts
function __wt_smart
    set -l skip_prompt $argv[1]
    set -l move_window $argv[2]
    set -l quiet $argv[3]
    set -l branch $argv[4]

    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "Error: Not in a git repository" >&2
        return 1
    end

    set -l repo_root (git rev-parse --show-toplevel)
    set -l repo_name (basename $repo_root)
    set -l worktree_path "$repo_root/.worktrees/$branch"
    set -l session_name "$repo_name/$branch"

    # Case 1: Worktree already exists → switch to it
    set -l existing_worktree ""
    for line in (git worktree list 2>/dev/null)
        if string match -rq "\[$branch\]\$" -- $line
            set existing_worktree (string split -f1 " " -- $line)
            break
        end
    end

    if test -n "$existing_worktree"
        __wt_switch_to_session $session_name $existing_worktree $move_window $quiet
        return $status
    end

    # Case 2: Check if branch exists (local or remote)
    set -l branch_exists false
    set -l is_remote false

    if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null
        set branch_exists true
    else if git show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null
        set branch_exists true
        set is_remote true
    end

    if test "$branch_exists" = true
        # Branch exists but no worktree
        if test "$skip_prompt" = false
            set -l source_desc "local branch"
            if test "$is_remote" = true
                set source_desc "remote branch origin/$branch"
            end
            echo "Branch '$branch' exists ($source_desc) but has no worktree."
            read -P "Create worktree at .worktrees/$branch? [y/N] " confirm
            if not string match -riq '^y' -- $confirm
                echo "Cancelled."
                return 1
            end
        end
        __wt_create_worktree $branch $worktree_path $session_name false $is_remote $move_window $quiet
    else
        # Case 3: Branch doesn't exist → create new
        if test "$skip_prompt" = false
            echo "Branch '$branch' does not exist."
            read -P "Create new branch + worktree? [y/N] " confirm
            if not string match -riq '^y' -- $confirm
                echo "Cancelled."
                return 1
            end
        end
        __wt_create_worktree $branch $worktree_path $session_name true false $move_window $quiet
    end
end

# Create worktree and switch to session
function __wt_create_worktree
    set -l branch $argv[1]
    set -l worktree_path $argv[2]
    set -l session_name $argv[3]
    set -l create_branch $argv[4]
    set -l is_remote $argv[5]
    set -l move_window $argv[6]
    set -l quiet $argv[7]

    if test "$quiet" = false
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🌿 Creating git worktree + tmux session"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "Creating worktree..."
    end

    # Create worktree (suppress output in quiet mode)
    set -l git_output
    if test "$create_branch" = true
        # New branch
        set git_output (git worktree add -b "$branch" "$worktree_path" 2>&1)
    else if test "$is_remote" = true
        # Track remote branch
        set git_output (git worktree add --track -b "$branch" "$worktree_path" "origin/$branch" 2>&1)
    else
        # Existing local branch
        set git_output (git worktree add "$worktree_path" "$branch" 2>&1)
    end

    if test $status -ne 0
        echo "❌ Failed to create worktree" >&2
        if test "$quiet" = false
            echo "$git_output" >&2
        end
        return 1
    end

    if test "$quiet" = false
        echo "✓ Worktree created: $worktree_path"
        echo ""
    end

    __wt_switch_to_session $session_name $worktree_path $move_window $quiet
end

# Switch to or create tmux session
function __wt_switch_to_session
    set -l session_name $argv[1]
    set -l worktree_path $argv[2]
    set -l move_window $argv[3]
    set -l quiet $argv[4]

    if test -n "$TMUX"
        # Inside tmux
        if not tmux has-session -t "$session_name" 2>/dev/null
            tmux new-session -d -s "$session_name" -c "$worktree_path"
            if test "$quiet" = false
                echo "✓ Session created: $session_name"
            end
        end

        if test "$move_window" = true
            # Move current window to the new session
            tmux move-window -t "$session_name"
            if test "$quiet" = false
                echo "✓ Window moved to: $session_name"
            end
        else
            tmux switch-client -t "$session_name"
        end
    else
        # Outside tmux
        if tmux has-session -t "$session_name" 2>/dev/null
            sesh connect "$session_name"
        else
            sesh connect "$session_name" --root "$worktree_path"
        end
    end

    # Output path (always for quiet mode, as final line for normal mode)
    if test "$quiet" = true
        echo "$worktree_path"
    else
        echo ""
        echo "Worktree: $worktree_path"
    end
end

function __wt_main
    set -l skip_prompt $argv[1]
    set -l move_window $argv[2]
    set -l quiet $argv[3]

    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "Error: Not in a git repository" >&2
        return 1
    end

    set -l repo_root (git rev-parse --show-toplevel)
    set -l repo_name (basename $repo_root)
    set -l session_name "$repo_name/main"

    __wt_switch_to_session $session_name $repo_root $move_window $quiet
end

function __wt_list
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "Error: Not in a git repository"
        return 1
    end

    git worktree list
end

function __wt_remove
    set -l branch $argv[1]

    if test -z "$branch"
        echo "Error: Branch name required"
        echo "Usage: wt remove <branch-name>"
        return 1
    end

    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "Error: Not in a git repository"
        return 1
    end

    set -l repo_name (basename (git rev-parse --show-toplevel))
    set -l session_name "$repo_name/$branch"

    # Find worktree path from git worktree list
    set -l worktree_path ""
    for line in (git worktree list 2>/dev/null)
        if string match -rq "\[$branch\]\$" -- $line
            set worktree_path (string split -f1 " " -- $line)
            break
        end
    end

    if test -z "$worktree_path"
        echo "Error: No worktree found for branch '$branch'"
        echo ""
        echo "Available worktrees:"
        __wt_list
        return 1
    end

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🗑️  Removing worktree + tmux session"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Kill tmux session if it exists
    if tmux has-session -t "$session_name" 2>/dev/null
        echo "Killing tmux session: $session_name"
        tmux kill-session -t "$session_name"
        echo "✓ Session killed"
    else
        echo "No tmux session found: $session_name"
    end

    echo ""
    echo "Removing worktree: $worktree_path"
    if git worktree remove "$worktree_path"
        echo "✓ Worktree removed"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "✓ Complete"
    else
        echo "❌ Failed to remove worktree"
        return 1
    end
end

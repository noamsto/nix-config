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
    echo "Git Worktree + Tmux Window Manager"
    echo ""
    echo "Usage:"
    echo "  wt <branch>           Smart switch/create (prompts before creating)"
    echo "  wt -y <branch>        Skip prompts"
    echo "  wt -m <branch>        Move current window to repo session"
    echo "  wt -q <branch>        Quiet mode (only output path)"
    echo "  wt -ymq <branch>      Combine flags (for Claude/scripts)"
    echo "  wt main               Switch to root repository window"
    echo "  wt list               List all worktrees"
    echo "  wt remove <branch>    Remove worktree + kill window"
    echo "  wt help               Show this help"
    echo ""
    echo "Model: Session = Project, Window = Worktree"
    echo "  • One tmux session per repository (e.g., 'nix-config')"
    echo "  • One window per worktree/branch (e.g., 'feat-x', 'fix-y')"
    echo "  • Fast switching between branches: \`n / \`p"
    echo ""
    echo "Smart mode:"
    echo "  • Worktree exists     → switch to window"
    echo "  • Branch exists       → prompt to create worktree"
    echo "  • Branch not found    → prompt to create new branch"
    echo ""
    echo "Claude usage:  cd \"\$(wt -ymq feature-x)\""
    echo ""
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
    for line in (git -C "$repo_root" worktree list 2>/dev/null)
        # Use single quotes for regex anchors, double quotes for variable
        if string match -rq '\['"$branch"'\]$' -- $line
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

    if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null
        set branch_exists true
    else if git -C "$repo_root" show-ref --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null
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
        __wt_create_worktree $repo_root $branch $worktree_path $session_name false $is_remote $move_window $quiet
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
        __wt_create_worktree $repo_root $branch $worktree_path $session_name true false $move_window $quiet
    end
end

# Create worktree and switch to session
function __wt_create_worktree
    set -l repo_root $argv[1]
    set -l branch $argv[2]
    set -l worktree_path $argv[3]
    set -l session_name $argv[4]
    set -l create_branch $argv[5]
    set -l is_remote $argv[6]
    set -l move_window $argv[7]
    set -l quiet $argv[8]

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
        set git_output (git -C "$repo_root" worktree add -b "$branch" "$worktree_path" 2>&1)
    else if test "$is_remote" = true
        # Track remote branch
        set git_output (git -C "$repo_root" worktree add --track -b "$branch" "$worktree_path" "origin/$branch" 2>&1)
    else
        # Existing local branch
        set git_output (git -C "$repo_root" worktree add "$worktree_path" "$branch" 2>&1)
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

# Helper: find window index by @worktree option
function __wt_find_window_by_worktree
    set -l session $argv[1]
    set -l worktree $argv[2]
    # List windows with their @worktree option and find matching one
    for line in (tmux list-windows -t "$session" -F '#{window_index}:#{@worktree}' 2>/dev/null)
        set -l idx (string split -f1 ':' -- $line)
        set -l wt (string split -f2 ':' -- $line)
        if test "$wt" = "$worktree"
            echo $idx
            return 0
        end
    end
    return 1
end

# Switch to or create tmux session/window
# Uses window-per-worktree model: one session per repo, windows per branch
# Windows are tracked by @worktree option, not by name (lets nerd-font plugin work)
function __wt_switch_to_session
    set -l session_name $argv[1]  # Format: repo-name/branch
    set -l worktree_path $argv[2]
    set -l move_window $argv[3]
    set -l quiet $argv[4]

    # Parse repo and branch from session_name
    set -l repo_name (string split -f1 '/' -- $session_name)
    set -l branch_name (string split -f2 '/' -- $session_name)

    if test -n "$TMUX"
        # Inside tmux - use window-per-worktree model
        set -l current_session (tmux display-message -p '#{session_name}')

        # Check if we're already in a session for this repo
        set -l in_repo_session false
        if test "$current_session" = "$repo_name"; or string match -q "$repo_name/*" -- "$current_session"
            set in_repo_session true
        end

        if test "$in_repo_session" = true
            # Already in repo session - create/switch to window
            set -l target_session "$current_session"

            # Check if window already exists (by @worktree option)
            set -l window_idx (__wt_find_window_by_worktree "$target_session" "$worktree_path")

            if test -n "$window_idx"
                # Window exists - switch to it
                tmux select-window -t "$target_session:$window_idx"
                if test "$quiet" = false
                    echo "✓ Switched to window: $branch_name"
                end
            else
                # Create new window (no name - let nerd-font plugin handle it)
                tmux new-window -t "$target_session" -c "$worktree_path"
                # Store worktree path and branch for identification and display
                tmux set-option -w @worktree "$worktree_path"
                tmux set-option -w @branch "$branch_name"
                if test "$quiet" = false
                    echo "✓ Window created: $branch_name"
                end
            end
        else
            # Not in repo session - create/switch to session
            if not tmux has-session -t "$repo_name" 2>/dev/null
                # Create new session (no window name)
                tmux new-session -d -s "$repo_name" -c "$worktree_path"
                tmux set-option -t "$repo_name" -w @worktree "$worktree_path"
                tmux set-option -t "$repo_name" -w @branch "$branch_name"
                if test "$quiet" = false
                    echo "✓ Session created: $repo_name"
                end
            else
                # Session exists - add window if needed
                set -l window_idx (__wt_find_window_by_worktree "$repo_name" "$worktree_path")
                if test -z "$window_idx"
                    tmux new-window -t "$repo_name" -c "$worktree_path"
                    tmux set-option -t "$repo_name" -w @worktree "$worktree_path"
                    tmux set-option -t "$repo_name" -w @branch "$branch_name"
                end
            end

            # Find the window index for switching
            set -l target_idx (__wt_find_window_by_worktree "$repo_name" "$worktree_path")

            if test "$move_window" = true
                # Move current window to the repo session
                tmux move-window -t "$repo_name"
                if test "$quiet" = false
                    echo "✓ Window moved to: $repo_name"
                end
            else
                if test -n "$target_idx"
                    tmux switch-client -t "$repo_name:$target_idx"
                else
                    tmux switch-client -t "$repo_name"
                end
            end
        end
    else
        # Outside tmux - create session with window
        if tmux has-session -t "$repo_name" 2>/dev/null
            # Check if window exists
            set -l window_idx (__wt_find_window_by_worktree "$repo_name" "$worktree_path")
            if test -z "$window_idx"
                tmux new-window -t "$repo_name" -c "$worktree_path"
                tmux set-option -t "$repo_name" -w @worktree "$worktree_path"
                tmux set-option -t "$repo_name" -w @branch "$branch_name"
            end
            set -l target_idx (__wt_find_window_by_worktree "$repo_name" "$worktree_path")
            if test -n "$target_idx"
                sesh connect "$repo_name:$target_idx"
            else
                sesh connect "$repo_name"
            end
        else
            # Create new session
            tmux new-session -d -s "$repo_name" -c "$worktree_path"
            tmux set-option -t "$repo_name" -w @worktree "$worktree_path"
            tmux set-option -t "$repo_name" -w @branch "$branch_name"
            sesh connect "$repo_name"
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
    # Use repo/main format so __wt_switch_to_session can parse it
    set -l session_name "$repo_name/main"

    __wt_switch_to_session $session_name $repo_root $move_window $quiet
end

function __wt_list
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "Error: Not in a git repository"
        return 1
    end

    set -l repo_root (git rev-parse --show-toplevel)
    git -C "$repo_root" worktree list
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

    set -l repo_root (git rev-parse --show-toplevel)
    set -l repo_name (basename $repo_root)

    # Find worktree path from git worktree list
    set -l worktree_path ""
    for line in (git -C "$repo_root" worktree list 2>/dev/null)
        if string match -rq '\['"$branch"'\]$' -- $line
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
    echo "🗑️  Removing worktree + tmux window"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Kill tmux window if it exists (find by @worktree option)
    if tmux has-session -t "$repo_name" 2>/dev/null
        set -l window_idx (__wt_find_window_by_worktree "$repo_name" "$worktree_path")
        if test -n "$window_idx"
            echo "Killing tmux window: $repo_name:$window_idx"
            tmux kill-window -t "$repo_name:$window_idx"
            echo "✓ Window killed"
        else
            echo "No tmux window found for worktree: $worktree_path"
        end
    else
        echo "No tmux session found: $repo_name"
    end

    echo ""
    echo "Removing worktree: $worktree_path"
    if git -C "$repo_root" worktree remove "$worktree_path"
        echo "✓ Worktree removed"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "✓ Complete"
    else
        echo "❌ Failed to remove worktree"
        return 1
    end
end

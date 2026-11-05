---
name: worktrunk
description: Use when creating, switching, listing, removing or merging git worktrees with wt (worktrunk), or when unsure which wt flags or branch shortcuts exist.
---

# worktrunk (`wt`)

Flags attach to the subcommand, never to bare `wt`. These are the only forms; do not invent others and do not browse `wt --help` mid-task.

```text
wt switch -c <branch>   # new branch + worktree
wt switch <branch>      # existing branch; creates the worktree if needed
wt switch               # interactive picker
wt list                 # worktrees and status
wt remove               # remove current worktree; deletes branch if merged
wt merge                # merge current branch into target
```

- `-y`/`--yes` skips prompts, `-b`/`--base <base>` sets the base for `-c`, `-x`/`--execute <cmd>` runs a command after switching (e.g. `-x claude`).
- Branch shortcuts: `^` default branch, `-` previous, `@` current, `pr:{N}`, `mr:{N}`.
- Wrong: `wt -yqn <branch>`, `wt <branch>`, `wt -q`, `wt -n`. Right: `wt switch -c -y <branch>`.

tmux model: one session per repository, one window per worktree. A `post-switch` hook in `~/.config/worktrunk/config.toml` switches to or creates the matching window, and `[switch] cd = false` leaves the parent shell where it is. So run `wt switch <branch>` directly; never wrap it in `cd "$(...)"`.

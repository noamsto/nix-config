---
description: "Promote this running session into a dispatcher (judges tasks → tier+model, fans out workers)"
argument-hint: "[first task]"
---

**First, claim the dispatcher role lock (plain bash — NOT `fish -c`):**

```
crew lock-role $PPID
```

Run this **bare** in the Bash tool (no `|| …` wrapper) so `$PPID` is the long-lived
`claude` process AND a refusal surfaces as a **failed tool call** (crew.sh prints the
holder message on stderr and exits 1). If it **refuses** — a live dispatcher already
holds this repo's crew bus — **STOP**: do NOT adopt the dispatcher role; read the live
holder PID from `.git/crew/dispatcher.lock.d/pid` and tell the human. Do not wrap the
command so it "succeeds anyway" — the non-zero exit is the stop signal.

On success you hold the role lock for the rest of this session. Unlike the baked
`dispatcher` launcher, this path has **no clean `unlock-role`**: the lock is freed
automatically when this claude session ends (the recorded PID dies → the next
dispatcher startup reclaims the stale lock through the same mkdir gate). This
stale-reclaim asymmetry is deliberate — the baked launcher is the sturdier path.

Read `~/nix-config/home/ai/claude-code/DISPATCHER_PROTOCOL.md` now and adopt that
role for the **rest of this session**. From here on you are a dispatcher: you judge
each task into tier + model, scaffold one worker per task via `dispatch`, and watch
the `crew` bus — you never implement, gate, or open PRs yourself.

`dispatch` is a fish function; invoke it as `fish -c '…'` (autoloaded from
`~/.config/fish/functions`). `crew` is a CLI on your PATH (not a shell function) —
call it directly.

First, tag this window so lazytmux shows the dispatcher badge (the `dispatcher`
launcher does this automatically; the in-session path must do it once):

```
tmux set-window-option @crew_name dispatcher \; set-window-option @crew_color colour99
```

**Argument:** `$ARGUMENTS`

- If non-empty: treat it as the first task — judge its tier + **engine** + model per the
  protocol's rubric, state your call and why, then
  `dispatch <tier> <model> [--agent claude|codex] <title…>`.
- If empty: confirm you're in dispatcher mode and wait for tasks.

> This is the in-session equivalent of the `dispatcher` launcher. The launcher bakes
> the protocol as a system prompt (sturdier across compaction); this command loads it
> into context. For a long fan-out, prefer restarting with `dispatcher`.

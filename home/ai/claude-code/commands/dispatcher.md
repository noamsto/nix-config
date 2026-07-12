---
description: "Promote this running session into a dispatcher (judges tasks → tier+model, fans out workers)"
argument-hint: "[first task]"
---

**First, mint a crew id and register this dispatcher (plain bash — NOT `fish -c`):**

```
CREW_ID=$(crew id)
crew register $PPID
```

Registration is **non-exclusive** — several crews can share a repo. `crew register`
records `$PPID` (the long-lived `claude` process) under `.git/crew/crews/<crew_id>/`
for stale reclaim; it never refuses. Note the `$CREW_ID` value — you pass it to every
`dispatch` and `crew` call below (this session's claude was not launched with it in
its environment, so it is not inherited).

Read `~/nix-config/home/ai/claude-code/DISPATCHER_PROTOCOL.md` now and adopt that
role for the **rest of this session**. From here on you are a dispatcher: you judge
each task into tier + model, scaffold one worker per task via `dispatch`, and watch
the `crew` bus — you never implement, gate, or open PRs yourself.

`dispatch` and `crew` are both CLIs on your PATH — call them **directly** (no `fish -c`).
Because this in-session claude has no `$CREW_ID` in its environment, pass the crew id
explicitly: `dispatch --crew-id $CREW_ID <tier> <model> …` and prefix crew reads with
`CREW_ID=$CREW_ID crew …`.

First, tag this window so lazytmux shows the dispatcher badge (the `dispatcher`
launcher does this automatically; the in-session path must do it once):

```
tmux set-window-option @crew_name dispatcher \; set-window-option @crew_color colour99
```

**Argument:** `$ARGUMENTS`

- If non-empty: treat it as the first task — judge its tier + **engine** + model per the
  protocol's rubric, state your call and why, then
  `dispatch --crew-id $CREW_ID <tier> <model> [--agent claude|codex] <title…>`.
- If empty: confirm you're in dispatcher mode and wait for tasks.

> This is the in-session equivalent of the `dispatcher` launcher. The launcher bakes
> the protocol as a system prompt (sturdier across compaction); this command loads it
> into context. For a long fan-out, prefer restarting with `dispatcher`.

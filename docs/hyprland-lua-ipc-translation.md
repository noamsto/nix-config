# hyprctl IPC under the Lua config

When Hyprland runs a Lua config (`configType = "lua"`), the IPC surface changes.
This is gated purely on config type — there is no compatibility flag:

```cpp
// src/debug/HyprCtl.cpp:1162
if (Config::mgr()->type() != Config::CONFIG_LEGACY)
    return "keyword can't work with non-legacy parsers. Use eval.";
```

Every form below was verified against a live Hyprland 0.56.2 running the Lua
config. Anything not in this table should be tested before use.

## What still works unchanged

`monitors`, `clients`, `activewindow`, `devices`, `getoption`, `version`,
`reload`, `setcursor` — all queries and a few side-effecting commands are fine.

## What broke

| Command | Status |
|---|---|
| `hyprctl dispatch <bare dispatcher> [args]` | **broken** — the argument is now parsed as Lua |
| `hyprctl keyword <path> <value>` | **broken** — `keyword can't work with non-legacy parsers` |

`hyprctl dispatch foo bar` becomes `hl.dispatch(foo bar)`, which is a Lua syntax
error. The fix is to pass a real Lua expression.

## dispatch translations

Pass a Lua expression to `hyprctl dispatch`:

| hyprlang | Lua |
|---|---|
| `dispatch moveworkspacetomonitor "N MON"` | `dispatch 'hl.dsp.workspace.move({ workspace = N, monitor = "MON" })'` |
| `dispatch dpms on` \| `off` | `dispatch 'hl.dsp.dpms({ action = "on" })'` |
| `dispatch exec CMD` | `dispatch 'hl.dsp.exec_cmd("CMD")'` |
| `dispatch centerwindow` | `dispatch 'hl.dsp.window.center()'` |
| `dispatch togglefloating` | `dispatch 'hl.dsp.window.float({ action = "toggle" })'` |
| `dispatch resizeactive X Y` | `dispatch 'hl.dsp.window.resize({ x = X, y = Y, relative = true })'` |
| `dispatch movetoworkspace r+1` | `dispatch 'hl.dsp.window.move({ workspace = "r+1" })'` |

## keyword translations

Use `hyprctl eval` with a Lua expression:

| hyprlang | Lua |
|---|---|
| `keyword env K,V` | `eval 'hl.env("K", "V")'` |
| `keyword cursor:zoom_factor V` | `eval 'hl.config({ cursor = { zoom_factor = V } })'` |
| `keyword general:col.active_border "c1 c2 45deg"` | `eval 'hl.config({ general = { ["col.active_border"] = { colors = {"c1","c2"}, angle = 45 } } })'` |
| `keyword animation "leaf,0,0,default"` | `eval 'hl.animation({ leaf = "leaf", enabled = false })'` |
| `keyword animation "leaf,1,S,default"` | `eval 'hl.animation({ leaf = "leaf", enabled = true, speed = S, bezier = "default" })'` |
| `keyword monitor "NAME,disable"` | `eval 'hl.monitor({ output = "NAME", disabled = true })'` |
| `keyword monitor "NAME,preferred,auto,S"` | `eval 'hl.monitor({ output = "NAME", mode = "preferred", position = "auto", scale = S })'` |

## Gotchas

- **Gradients are tables, not strings.** `"c1 c2 45deg"` is rejected as a single
  colour. Use `{ colors = {"c1","c2"}, angle = 45 }`. A single colour string is
  still accepted.
- **`hl.animation` requires an explicit `enabled`** — it is not defaulted.
- **`resizeactive` percentages have no equivalent.** `hl.dsp.window.resize`
  parses `x`/`y` with `tableOptNum` (`LuaBindingsDispatchers.cpp:1083`), so they
  must be numbers. `resizeactive exact 65% 65%` cannot be expressed; compute
  pixels from the monitor size, or do the work in a Lua bind handler where the
  monitor geometry is available.
- **Keys containing a dot need bracket syntax** in Lua tables:
  `["col.active_border"]`, not `col.active_border`.
- **`centerwindow` on a tiled window** returns `No floating window found`. That
  is the same no-op as before, not a translation error.
- **`hyprctl --batch "dispatch a; dispatch b"`** is broken for the same reason;
  split into separate calls, each with a Lua expression.

## Why scripts break silently

`hyprctl configerrors` validates that the *config file* loads. It says nothing
about the runtime IPC surface that scripts use. A config can be completely clean
while every `hyprctl dispatch` in the repo fails. Test the scripts, not just the
config.

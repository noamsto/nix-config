# Stable-path Claude plugin indirection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Point the `claude` wrapper's `--plugin-dir` at rebuild-stable HM symlinks instead of raw `/nix/store` paths, so running Claude sessions self-heal aeye hook-script + binary changes on the next hook fire after a switch — no restart.

**Architecture:** Declare two HM `xdg.configFile` directory symlinks under a neutral, HM-owned namespace, each sourced from the flake-input plugin dir. A switch repoints them atomically. Repoint the wrapper's two `--plugin-dir` args at those stable paths. No aeye/lazytmux code change — aeye hooks already reference `${CLAUDE_PLUGIN_ROOT}` relatively.

**Tech Stack:** Nix, home-manager (`xdg.configFile`, flake inputs), `nh`.

## Global Constraints

- Stable path MUST be HM-owned and MUST NOT sit under `~/.claude/plugins` (Claude's marketplace cache) or `~/.config/claude`. Use `~/.config/nix-managed/claude-plugins/{aeye,lazytmux}`.
- No code changes to aeye or lazytmux — nix-config wiring only.
- Do NOT push to `main`; work stays on branch `feat/aeye-plugin-stable-path`.
- Self-heal covers hook **script bodies** + PATH-resolved **binaries** only. `hooks.json` **structure** changes still need a session restart (read once at startup).
- The `claude` wrapper module is `home/ai/claude-code/default.nix`; module args in scope: `pkgs lib config inputs osConfig`.

---

### Task 1: Stable-path symlinks + wrapper repoint

**Files:**
- Modify: `home/ai/claude-code/default.nix` — add `xdg.configFile` block (config section) + repoint the two `--plugin-dir` args in `claude-wrapper` (currently `home/ai/claude-code/default.nix:186`)

**Interfaces:**
- Consumes: `inputs.lazytmux` (its `/claude-plugin` dir), `inputs.lazytmux.inputs.aeye` (its `/adapters/claude-code/plugin` dir), `config.xdg.configHome`.
- Produces: stable plugin paths `${config.xdg.configHome}/nix-managed/claude-plugins/{lazytmux,aeye}` that the wrapper passes to `--plugin-dir`; a running Claude session's `CLAUDE_PLUGIN_ROOT` becomes one of these stable paths.

- [ ] **Step 1: Add the stable-path symlinks**

In `home/ai/claude-code/default.nix`, in the `in { ... }` config block (e.g. right after the `home = { ... };` block that holds `home.file`), add:

```nix
  # Rebuild-stable plugin paths: a switch repoints these symlinks atomically, so
  # a running Claude session (which froze --plugin-dir into CLAUDE_PLUGIN_ROOT at
  # launch) resolves the NEW plugin scripts on the next hook fire — no restart.
  # Sourced from the flake inputs; a neutral namespace, never ~/.claude/plugins
  # (Claude's own marketplace cache) or ~/.config/claude.
  xdg.configFile = {
    "nix-managed/claude-plugins/lazytmux".source = inputs.lazytmux + "/claude-plugin";
    "nix-managed/claude-plugins/aeye".source = inputs.lazytmux.inputs.aeye + "/adapters/claude-code/plugin";
  };
```

- [ ] **Step 2: Repoint the wrapper's `--plugin-dir` args**

In the same file, replace the wrapper `exec` line (currently at :186):

```nix
      exec -a claude ${claude-wrapped}/bin/claude --settings ${nix-settings-json} --plugin-dir ${inputs.lazytmux}/claude-plugin --plugin-dir ${inputs.lazytmux.inputs.aeye}/adapters/claude-code/plugin "$@"
```

with:

```nix
      exec -a claude ${claude-wrapped}/bin/claude --settings ${nix-settings-json} --plugin-dir ${config.xdg.configHome}/nix-managed/claude-plugins/lazytmux --plugin-dir ${config.xdg.configHome}/nix-managed/claude-plugins/aeye "$@"
```

- [ ] **Step 3: Build (eval + realize) — must succeed**

Run (from the worktree):
```bash
nh home build .#"noams@$(hostname)"
```
Expected: build completes with no eval error. If it errors on `xdg.configFile … source` type, change `+ "/…"` concatenation to the string form `"${inputs.lazytmux}/claude-plugin"` and rebuild. If it errors that the target directory already exists / collision, the namespace clashed — confirm nothing else manages `~/.config/nix-managed`.

- [ ] **Step 4: Activate + verify the symlinks resolve to the plugins**

Run:
```bash
nh home switch .#"noams@$(hostname)"
readlink -f ~/.config/nix-managed/claude-plugins/aeye
ls ~/.config/nix-managed/claude-plugins/aeye/hooks/hooks.json ~/.config/nix-managed/claude-plugins/lazytmux
```
Expected: `readlink -f` prints a `/nix/store/…/adapters/claude-code/plugin` path; both `ls` targets exist. (On this Linux host `nh os switch` also activates HM — either works.)

- [ ] **Step 5: Verify a fresh session loads plugins from the stable path**

Launch a fresh `claude` (a new pane), then confirm the wrapper now injects the stable path and the plugin still loads:
```bash
pgrep -af 'claude' | grep -o 'nix-managed/claude-plugins/aeye' | head -1
```
Expected: prints `nix-managed/claude-plugins/aeye` (the wrapper's `--plugin-dir` is now the stable path). In that fresh session, Read an image, then:
```bash
grep -c . /tmp/claude-status/images/*.jsonl 2>/dev/null
```
Expected: the capture landed (≥1) — plugin hooks fire correctly through the symlink. Regression check: `/aeye:image-gallery` and diagram capture still work in the fresh session.

- [ ] **Step 6: Self-heal integration check (the whole point)**

With a Claude session already running (launched after Step 4), bump the aeye input and switch WITHOUT restarting that session, then trigger a capture and confirm the new hook script ran:
```bash
# in ~/nix-config on your normal branch, or simulate by pointing the input at a newer rev
nh home switch .#"noams@$(hostname)"
readlink -f ~/.config/nix-managed/claude-plugins/aeye   # now the NEW store path
```
Then, in the still-running session, Read an image and confirm the new `images.sh` behavior (e.g. with aeye ≥ #140, an out-of-cwd path merely printed in Bash stdout is NOT captured). Expected: the running session used the new script — no restart. Document this as the acceptance criterion; it is a manual check.

- [ ] **Step 7: Commit**

```bash
git add home/ai/claude-code/default.nix
git commit -m "feat(claude): stable-path --plugin-dir so switches self-heal running sessions

Point the claude wrapper at rebuild-stable HM symlinks under
~/.config/nix-managed/claude-plugins instead of raw /nix/store paths. A running
session froze --plugin-dir into CLAUDE_PLUGIN_ROOT at launch; with the symlink,
a switch repoints it and the next hook fire runs the new scripts — no restart.
Mirrors the rebuild-stable-path principle already used for codex status hooks."
```

---

## Notes for the implementer

- **One-time transition:** sessions currently running the OLD store-path wrapper keep the old `--plugin-dir` arg; they need ONE restart to adopt the stable path, then self-heal across all future switches. Step 5/6 verification must use a session launched AFTER Step 4.
- **If `xdg.configFile … .source` rejects a directory** in this HM version, fall back to `home.file."nix-managed/…"` with the same `.source`, or set `recursive = false` explicitly (it is the default). Do NOT use `recursive = true` — that symlinks each file individually and breaks the single-dir-repoint semantics.
- **lazytmux plugin** is included for parity; the motivating fix is aeye. If the lazytmux `claude-plugin` path differs in a future lazytmux rev, adjust the `.source` subpath.

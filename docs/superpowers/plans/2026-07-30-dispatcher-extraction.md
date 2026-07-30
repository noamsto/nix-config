# Dispatcher Harness Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the dispatcher harness out of `nix-config` into a standalone, tested, multi-engine repo `noamsto/dispatcher`.

**Architecture:** A new repo laid out as `adapters/{core,claude-code,codex,cursor}`, following the proven `aeye` pattern. `adapters/core` holds the three engine-neutral shell CLIs (`crew`, `dispatch`, `dispatcher`), the protocols, and one shared markdown body per command. A generator script projects those bodies into each engine's native shape — commands for Claude Code and cursor, skills for codex (codex has no custom slash commands). A Nix flake exposes packages plus `homeManagerModules.default`; `nix-config` consumes it as a flake input.

**Tech Stack:** bash (shellcheck-clean via `writeShellApplication`), bats-core, Nix flakes + flake-parts, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-07-30-dispatcher-extraction-design.md`

## Global Constraints

- Repo name `noamsto/dispatcher`. HM option `programs.dispatcher.*`. CC plugin `dispatcher@noamsto`.
- **Shell moves verbatim.** Only three intended behaviour changes exist (protocol path resolution, fish→bash launcher, `DISPATCH_PROFILE`→module option). Any other diff to `crew.sh` / `dispatch.sh` is a bug in this migration.
- **Nothing is deleted from `nix-config` until Task 7's three-engine verification passes.** Task 8 is the only irreversible task.
- Codex plugins must be installed as a **real directory** under `~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/`. A symlinked tree reports "installed, enabled" in `codex plugin list` while its skills never reach the model. Use `cp -rL` + `chmod -R u+w`.
- Cursor `~/.cursor/rules/*.mdc` files are **silently ignored** without `alwaysApply: true` frontmatter.
- Hook script paths: codex uses `"$PLUGIN_ROOT"`, Claude Code uses `"${CLAUDE_PLUGIN_ROOT}"`.
- Protocol path resolution order is always: `$DISPATCHER_PROTOCOL_DIR` → baked store path. Never a `~/nix-config/...` literal.
- Every task ends with a commit. Work in a worktree (`wt switch -c <branch>`), never on `main`.

---

### Task 1: Scaffold the repo, CI, and the bats harness

**Files:**
- Create: `~/Data/git/noamsto/dispatcher/` (new git repo)
- Create: `flake.nix`, `.envrc`, `.gitignore`, `README.md`
- Create: `tests/helpers.bash`, `tests/smoke.bats`
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: nothing.
- Produces: a devshell providing `bats`, `shellcheck`, `jq`, `git`, `tmux`; `tests/helpers.bash` exporting `setup_repo()` and `stub_bin()` used by every later test file.

- [ ] **Step 1: Create the repo**

```bash
mkdir -p ~/Data/git/noamsto/dispatcher
cd ~/Data/git/noamsto/dispatcher
git init -b main
gh repo create noamsto/dispatcher --private --source=. --remote=origin
```

Keep it private until Task 8; flip to public once the cutover is verified.

- [ ] **Step 2: Scaffold the flake with the bootstrap skill**

Invoke the `bootstrap-nix-repo` skill (generic project type). It produces the flake-parts `flake.nix`, `.envrc`, `.gitignore`, treefmt and git-hooks wiring to this repo's conventions. Then add these to the devshell's `packages`:

```nix
packages = with pkgs; [bats shellcheck jq git tmux gh];
```

- [ ] **Step 3: Write the test helper**

Create `tests/helpers.bash`:

```bash
# Shared bats helpers.

# setup_repo — a throwaway git repo as $TEST_REPO, cwd set to it.
setup_repo() {
  TEST_REPO="$(mktemp -d)"
  cd "$TEST_REPO" || return 1
  git init -q -b main .
  git config user.email test@example.com
  git config user.name test
  export TEST_REPO
}

teardown_repo() {
  [ -n "${TEST_REPO:-}" ] && rm -rf "$TEST_REPO"
}

# stub_bin <name> — put a logging stub for <name> first on PATH.
# The stub appends its argv (NUL-free, one invocation per line) to
# $STUB_LOG and exits 0.
stub_bin() {
  STUB_DIR="${STUB_DIR:-$(mktemp -d)}"
  STUB_LOG="${STUB_LOG:-$STUB_DIR/calls.log}"
  cat >"$STUB_DIR/$1" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
exit 0
EOF
  chmod +x "$STUB_DIR/$1"
  export STUB_DIR STUB_LOG
  export PATH="$STUB_DIR:$PATH"
}
```

- [ ] **Step 4: Write a smoke test that proves the harness runs**

Create `tests/smoke.bats`:

```bash
setup() {
  load helpers
  setup_repo
}

teardown() {
  teardown_repo
}

@test "setup_repo creates a git repo" {
  run git rev-parse --is-inside-work-tree
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "stub_bin intercepts a command and logs argv" {
  stub_bin tmux
  tmux send-keys -t pane0 'hello' Enter
  run cat "$STUB_LOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"send-keys -t pane0 hello Enter"* ]]
}
```

- [ ] **Step 5: Run the smoke test — expect PASS**

```bash
nix develop -c bats tests/smoke.bats
```

Expected: `2 tests, 0 failures`. If `stub_bin` fails, the PATH prepend is not taking effect — fix before continuing, every later task depends on it.

- [ ] **Step 6: Add CI**

Create `.github/workflows/ci.yml`:

```yaml
name: ci
on:
  push:
    branches: [main]
  pull_request:

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: DeterminateSystems/nix-installer-action@main
      - uses: DeterminateSystems/magic-nix-cache-action@main
      - name: shellcheck
        run: nix develop -c shellcheck adapters/core/*.sh
      - name: bats
        run: nix develop -c bats tests/
      - name: flake check
        run: nix flake check
```

`shellcheck adapters/core/*.sh` will fail until Task 2 adds files — that is expected and fixed by Task 2's commit. Do not add a `|| true`.

- [ ] **Step 7: Commit**

```bash
git add flake.nix flake.lock .envrc .gitignore README.md tests .github
git commit -m "chore: scaffold flake, devshell, bats harness, CI"
```

---

### Task 2: Move `crew.sh` verbatim and cover it with bats

**Files:**
- Create: `adapters/core/crew.sh` (copied from `~/nix-config/home/ai/claude-code/crew.sh`, 833 L, unmodified)
- Create: `tests/crew.bats`

**Interfaces:**
- Consumes: `tests/helpers.bash` from Task 1.
- Produces: `adapters/core/crew.sh`, a `writeShellApplication` body (no shebang, no `set -euo pipefail` — those are prepended at build). Subcommand surface, verbatim from its usage line:
  `crew id | identity <branch> | status <from> <state> [detail] [pr] | msg <from> <to> <body> | reply <to> <body> | await <agent> | register [pid] | deregister | watch | roster [crew] | inbox <agent> [crew] | stall-watch <branch> --pane <id> | log [crew] | report [crew] | rate | reap [--quiet] [--dry-run]`

- [ ] **Step 1: Copy the file unmodified**

```bash
mkdir -p adapters/core
cp ~/nix-config/home/ai/claude-code/crew.sh adapters/core/crew.sh
```

- [ ] **Step 2: Verify it is byte-identical**

```bash
diff ~/nix-config/home/ai/claude-code/crew.sh adapters/core/crew.sh
```

Expected: no output. Any diff means the copy was edited — redo it.

- [ ] **Step 3: Write the failing tests**

Create `tests/crew.bats`. `crew.sh` is a `writeShellApplication` body, so tests run it through `bash -euo pipefail`.

```bash
setup() {
  load helpers
  CREW="$BATS_TEST_DIRNAME/../adapters/core/crew.sh"
  run_crew() { bash -euo pipefail "$CREW" "$@"; }
  setup_repo
}

teardown() {
  teardown_repo
}

@test "id: honours CREW_ID when set" {
  CREW_ID=1720800000-12345 run run_crew id
  [ "$status" -eq 0 ]
  [ "$output" = "1720800000-12345" ]
}

@test "id: mints <epoch>-<pid> when CREW_ID is unset" {
  CREW_ID= run run_crew id
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+-[0-9]+$ ]]
}

@test "id: works outside a git repo" {
  cd /
  CREW_ID= run run_crew id
  [ "$status" -eq 0 ]
}

@test "identity: is deterministic over the branch" {
  run run_crew identity feat/foo
  [ "$status" -eq 0 ]
  first="$output"
  run run_crew identity feat/foo
  [ "$output" = "$first" ]
}

@test "identity: emits name, color and tmux keys" {
  run run_crew identity feat/foo
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'has("name") and has("color") and has("tmux")'
}

@test "repo-keyed subcommands refuse to run outside a git repo" {
  cd /
  CREW_ID=c1 run run_crew status worker working
  [ "$status" -eq 1 ]
  [[ "$output" == *"not in a git repo"* ]]
}

@test "status: rejects an unknown state" {
  CREW_ID=c1 run run_crew status worker bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"status state must be one of"* ]]
}

@test "status: accepts every documented state" {
  for s in working blocked pr_open done failed exited; do
    CREW_ID=c1 run run_crew status "worker-$s" "$s"
    [ "$status" -eq 0 ]
  done
}

@test "status: a repeated terminal state is written once" {
  CREW_ID=c1 run_crew status worker done
  CREW_ID=c1 run_crew status worker done
  log="$(git rev-parse --path-format=absolute --git-common-dir)/crew/events.jsonl"
  run grep -c '"state":"done"' "$log"
  [ "$output" = "1" ]
}

@test "status: a repeated non-terminal state is NOT deduped" {
  CREW_ID=c1 run_crew status worker working
  CREW_ID=c1 run_crew status worker working
  log="$(git rev-parse --path-format=absolute --git-common-dir)/crew/events.jsonl"
  run grep -c '"state":"working"' "$log"
  [ "$output" = "2" ]
}

@test "status: is addressed to the crew dispatcher" {
  CREW_ID=c1 run_crew status worker working
  log="$(git rev-parse --path-format=absolute --git-common-dir)/crew/events.jsonl"
  run jq -r 'select(.kind=="status") | .to' "$log"
  [ "$output" = "dispatcher:c1" ]
}

@test "status: fails when no crew id can be resolved" {
  CREW_ID= run run_crew status worker working
  [ "$status" -eq 1 ]
  [[ "$output" == *"CREW_ID unset"* ]]
}

@test "crew id resolves from WORKER_TASK.md when CREW_ID is unset" {
  printf 'crew_id: c-from-file\n' >WORKER_TASK.md
  CREW_ID= run_crew status worker working
  log="$(git rev-parse --path-format=absolute --git-common-dir)/crew/events.jsonl"
  run jq -r '.crew_id' "$log"
  [ "$output" = "c-from-file" ]
}

@test "msg: records from, to and body verbatim" {
  CREW_ID=c1 run_crew msg alice bob "ship it"
  log="$(git rev-parse --path-format=absolute --git-common-dir)/crew/events.jsonl"
  run jq -r 'select(.kind=="msg") | "\(.from)|\(.to)|\(.body)"' "$log"
  [ "$output" = "alice|bob|ship it" ]
}

@test "register: is idempotent for the same pid" {
  CREW_ID=c1 run run_crew register $$
  [ "$status" -eq 0 ]
  CREW_ID=c1 run run_crew register $$
  [ "$status" -eq 0 ]
}

@test "register: is non-exclusive across crews" {
  CREW_ID=c1 run run_crew register $$
  [ "$status" -eq 0 ]
  CREW_ID=c2 run run_crew register $$
  [ "$status" -eq 0 ]
}

@test "inbox: does not deliver a metrics-addressed message to the dispatcher" {
  CREW_ID=c1 run_crew msg worker "metrics:c1" '{"tier":"deep"}'
  CREW_ID=c1 run run_crew inbox "dispatcher:c1"
  [ "$status" -eq 0 ]
  [[ "$output" != *"deep"* ]]
}

@test "reap: rejects an unknown flag" {
  CREW_ID=c1 run run_crew reap --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"reap takes --quiet and --dry-run"* ]]
}

@test "reap: is a no-op when the bus has no events" {
  CREW_ID=c1 run run_crew reap
  [ "$status" -eq 0 ]
}

@test "reap: --dry-run removes no worktree" {
  stub_bin gh
  stub_bin wt
  CREW_ID=c1 run_crew status worker done
  CREW_ID=c1 run run_crew reap --dry-run
  [ "$status" -eq 0 ]
  run grep -c 'remove' "$STUB_LOG"
  [ "$output" = "0" ]
}
```

`reap` gates on the PR having landed, never on elapsed time — a worker sits in
`done` for as long as its PR takes to merge, answering review comments the whole
while, so a time-based sweep would delete live work. The `--dry-run` test pins
that no destructive `wt` call escapes.

That last test pins the behaviour `WORKER_PROTOCOL.md` depends on: the per-run metrics `msg` must **not** wake the dispatcher.

- [ ] **Step 4: Run the tests**

```bash
nix develop -c bats tests/crew.bats
```

Expected: all pass. `crew.sh` is already-working code, so these are characterization tests — a failure means either a bad copy or a wrong assumption in the test. Investigate before adjusting either.

- [ ] **Step 5: Run shellcheck**

```bash
nix develop -c shellcheck adapters/core/crew.sh
```

Expected: clean. The file carries `# shellcheck shell=bash` on line 1 precisely so it lints standalone.

- [ ] **Step 6: Commit**

```bash
git add adapters/core/crew.sh tests/crew.bats
git commit -m "feat(core): vendor crew bus verbatim with bats coverage"
```

---

### Task 3: Move `dispatch.sh` and the protocols; add `DISPATCHER_PROTOCOL_DIR`

**Files:**
- Create: `adapters/core/dispatch.sh` (from `~/nix-config/home/ai/claude-code/dispatch.sh`, 304 L)
- Create: `adapters/core/protocols/DISPATCHER_PROTOCOL.md`, `WORKER_PROTOCOL.md`, `dispatch-orchestration.md`
- Create: `tests/dispatch.bats`

**Interfaces:**
- Consumes: `crew` on PATH (stubbed in tests); `tests/helpers.bash`.
- Produces: `dispatch.sh` resolving `PROTOCOL_DIR="${DISPATCHER_PROTOCOL_DIR:-@protocolDir@}"`. `@protocolDir@` is substituted at build time in Task 6. Arg surface unchanged:
  `dispatch <trivial|standard|deep> <model> --effort <low|medium|high|xhigh|max|ultra> [--agent claude|codex|cursor] [--mcp <profile>] [--plan provided|required] [--crew-id <id>] [LINEAR-ID|#N] <title...>`

- [ ] **Step 1: Copy the files unmodified**

```bash
mkdir -p adapters/core/protocols
cp ~/nix-config/home/ai/claude-code/dispatch.sh adapters/core/dispatch.sh
cp ~/nix-config/home/ai/claude-code/DISPATCHER_PROTOCOL.md adapters/core/protocols/
cp ~/nix-config/home/ai/claude-code/WORKER_PROTOCOL.md adapters/core/protocols/
cp ~/nix-config/home/ai/claude-code/dispatch-orchestration.md adapters/core/protocols/
```

- [ ] **Step 2: Confirm exactly three hardcoded protocol paths exist**

```bash
grep -n 'nix-config' adapters/core/dispatch.sh
```

Expected: three hits, at the codex, cursor and claude launch strings (lines 274, 289, 292 as of `15b818c5`). Trust the count, not the line numbers — this file changes often. If the count is not 3, stop and re-read the file; the substitution below assumes exactly these three.

- [ ] **Step 3: Add the protocol-dir resolver**

Insert immediately after the `usage()` function definition (before `tier="${1:-}"`):

```bash
# Protocol directory. The env override is the dev loop: point it at a checkout
# and protocol edits take effect on the next dispatch with no rebuild. The
# default is substituted to a store path at build time.
PROTOCOL_DIR="${DISPATCHER_PROTOCOL_DIR:-@protocolDir@}"
```

- [ ] **Step 4: Replace the three hardcoded paths**

```bash
sed -i 's|~/nix-config/home/ai/claude-code/WORKER_PROTOCOL.md|'"'"'"$PROTOCOL_DIR"'"'"'/WORKER_PROTOCOL.md|g' adapters/core/dispatch.sh
```

That `sed` is fiddly to read, so verify the result by eye instead of trusting it. Each of the three launch lines must now read `"$PROTOCOL_DIR"/WORKER_PROTOCOL.md`, with the quoting intact so the value expands in the dispatching shell and reaches `tmux send-keys` as a literal absolute path. Re-run `grep -n 'nix-config' adapters/core/dispatch.sh` — expected: no output.

- [ ] **Step 5: Write the failing tests**

Create `tests/dispatch.bats`:

```bash
setup() {
  load helpers
  DISPATCH="$BATS_TEST_DIRNAME/../adapters/core/dispatch.sh"
  run_dispatch() { bash -euo pipefail "$DISPATCH" "$@"; }
  setup_repo
  stub_bin tmux
  stub_bin crew
  stub_bin gh
  stub_bin wt
  export DISPATCHER_PROTOCOL_DIR=/opt/protocols
}

teardown() {
  teardown_repo
}

@test "rejects an unknown tier" {
  run run_dispatch bogus sonnet --effort medium "title"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: dispatch"* ]]
}

@test "requires a model" {
  run run_dispatch standard
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: dispatch"* ]]
}

@test "rejects an unknown agent" {
  run run_dispatch standard sonnet --agent bogus --effort medium "title"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--agent must be claude, codex, or cursor"* ]]
}

@test "rejects an unknown effort" {
  run run_dispatch standard sonnet --effort bogus "title"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--effort must be low, medium, high, xhigh, max, or ultra"* ]]
}

@test "gates codex behind the work profile" {
  DISPATCH_PROFILE=personal run run_dispatch standard gpt-5.6-sol --agent codex --effort high --crew-id c1 "title"
  [ "$status" -eq 1 ]
  [[ "$output" == *"codex is work-profile only"* ]]
}

@test "gates cursor behind the work profile" {
  DISPATCH_PROFILE=personal run run_dispatch standard kimi-k3-high --agent cursor --effort high --crew-id c1 "title"
  [ "$status" -eq 1 ]
  [[ "$output" == *"work-profile only"* ]]
}

@test "the profile gate fires before any worktree is scaffolded" {
  DISPATCH_PROFILE=personal run run_dispatch standard gpt-5.6-sol --agent codex --effort high --crew-id c1 "title"
  [ "$status" -eq 1 ]
  run grep -c 'switch' "$STUB_LOG"
  [ "$output" = "0" ]
}

@test "no launch string references nix-config" {
  run grep -c 'nix-config' "$DISPATCH"
  [ "$output" = "0" ]
}

@test "DISPATCHER_PROTOCOL_DIR overrides the baked default" {
  run grep -c 'DISPATCHER_PROTOCOL_DIR:-@protocolDir@' "$DISPATCH"
  [ "$output" = "1" ]
}
```

- [ ] **Step 6: Run the tests**

```bash
nix develop -c bats tests/dispatch.bats
```

Expected: all pass.

If `the profile gate fires before any worktree is scaffolded` fails, the gate has moved below the `wt` call — that is a real regression against the comment at `dispatch.sh:117-120`, which exists so the failure is a clear message rather than a later `codex: command not found`. Fix the ordering, not the test.

- [ ] **Step 7: Run shellcheck**

```bash
nix develop -c shellcheck adapters/core/dispatch.sh
```

Expected: clean.

- [ ] **Step 8: Commit**

```bash
git add adapters/core/dispatch.sh adapters/core/protocols tests/dispatch.bats
git commit -m "feat(core): vendor dispatch + protocols, resolve protocol dir via env"
```

---

### Task 4: Port the fish launcher to `dispatcher.sh`

**Files:**
- Create: `adapters/core/dispatcher.sh`
- Create: `tests/dispatcher.bats`
- Read for reference: `~/nix-config/home/terminal/fish/default.nix:199-333`

**Interfaces:**
- Consumes: `crew` (stubbed in tests), `tmux`, `tmux-reflow-windows`, `claude`/`codex`/`cursor-agent`.
- Produces: `dispatcher [--agent claude|codex|cursor] [--model M] [--effort E] [task...]`. Same flag surface as the fish function, all optional and order-independent; the bare `dispatcher <task>` form is preserved.

- [ ] **Step 1: Write the script**

Create `adapters/core/dispatcher.sh`. This is a `writeShellApplication` body — no shebang, no `set -euo pipefail`.

```bash
# shellcheck shell=bash
# dispatcher — start an orchestrator session with DISPATCHER_PROTOCOL baked in.
# Ported from a fish autoload function; `dispatch` made the same move earlier.
# One behaviour change is unavoidable: a script cannot export CREW_ID back into
# the caller's interactive shell the way `set -gx` did, so the id is printed.

PROTOCOL_DIR="${DISPATCHER_PROTOCOL_DIR:-@protocolDir@}"
protocol="$PROTOCOL_DIR/DISPATCHER_PROTOCOL.md"

agent=claude
model=""
effort=""
task=""

while [ $# -gt 0 ]; do
  case "$1" in
  --agent)
    agent="${2:-}"
    shift 2
    ;;
  --model)
    model="${2:-}"
    shift 2
    ;;
  --effort)
    effort="${2:-}"
    shift 2
    ;;
  *)
    task="${task:+$task }$1"
    shift
    ;;
  esac
done

case "$agent" in
claude | codex | cursor) ;;
*)
  echo "dispatcher: --agent must be claude, codex, or cursor" >&2
  exit 1
  ;;
esac

profile="${DISPATCH_PROFILE:-personal}"
if [ "$agent" != claude ] && [ "$profile" != work ]; then
  echo "dispatcher: --agent $agent is work-profile only" >&2
  exit 1
fi

if [ -n "$effort" ]; then
  case "$effort" in
  low | medium | high | xhigh | max | ultra) ;;
  *)
    echo "dispatcher: --effort must be low, medium, high, xhigh, max, or ultra" >&2
    exit 1
    ;;
  esac
fi

# Fixed identity for the orchestrator window so it stands out from the
# per-branch worker windows it spawns. Guarded on $TMUX — the dispatcher can be
# launched outside a tmux pane.
if [ -n "${TMUX:-}" ]; then
  tmux set-window-option pane-border-style "bg=#{@thm_bg},fg=#{@thm_mauve}"
  tmux set-window-option pane-active-border-style "bg=#{@thm_bg},fg=#{@thm_mauve},bold"
  tmux set-window-option pane-border-format " #[bold]dispatcher#[nobold] "
  # Same @crew_* options `dispatch` stamps on workers, so lazytmux renders the
  # orchestrator badge too. colour99 clears contrast on both Catppuccin themes.
  tmux set-window-option @crew_name dispatcher
  tmux set-window-option @crew_color colour99
  # No tmux event fires on a user-option set, and lazytmux's per-tick poll only
  # runs for the session a client is viewing — kick a reflow or the badge won't
  # render until you next switch to this window.
  tmux-reflow-windows \
    "$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}')" \
    "$(tmux display-message -p -t "$TMUX_PANE" '#{window_width}')"
fi

session_name=dispatcher
[ -n "$task" ] && session_name="dispatcher: $task"

# Mint + export the crew id once at launch (mirrors `dispatch`), so the launched
# agent and every child `dispatch` inherit the SAME crew. `crew id` needs no git
# repo. Printed because a script cannot export back to the calling shell.
: "${CREW_ID:=$(crew id)}"
export CREW_ID
echo "crew id: $CREW_ID"

if git rev-parse --git-common-dir >/dev/null 2>&1; then
  crew register $$
fi

case "$agent" in
claude)
  set -- --name "$session_name" --append-system-prompt-file "$protocol"
  [ -n "$model" ] && set -- "$@" --model "$model"
  [ -n "$effort" ] && set -- "$@" --effort "$effort"
  claude "$@" ${task:+"$task"}
  ;;
codex | cursor)
  # Neither CLI has --append-system-prompt-file — inject the protocol as the
  # first prompt (the same pattern dispatch.sh uses for codex/cursor workers).
  prompt="Read $protocol and adopt the dispatcher role for the rest of this session: judge each task into tier + engine + model + effort per the rubric, scaffold one worker per task via dispatch, and run the crew-watch loop per YOUR engine's section of the protocol (you are a $agent dispatcher). CREW_ID is already exported in this environment, so dispatch and crew calls inherit it."
  [ -n "$task" ] && prompt="$prompt First task: $task"
  if [ "$agent" = codex ]; then
    # Effort high, not xhigh: blocked workers wait on a bounded ~300s in-band
    # window; xhigh turns would let blocks go stale. service_tier pinned — the
    # interactive /fast toggle persists locally and would otherwise leak into
    # the unattended dispatcher at 2.5x cost.
    codex --profile worker \
      -m "${model:-gpt-5.6-sol}" \
      -c "model_reasoning_effort=\"${effort:-high}\"" \
      -c "service_tier=\"default\"" \
      --dangerously-bypass-approvals-and-sandbox "$prompt"
  else
    # kimi-k3-high: third-family model, strong agentic tool use. --effort is
    # accepted-and-ignored (cursor encodes effort in the model id).
    [ -n "$effort" ] && echo "dispatcher: --effort is ignored for cursor (effort lives in the model id)" >&2
    cursor-agent --model "${model:-kimi-k3-high}" \
      --force --trust --approve-mcps --disable-indexing --disable-codebase-ref "$prompt"
  fi
  ;;
esac

# The launches above are children, not exec — deregister so the bus doesn't
# accumulate stale entries.
if git rev-parse --git-common-dir >/dev/null 2>&1; then
  crew deregister
fi
```

- [ ] **Step 2: Write the failing tests**

Create `tests/dispatcher.bats`:

```bash
setup() {
  load helpers
  LAUNCHER="$BATS_TEST_DIRNAME/../adapters/core/dispatcher.sh"
  run_launcher() { bash -euo pipefail "$LAUNCHER" "$@"; }
  setup_repo
  stub_bin tmux
  stub_bin crew
  stub_bin claude
  stub_bin codex
  stub_bin cursor-agent
  export DISPATCHER_PROTOCOL_DIR=/opt/protocols
  unset TMUX
}

teardown() {
  teardown_repo
}

@test "rejects an unknown agent" {
  run run_launcher --agent bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"--agent must be claude, codex, or cursor"* ]]
}

@test "gates codex behind the work profile" {
  DISPATCH_PROFILE=personal run run_launcher --agent codex
  [ "$status" -eq 1 ]
  [[ "$output" == *"work-profile only"* ]]
}

@test "rejects an unknown effort" {
  run run_launcher --effort bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"--effort must be"* ]]
}

@test "prints the crew id it minted" {
  CREW_ID=1720800000-99 run run_launcher
  [ "$status" -eq 0 ]
  [[ "$output" == *"crew id: 1720800000-99"* ]]
}

@test "passes the protocol to claude as an appended system prompt" {
  CREW_ID=c1 run_launcher
  run grep -F -- '--append-system-prompt-file /opt/protocols/DISPATCHER_PROTOCOL.md' "$STUB_LOG"
  [ "$status" -eq 0 ]
}

@test "the bare form treats all non-flag args as one task" {
  CREW_ID=c1 run_launcher fix the flaky test
  run grep -F -- '--name dispatcher: fix the flaky test' "$STUB_LOG"
  [ "$status" -eq 0 ]
}

@test "injects the protocol as a first prompt for codex" {
  DISPATCH_PROFILE=work CREW_ID=c1 run_launcher --agent codex
  run grep -F -- 'Read /opt/protocols/DISPATCHER_PROTOCOL.md' "$STUB_LOG"
  [ "$status" -eq 0 ]
}

@test "warns that effort is ignored for cursor" {
  DISPATCH_PROFILE=work CREW_ID=c1 run run_launcher --agent cursor --effort high
  [[ "$output" == *"--effort is ignored for cursor"* ]]
}

@test "skips tmux window stamping when not inside tmux" {
  CREW_ID=c1 run_launcher
  run grep -c 'set-window-option' "$STUB_LOG"
  [ "$output" = "0" ]
}

@test "registers and deregisters around the agent launch" {
  CREW_ID=c1 run_launcher
  run grep -c 'register' "$STUB_LOG"
  [ "$output" -ge 2 ]
}
```

- [ ] **Step 3: Run the tests**

```bash
nix develop -c bats tests/dispatcher.bats
```

Expected: all pass.

- [ ] **Step 4: Run shellcheck**

```bash
nix develop -c shellcheck adapters/core/dispatcher.sh
```

Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add adapters/core/dispatcher.sh tests/dispatcher.bats
git commit -m "feat(core): port the dispatcher launcher from fish to bash"
```

---

### Task 5: Shared command bodies, the adapter generator, and the three adapter trees

**Files:**
- Create: `adapters/core/commands/{dispatcher,autopilot,finish-prs,project-autopilot}.md`
- Create: `adapters/core/dispatch-notify.sh`
- Create: `scripts/gen-adapters.sh`
- Create: `adapters/claude-code/plugin/` (`.claude-plugin/plugin.json`, `commands/`, `agents/`, `skills/spec-plan-critic/`, `workflows/`, `hooks/hooks.json`, `scripts/`)
- Create: `adapters/codex/plugin/` (`.codex-plugin/plugin.json`, `skills/`, `hooks/hooks.json`, `scripts/`), `adapters/codex/.agents/plugins/marketplace.json`
- Create: `adapters/cursor/{rules,commands}/`
- Create: `tests/adapters.bats`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `scripts/gen-adapters.sh` — regenerates every adapter tree from `adapters/core/commands/`; idempotent, so CI can assert `git diff --exit-code`.

- [ ] **Step 1: Copy the command bodies and the notify hook**

```bash
mkdir -p adapters/core/commands
cd ~/nix-config/home/ai/claude-code
cp commands/dispatcher.md commands/autopilot.md commands/finish-prs.md commands/project-autopilot.md \
  ~/Data/git/noamsto/dispatcher/adapters/core/commands/
cp dispatch-notify.sh ~/Data/git/noamsto/dispatcher/adapters/core/
cd ~/Data/git/noamsto/dispatcher
```

- [ ] **Step 2: Fix the two stale references in the command bodies**

In `adapters/core/commands/dispatcher.md`, replace the hardcoded protocol path:

```
Read `~/nix-config/home/ai/claude-code/DISPATCHER_PROTOCOL.md` now and adopt that
```

with:

```
Read the `DISPATCHER_PROTOCOL.md` shipped with this plugin now and adopt that
```

In `adapters/core/commands/project-autopilot.md`, the teammate prompt says each teammate runs `/autopilot TICKET-ID`. Plugin commands are namespaced, so change that to `/dispatcher:autopilot TICKET-ID`.

- [ ] **Step 3: Copy the critic pipeline into the Claude Code adapter**

```bash
mkdir -p adapters/claude-code/plugin/{agents,skills,workflows,hooks,scripts,.claude-plugin}
cd ~/nix-config/home/ai/claude-code
cp agents/spec-critic.md agents/plan-critic.md \
  ~/Data/git/noamsto/dispatcher/adapters/claude-code/plugin/agents/
cp -r skills/spec-plan-critic \
  ~/Data/git/noamsto/dispatcher/adapters/claude-code/plugin/skills/
cp workflows/spec-plan-critic.js \
  ~/Data/git/noamsto/dispatcher/adapters/claude-code/plugin/workflows/
cd ~/Data/git/noamsto/dispatcher
```

The codex adapter gets `spec-plan-critic` as a skill but **no** agents and **no** workflow — codex plugins cannot express either. This is why `WORKER_PROTOCOL.md` already marks codex/cursor runs process-light; it is a documented limitation, not an omission to fix here.

- [ ] **Step 4: Write the manifests**

`adapters/claude-code/plugin/.claude-plugin/plugin.json`:

```json
{
  "name": "dispatcher",
  "version": "0.1.0",
  "description": "Judge tasks into tier + engine + model, fan out one worker per task, coordinate over a git-backed crew bus.",
  "author": {"name": "Noam Stolero"},
  "commands": "./commands",
  "agents": "./agents",
  "skills": "./skills"
}
```

`adapters/codex/plugin/.codex-plugin/plugin.json`:

```json
{
  "name": "dispatcher",
  "version": "0.1.0",
  "description": "Judge tasks into tier + engine + model, fan out one worker per task, coordinate over a git-backed crew bus.",
  "author": {"name": "Noam Stolero"},
  "skills": "./skills",
  "interface": {
    "displayName": "dispatcher",
    "shortDescription": "Agent fan-out harness with a git-backed crew bus.",
    "longDescription": "Promotes a session into a dispatcher: judges each task into tier + engine + model + effort, scaffolds one worker per task in its own worktree and tmux window, and coordinates over a git-backed crew bus.",
    "developerName": "Noam Stolero",
    "category": "Productivity",
    "capabilities": ["Read", "Write"],
    "defaultPrompt": [
      "Become a dispatcher and fan out my open tasks",
      "Dispatch a worker for this ticket",
      "Show me the crew roster"
    ]
  }
}
```

`adapters/codex/.agents/plugins/marketplace.json`:

```json
{
  "name": "dispatcher",
  "interface": {"displayName": "dispatcher"},
  "plugins": [
    {
      "name": "dispatcher",
      "source": {"source": "local", "path": "./plugin"},
      "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"},
      "category": "Productivity"
    }
  ]
}
```

- [ ] **Step 5: Write the hooks**

`adapters/claude-code/plugin/hooks/hooks.json`:

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/scripts/dispatch-notify.sh"}
        ]
      }
    ]
  }
}
```

`adapters/codex/plugin/hooks/hooks.json` — identical but with codex's variable:

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {"type": "command", "command": "\"$PLUGIN_ROOT\"/scripts/dispatch-notify.sh"}
        ]
      }
    ]
  }
}
```

- [ ] **Step 6: Write the generator**

Create `scripts/gen-adapters.sh`:

```bash
#!/usr/bin/env bash
# Project the shared command bodies in adapters/core/commands/ into each
# engine's native shape. Idempotent — CI regenerates and asserts no diff.
#
#   claude-code : commands/<name>.md   (native slash commands)
#   cursor      : commands/<name>.md   (native slash commands)
#   codex       : skills/<name>/SKILL.md
#                 codex has NO custom slash commands (custom prompts are
#                 deprecated in favour of skills), so each command becomes a
#                 skill invoked as $<name> or via /skills.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/adapters/core/commands"

cc="$root/adapters/claude-code/plugin/commands"
cx="$root/adapters/codex/plugin/skills"
cu="$root/adapters/cursor/commands"

rm -rf "$cc" "$cu"
mkdir -p "$cc" "$cu" "$cx"

for f in "$src"/*.md; do
  name="$(basename "$f" .md)"

  cp "$f" "$cc/$name.md"
  cp "$f" "$cu/$name.md"

  # codex: same body, re-fronted as a skill.
  mkdir -p "$cx/$name"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$(awk -F'"' '/^description:/ {print $2; exit}' "$f")"
    printf -- '---\n\n'
    # Body with the source frontmatter stripped, if it has any.
    if [ "$(head -1 "$f")" = "---" ]; then
      awk 'NR>1 && /^---$/ {found=1; next} found' "$f"
    else
      cat "$f"
    fi
  } >"$cx/$name/SKILL.md"
done

# Copy the notify hook into both plugin trees.
for d in "$root/adapters/claude-code/plugin" "$root/adapters/codex/plugin"; do
  mkdir -p "$d/scripts"
  cp "$root/adapters/core/dispatch-notify.sh" "$d/scripts/dispatch-notify.sh"
  chmod +x "$d/scripts/dispatch-notify.sh"
done

# codex gets spec-plan-critic as a skill; it can express neither agents nor
# workflows, so its workers stay process-light per WORKER_PROTOCOL.md.
mkdir -p "$cx/spec-plan-critic"
cp "$root/adapters/claude-code/plugin/skills/spec-plan-critic/SKILL.md" \
  "$cx/spec-plan-critic/SKILL.md"

echo "adapters regenerated"
```

Make it executable: `chmod +x scripts/gen-adapters.sh`

- [ ] **Step 7: Write the cursor rule**

Create `adapters/cursor/rules/dispatcher.mdc`. The `alwaysApply: true` frontmatter is mandatory — without it cursor silently ignores the file, and an ignored file is indistinguishable from an unsupported path.

```markdown
---
alwaysApply: true
---

# Dispatcher harness

`crew`, `dispatch` and `dispatcher` are on your PATH.

- `dispatcher` promotes a session into an orchestrator: it judges each task into
  tier + engine + model + effort, scaffolds one worker per task via `dispatch`,
  and watches the `crew` bus. A dispatcher never implements, gates, or opens PRs.
- A dispatched worker reads `WORKER_PROTOCOL.md` and runs its task end-to-end.
- Cursor workers run single-agent: no plan-critic and no code-review gate. Emit
  `plan_critic_first_pass: null`, `review_high: null`, `review_mode: "none"` so a
  run is never mistaken for reviewed-and-clean.

Run `crew` with no arguments for the full subcommand surface.
```

- [ ] **Step 8: Run the generator**

```bash
./scripts/gen-adapters.sh
```

Expected: `adapters regenerated`.

- [ ] **Step 9: Write the tests**

Create `tests/adapters.bats`:

```bash
setup() {
  load helpers
  ROOT="$BATS_TEST_DIRNAME/.."
}

@test "generator is idempotent" {
  "$ROOT/scripts/gen-adapters.sh"
  run git -C "$ROOT" diff --exit-code
  [ "$status" -eq 0 ]
}

@test "all four commands reach claude-code and cursor" {
  for n in dispatcher autopilot finish-prs project-autopilot; do
    [ -f "$ROOT/adapters/claude-code/plugin/commands/$n.md" ]
    [ -f "$ROOT/adapters/cursor/commands/$n.md" ]
  done
}

@test "all four commands reach codex as skills" {
  for n in dispatcher autopilot finish-prs project-autopilot; do
    [ -f "$ROOT/adapters/codex/plugin/skills/$n/SKILL.md" ]
  done
}

@test "codex skills carry name and description frontmatter" {
  run head -4 "$ROOT/adapters/codex/plugin/skills/autopilot/SKILL.md"
  [[ "$output" == *"name: autopilot"* ]]
  [[ "$output" == *"description:"* ]]
}

@test "every manifest is valid json" {
  jq -e . "$ROOT/adapters/claude-code/plugin/.claude-plugin/plugin.json"
  jq -e . "$ROOT/adapters/codex/plugin/.codex-plugin/plugin.json"
  jq -e . "$ROOT/adapters/codex/.agents/plugins/marketplace.json"
  jq -e . "$ROOT/adapters/claude-code/plugin/hooks/hooks.json"
  jq -e . "$ROOT/adapters/codex/plugin/hooks/hooks.json"
}

@test "each engine's hooks use that engine's plugin-root variable" {
  run grep -F 'CLAUDE_PLUGIN_ROOT' "$ROOT/adapters/claude-code/plugin/hooks/hooks.json"
  [ "$status" -eq 0 ]
  run grep -F '$PLUGIN_ROOT' "$ROOT/adapters/codex/plugin/hooks/hooks.json"
  [ "$status" -eq 0 ]
  run grep -c 'CLAUDE_PLUGIN_ROOT' "$ROOT/adapters/codex/plugin/hooks/hooks.json"
  [ "$output" = "0" ]
}

@test "the cursor rule sets alwaysApply, else cursor ignores it silently" {
  run head -3 "$ROOT/adapters/cursor/rules/dispatcher.mdc"
  [[ "$output" == *"alwaysApply: true"* ]]
}

@test "no command body references nix-config" {
  run grep -rl 'nix-config' "$ROOT/adapters/"
  [ "$status" -ne 0 ]
}

@test "project-autopilot points teammates at the namespaced autopilot" {
  run grep -F '/dispatcher:autopilot' "$ROOT/adapters/core/commands/project-autopilot.md"
  [ "$status" -eq 0 ]
}

@test "codex adapter ships no agents and no workflows" {
  [ ! -d "$ROOT/adapters/codex/plugin/agents" ]
  [ ! -d "$ROOT/adapters/codex/plugin/workflows" ]
}
```

- [ ] **Step 10: Run the tests**

```bash
nix develop -c bats tests/adapters.bats
```

Expected: all pass. Note `generator is idempotent` only means something once the generated files are committed — run it again after Step 11 and confirm it still passes.

- [ ] **Step 11: Commit**

```bash
git add adapters scripts tests/adapters.bats
git commit -m "feat(adapters): shared command bodies projected into claude-code, codex and cursor"
```

- [ ] **Step 12: Add the drift gate to CI**

Append to `.github/workflows/ci.yml` under `steps:`:

```yaml
      - name: adapters are in sync
        run: |
          nix develop -c ./scripts/gen-adapters.sh
          git diff --exit-code
```

Commit:

```bash
git add .github/workflows/ci.yml
git commit -m "ci: fail when generated adapters drift from their source bodies"
```

---

### Task 6: Flake packages and the Home Manager module

**Files:**
- Modify: `flake.nix`
- Create: `nix/hm-module.nix`
- Create: `tests/module.bats`

**Interfaces:**
- Consumes: everything in `adapters/`.
- Produces: `packages.{crew,dispatch,dispatcher}`, `packages.default`, and `homeManagerModules.default` with options `programs.dispatcher.enable` (bool) and `programs.dispatcher.profile` (enum `"work"|"personal"`, default `"personal"`).

- [ ] **Step 1: Add the packages to `flake.nix`**

Inside `perSystem = {pkgs, ...}: {`:

```nix
packages = let
  protocols = ./adapters/core/protocols;
  sub = builtins.replaceStrings ["@protocolDir@"] ["${protocols}"];
in rec {
  crew = pkgs.writeShellApplication {
    name = "crew";
    runtimeInputs = with pkgs; [git jq coreutils gnugrep tmux];
    text = builtins.readFile ./adapters/core/crew.sh;
  };

  dispatch = pkgs.writeShellApplication {
    name = "dispatch";
    runtimeInputs = (with pkgs; [gh git jq gnused coreutils tmux]) ++ [crew];
    text = sub (builtins.readFile ./adapters/core/dispatch.sh);
  };

  dispatcher = pkgs.writeShellApplication {
    name = "dispatcher";
    runtimeInputs = (with pkgs; [git jq coreutils tmux]) ++ [crew];
    text = sub (builtins.readFile ./adapters/core/dispatcher.sh);
  };

  default = pkgs.symlinkJoin {
    name = "dispatcher-all";
    paths = [crew dispatch dispatcher];
  };
};
```

`crew` deliberately has **no** substitution — it never references the protocols. `dispatch` and `dispatcher` list `crew` in `runtimeInputs` because both shell out to it. `wt` (worktrunk) is intentionally absent: it resolves from the ambient session PATH, which `writeShellApplication` preserves.

- [ ] **Step 2: Write the Home Manager module**

Create `nix/hm-module.nix`:

```nix
self: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.dispatcher;
  pkgsFor = self.packages.${pkgs.stdenv.hostPlatform.system};
  ccPlugin = "${self}/adapters/claude-code/plugin";
  codexPlugin = "${self}/adapters/codex/plugin";
  codexVersion = (lib.importJSON "${codexPlugin}/.codex-plugin/plugin.json").version;
  codexCache = ".codex/plugins/cache/dispatcher/dispatcher";
in {
  options.programs.dispatcher = {
    enable = lib.mkEnableOption "the dispatcher agent fan-out harness";

    profile = lib.mkOption {
      type = lib.types.enum ["work" "personal"];
      default = "personal";
      description = ''
        Gates the codex and cursor engines, which are work-profile only.
        Replaces the DISPATCH_PROFILE environment variable.
      '';
    };

    claudePluginDir = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = ccPlugin;
      description = ''
        Pass to claude via --plugin-dir. Read-only; consumers reference it
        rather than reconstructing the store path.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [pkgsFor.crew pkgsFor.dispatch pkgsFor.dispatcher];

    home.sessionVariables = {
      DISPATCH_PROFILE = cfg.profile;
      # Exported, not just baked into the CLIs. The `dispatcher` slash command
      # and the cursor rule are markdown an agent reads live, so they resolve
      # the protocol through this variable via their Bash tool — a build-time
      # substitution into the shell scripts cannot reach them. Each plugin also
      # ships a protocols/ copy as the fallback when this is unset (a non-Nix
      # install). Override it in your shell to iterate on a checkout.
      DISPATCHER_PROTOCOL_DIR = "${self}/adapters/core/protocols";
    };

    # Cursor has no plugin format yet — loose files are the only channel.
    # The .mdc rule is silently ignored without alwaysApply: true frontmatter,
    # which the shipped file provides.
    home.file = {
      ".cursor/rules/dispatcher.mdc".source = "${self}/adapters/cursor/rules/dispatcher.mdc";
      ".cursor/commands" = {
        source = "${self}/adapters/cursor/commands";
        recursive = true;
      };
    };

    # Codex loads plugins ONLY from a real directory under
    # ~/.codex/plugins/cache. A symlinked tree reports "installed, enabled" in
    # `codex plugin list` while its skills never reach the model — hence cp -rL.
    # chmod lets the next switch replace the read-only store copy.
    home.activation.dispatcherCodexPlugin = lib.hm.dag.entryAfter ["writeBoundary"] ''
      run rm -rf "$HOME/${codexCache}"
      run mkdir -p "$HOME/${codexCache}"
      run cp -rL ${codexPlugin} "$HOME/${codexCache}/${codexVersion}"
      run chmod -R u+w "$HOME/${codexCache}"
    '';

    assertions = [
      {
        assertion = cfg.profile != "work" || config.programs.codex.enable or true;
        message = ''
          programs.dispatcher.profile = "work" dispatches codex workers with
          `--profile worker`, which requires ~/.codex/worker.config.toml. That
          file is managed outside this module — see the codex HM module.
        '';
      }
    ];
  };
}
```

- [ ] **Step 3: Export the module from `flake.nix`**

At the top level of the flake outputs (outside `perSystem`):

```nix
flake.homeManagerModules.default = import ./nix/hm-module.nix self;
```

`self` must be in scope — use `{self, ...}@inputs:` in the flake-parts module arguments.

The `[marketplaces.dispatcher]` and `[plugins."dispatcher@dispatcher"]` stanzas in `~/.codex/config.toml` are hand-managed (no store path, so not Nix's job). Document that in `README.md` — the codex adapter is inert without them.

- [ ] **Step 4: Test the build**

```bash
nix build .#crew .#dispatch .#dispatcher
nix flake check
```

Expected: all succeed.

- [ ] **Step 5: Verify the protocol path was actually substituted**

```bash
grep -o 'DISPATCHER_PROTOCOL_DIR:-[^}]*' result/bin/dispatch
```

Expected: a `/nix/store/...` path, **not** the literal `@protocolDir@`. If the placeholder survived, `builtins.replaceStrings` was applied to the wrong string — fix before continuing, or every dispatched worker will fail to find its protocol.

```bash
test -f "$(grep -o '/nix/store/[^"}]*' result/bin/dispatch | head -1)/WORKER_PROTOCOL.md" && echo OK
```

Expected: `OK`.

- [ ] **Step 5b: Verify the module exports DISPATCHER_PROTOCOL_DIR**

The `dispatcher` slash command and the cursor rule resolve the protocol through
this variable at read time; a build-time substitution into the shell scripts
cannot reach them. Confirm the module declares it:

```bash
grep -n 'DISPATCHER_PROTOCOL_DIR' nix/hm-module.nix
```

Expected: one hit inside `home.sessionVariables`. Its absence is the defect the
Task 5 review caught — the command would reference an unset variable and fall
back to the plugin-local copy on every invocation, silently never honouring the
dev-loop override.

- [ ] **Step 6: Write the module tests**

Create `tests/module.bats`:

```bash
setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
}

@test "all three packages build" {
  run nix build --no-link "$ROOT#crew" "$ROOT#dispatch" "$ROOT#dispatcher"
  [ "$status" -eq 0 ]
}

@test "the protocol placeholder is substituted in dispatch" {
  nix build --no-link --print-out-paths "$ROOT#dispatch" >/tmp/d.out
  run grep -c '@protocolDir@' "$(cat /tmp/d.out)/bin/dispatch"
  [ "$output" = "0" ]
}

@test "the protocol placeholder is substituted in dispatcher" {
  nix build --no-link --print-out-paths "$ROOT#dispatcher" >/tmp/l.out
  run grep -c '@protocolDir@' "$(cat /tmp/l.out)/bin/dispatcher"
  [ "$output" = "0" ]
}

@test "the substituted protocol dir actually contains the protocols" {
  nix build --no-link --print-out-paths "$ROOT#dispatch" >/tmp/d.out
  dir="$(grep -o '/nix/store/[^"}]*' "$(cat /tmp/d.out)/bin/dispatch" | head -1)"
  [ -f "$dir/WORKER_PROTOCOL.md" ]
  [ -f "$dir/DISPATCHER_PROTOCOL.md" ]
}
```

- [ ] **Step 7: Run the tests**

```bash
nix develop -c bats tests/module.bats
```

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add flake.nix flake.lock nix tests/module.bats README.md
git commit -m "feat(nix): packages and home-manager module"
git push -u origin main
```

---

### Task 7: Wire into nix-config behind `override-input` and verify all three engines

Nothing is deleted in this task. The goal is a running system where the new repo is authoritative while the old files still exist, so a failure is a one-line revert.

**Files:**
- Modify: `~/nix-config/flake.nix` (add the input)
- Modify: `~/nix-config/home/ai/claude-code/default.nix`
- Modify: `~/nix-config/home/terminal/fish/default.nix` (remove the fish `dispatcher` function)

- [ ] **Step 1: Branch nix-config**

```bash
cd ~/nix-config
wt switch -c feat/dispatcher-extraction
```

- [ ] **Step 2: Add the flake input**

In `~/nix-config/flake.nix`, alongside the `agent-smith` and `resolved` inputs:

```nix
    # Dispatcher agent fan-out harness (crew bus + dispatch + protocols,
    # with claude-code/codex/cursor adapters).
    dispatcher = {
      url = "github:noamsto/dispatcher";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

- [ ] **Step 3: Point it at the local checkout**

```bash
nix flake lock --override-input dispatcher ~/Data/git/noamsto/dispatcher
```

This is the same pattern used for the lazytmux darwin port. Nothing is pinned to a remote commit until Task 8.

- [ ] **Step 4: Rewire `home/ai/claude-code/default.nix`**

Delete the `crew`, `dispatch` and `dispatch-notify` `let` bindings, the `SessionEnd` hook block in `nix-settings-json`, `home.packages = [crew dispatch]`, and `sessionVariables.DISPATCH_PROFILE`. Add to `imports`:

```nix
    inputs.dispatcher.homeManagerModules.default
```

Add to `programs`:

```nix
    dispatcher = {
      enable = true;
      profile = osConfig.profile;
    };
```

Add the plugin dir to the claude wrapper's `exec` line, alongside the existing lazytmux and aeye `--plugin-dir` flags:

```
--plugin-dir ${inputs.dispatcher}/adapters/claude-code/plugin
```

- [ ] **Step 5: Remove the fish launcher**

Delete the `"fish/functions/dispatcher.fish"` block from `~/nix-config/home/terminal/fish/default.nix` (lines 199-333, including the leading comment). `dispatcher` now arrives on PATH from the module.

- [ ] **Step 6: Stage and rebuild**

Untracked files are invisible to `nix build`, so stage first:

```bash
git add -A
nh home switch
```

Expected: builds and activates. If it fails on the `programs.codex.enable` assertion, that option does not exist in this config — relax the assertion in `nix/hm-module.nix` to check for the file instead, and re-run.

- [ ] **Step 7: Verify the CLIs resolve to the new store paths**

```bash
which crew dispatch dispatcher
echo $DISPATCH_PROFILE
```

Expected: three `/nix/store/...` paths, and `work` on the work machine.

- [ ] **Step 8: Verify each engine's adapter actually loaded**

```bash
claude --version >/dev/null && echo "claude ok"
codex plugin list | grep dispatcher
ls ~/.cursor/commands/ ~/.cursor/rules/dispatcher.mdc
```

For codex, `plugin list` showing "installed, enabled" is **not sufficient** — that is exactly the false positive the symlink trap produces. Confirm the real payload:

```bash
ls -la ~/.codex/plugins/cache/dispatcher/dispatcher/*/skills/
```

Expected: a real directory containing `autopilot/`, `dispatcher/`, `finish-prs/`, `project-autopilot/`, `spec-plan-critic/` — not a symlink.

Then add the hand-managed stanzas to `~/.codex/config.toml` if absent:

```toml
[marketplaces.dispatcher]
source = "local"
path = "/home/noams/.codex/plugins/cache/dispatcher"

[plugins."dispatcher@dispatcher"]
enabled = true
```

- [ ] **Step 9: End-to-end verification on all three engines**

Use the `crew-smoke` repo as the target.

```bash
cd ~/Data/git/noamsto/crew-smoke
dispatcher
```

In the dispatcher session, dispatch one trivial worker per engine and confirm each reaches `pr_open`:

```
dispatch --crew-id <id> trivial haiku --effort low "add a line to README"
dispatch --crew-id <id> trivial gpt-5.6-sol --agent codex --effort low "add a line to README"
dispatch --crew-id <id> trivial kimi-k3-high --agent cursor --effort low "add a line to README"
```

For each: the tmux window carries the crew badge, `crew roster` lists the worker, and a PR opens. Confirm each worker read its protocol from the **store path** (or your override), not from `~/nix-config` — `crew log` shows the launch string.

- [ ] **Step 10: Verify the dev loop**

```bash
export DISPATCHER_PROTOCOL_DIR=~/Data/git/noamsto/dispatcher/adapters/core/protocols
dispatch --crew-id <id> trivial haiku --effort low "another line"
```

Expected: the launch string references your checkout, not the store. Edit a protocol, dispatch again, confirm the edit is live with no rebuild. **This is the primary deliverable of the whole extraction** — if it does not work, stop and fix it before Task 8.

- [ ] **Step 11: Commit (nothing deleted yet)**

```bash
cd ~/nix-config
git add -A
git commit -m "feat(dispatcher): consume the extracted harness as a flake input"
```

---

### Task 8: Cut over — delete from nix-config, migrate the docs, pin the input

The only irreversible task. Do not start until Task 7 Step 9 and Step 10 both passed.

- [ ] **Step 1: Migrate the design docs**

```bash
cd ~/Data/git/noamsto/dispatcher
mkdir -p docs/superpowers/{specs,plans}
cd ~/nix-config
cp docs/superpowers/specs/*dispatch* docs/superpowers/specs/*crew* \
  ~/Data/git/noamsto/dispatcher/docs/superpowers/specs/ 2>/dev/null || true
cp docs/superpowers/plans/*dispatch* docs/superpowers/plans/*crew* docs/superpowers/plans/*worker* \
  ~/Data/git/noamsto/dispatcher/docs/superpowers/plans/ 2>/dev/null || true
```

Verify the count before deleting anything:

```bash
ls ~/Data/git/noamsto/dispatcher/docs/superpowers/specs/ | wc -l
ls ~/Data/git/noamsto/dispatcher/docs/superpowers/plans/ | wc -l
```

Expected: roughly 8 specs and 14 plans. Read the filenames and confirm each is dispatcher/crew/worker work, not an unrelated doc caught by the glob.

- [ ] **Step 2: Commit the docs in the new repo**

```bash
cd ~/Data/git/noamsto/dispatcher
git add docs
git commit -m "docs: migrate dispatcher design history from nix-config"
git push
```

- [ ] **Step 3: Delete the moved files from nix-config**

```bash
cd ~/nix-config/home/ai/claude-code
gtrash put crew.sh dispatch.sh dispatch-notify.sh
gtrash put DISPATCHER_PROTOCOL.md WORKER_PROTOCOL.md dispatch-orchestration.md
gtrash put commands/dispatcher.md commands/autopilot.md commands/finish-prs.md commands/project-autopilot.md
gtrash put agents/spec-critic.md agents/plan-critic.md
gtrash put skills/spec-plan-critic workflows/spec-plan-critic.js
cd ~/nix-config
gtrash put docs/superpowers/specs/*dispatch* docs/superpowers/specs/*crew*
gtrash put docs/superpowers/plans/*dispatch* docs/superpowers/plans/*crew* docs/superpowers/plans/*worker*
```

`.claude/commands` stays a whole-directory symlink — the four files simply leave the source directory, and `/pr-review`, `/commit`, `/push` are untouched.

- [ ] **Step 4: Confirm no dangling references**

```bash
cd ~/nix-config
rg -n 'DISPATCHER_PROTOCOL|WORKER_PROTOCOL|dispatch-orchestration|spec-plan-critic|crew\.sh|dispatch\.sh' \
  --glob '!docs/**' --glob '!.git/**' .
```

Expected: no output. Any hit is a file that still points at something deleted — fix it now.

- [ ] **Step 5: Rebuild and re-verify**

```bash
git add -A
nh home switch
```

Then re-run Task 7 Step 9 for the claude engine at minimum. Expected: identical behaviour.

- [ ] **Step 6: Pin the input to a real commit**

```bash
nix flake lock --override-input dispatcher github:noamsto/dispatcher
```

Confirm `flake.lock` now carries a 40-character `rev` for `dispatcher`, not a local path. A branch ref with a fixed hash is the time bomb documented in the repo's gotchas — the lock must name a commit.

- [ ] **Step 7: Rebuild against the pinned input**

```bash
git add -A
nh home switch
```

Expected: succeeds. Re-run one trivial dispatch to confirm.

- [ ] **Step 8: Commit and open the PR**

```bash
git add -A
git commit -m "refactor(dispatcher): extract the harness into noamsto/dispatcher"
git push -u origin feat/dispatcher-extraction
gh pr create --fill
```

- [ ] **Step 9: Make the new repo public**

```bash
gh repo edit noamsto/dispatcher --visibility public --accept-visibility-change-consequences
```

---

## Verification Summary

| Task | Deliverable | Verified by |
|---|---|---|
| 1 | Repo, devshell, CI, bats harness | `bats tests/smoke.bats` → 2 pass |
| 2 | `crew` vendored + tested | `diff` clean; `bats tests/crew.bats` |
| 3 | `dispatch` + protocols, env-resolved | `grep nix-config` → 0; `bats tests/dispatch.bats` |
| 4 | `dispatcher` ported to bash | `bats tests/dispatcher.bats` |
| 5 | Three adapter trees + drift gate | `bats tests/adapters.bats`; CI `git diff --exit-code` |
| 6 | Packages + HM module | `nix flake check`; placeholder substituted |
| 7 | nix-config consumes it; nothing deleted | trivial dispatch green on all 3 engines; dev loop live |
| 8 | Cutover complete | no dangling refs; pinned rev; PR open |

## Rollback

Tasks 1-6 touch only the new repo — nothing to roll back.

Task 7 is one commit in `nix-config` on a branch: `git revert` plus `nh home switch` restores the previous state, because the old files still exist.

Task 8 is the cutover. If it fails after Step 3, the deleted files are in `gtrash` (`gtrash restore`) and the branch is unmerged — reset it. Once the PR merges, recovery is a `git revert` of the merge commit.

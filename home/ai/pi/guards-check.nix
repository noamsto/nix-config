# End-to-end check for ./guards.nix, over the real production path: the locked
# hookyard binary installs the real manifest, then routes real pi `tool_call`
# payloads through it and we assert the pi response it renders back.
#
# Nothing here is a fixture copy of a guard's predicate. Every assertion runs
# the same handler executables the manifest names, behind the same router,
# envelope normalization, deny-wins consolidation and pi verdict rendering the
# installed bridge calls — so a matcher or payload-shape mismatch shows up as a
# guard that stopped blocking, which is the failure mode this migration could
# otherwise hide (a guard that abstains is silent and fails open).
{
  pkgs,
  hookyard,
}: let
  inherit (import ./guards.nix {inherit pkgs;}) manifest handlers;

  execFor = id: (builtins.head (builtins.filter (h: h.id == id) handlers)).exec;
  psqlGuardExec = execFor "guards.pi.psql";
  readAdapterExec = execFor "guards.pi.read-skeleton";
  secretReadExec = execFor "guards.pi.secret-read-paths";
in
  pkgs.runCommand "pi-guards-hookyard-check" {
    nativeBuildInputs = [hookyard pkgs.jq pkgs.git pkgs.gnugrep pkgs.coreutils pkgs.nodejs];
  } ''
        set -euo pipefail

        export HOME=$TMPDIR/home
        mkdir -p "$HOME"
        export GIT_CONFIG_GLOBAL=$HOME/.gitconfig
        git config --global user.email check@example.com
        git config --global user.name check
        git config --global init.defaultBranch main
        git config --global commit.gpgsign false

        state=$TMPDIR/state
        ambient=$TMPDIR/pi-agent/settings.json
        worker=$TMPDIR/pi-worker/settings.json
        mkdir -p "$(dirname "$ambient")" "$(dirname "$worker")"

        # Two --pi-settings, as ../hookyard configures: the dispatcher launches pi
        # workers under their own PI_CODING_AGENT_DIR, and a manifest that installs
        # into only the ambient dir would leave those workers unguarded.
        hookyard install \
          --manifest ${manifest} \
          --state-dir "$state" \
          --codex-config "$TMPDIR/codex.toml" \
          --cursor-hooks "$TMPDIR/cursor-hooks.json" \
          --pi-settings "$ambient" \
          --pi-settings "$worker"

        for settings in "$ambient" "$worker"; do
          bridge=$(dirname "$settings")/bin/hookyard-bridge.ts
          [ -f "$bridge" ] || { echo "FAIL: no bridge installed beside $settings"; exit 1; }
          jq -e --arg b "$bridge" '.extensions | index($b)' "$settings" >/dev/null \
            || { echo "FAIL: $settings does not register $bridge"; exit 1; }
        done

        # The dispatcher is the second writer of the worker's settings.json, and it
        # merges (dispatcher adapters/core/crew.sh: `$base + {defaultProjectTrust:…}`).
        # A seeder that rewrote the file instead would silently unguard every
        # `--no-approve` worker, so its merge shape is replayed here.
        seeded=$(jq -n --argjson base "$(cat "$worker")" '$base + {defaultProjectTrust: "never"}')
        jq -e --arg b "$(dirname "$worker")/bin/hookyard-bridge.ts" '.extensions | index($b)' <<<"$seeded" >/dev/null \
          || { echo "FAIL: the dispatcher seeder's merge drops hookyard's extensions entry"; echo "  got: $seeded"; exit 1; }

        cat >"$TMPDIR/harness.mjs" <<'JS'
    import { readFile } from "node:fs/promises";
    import { pathToFileURL } from "node:url";

    const [bridgePath, cwd, scriptPath] = process.argv.slice(2);
    const steps = JSON.parse(await readFile(scriptPath, "utf8"));
    const { default: bridge } = await import(pathToFileURL(bridgePath).href);

    const registered = [];
    bridge({
      on: (event, handler) => registered.push({ event, handler }),
      registerCommand: () => {},
    });

    const ctx = {
      cwd,
      sessionManager: {
        getSessionId: () => "probe-session",
        getSessionFile: () => undefined,
      },
      ui: { notify: () => {} },
    };

    // Mirrors hookyard's own piBridgeHarness runHandlers (internal/render/pi_bridge_runtime_test.go):
    // tool_call short-circuits on the first block and otherwise returns the last
    // truthy reply; every other event chains {content} patches through one
    // shared event object, exactly as pi's own tool_result middleware does.
    async function runHandlers(eventName, handlers, payload) {
      if (eventName === "tool_call") {
        let lastTruthy = null;
        for (const { handler } of handlers) {
          const result = await handler(payload, ctx);
          if (result && result.block === true) return result;
          if (result != null) lastTruthy = result;
        }
        return lastTruthy;
      }
      let event = payload;
      let changed = false;
      let lastReturn = null;
      for (const { handler } of handlers) {
        const result = await handler(event, ctx);
        if (result != null) lastReturn = result;
        if (result && result.content !== undefined) {
          event = { ...event, content: result.content };
          changed = true;
        }
      }
      return changed ? { content: event.content } : lastReturn;
    }

    const returns = [];
    for (const step of steps) {
      const handlers = registered.filter((r) => r.event === step.event);
      if (handlers.length === 0) throw new Error("nothing registered for " + step.event);
      returns.push((await runHandlers(step.event, handlers, step.payload)) ?? null);
    }
    process.stdout.write(JSON.stringify(returns));
    JS

        route() {
          hookyard route --registered-for pi --event pre_tool --state-dir "$state"
        }

        # Drives the REAL installed pi_bridge.ts (not just the Go router CLI) through
        # a minimal Node harness that fakes pi's extension-loading API — the same
        # technique hookyard's own pi_bridge_runtime_test.go uses. This is the only
        # way to observe the tool_result-append delivery path: the Go `route` CLI's
        # JSON reply never leaves the router: the bridge is what turns it into a
        # stashed advisory and later appends it to that call's own tool_result.
        bridge_drive() {
          local settings=$1 cwd=$2 steps=$3
          local bridge="$(dirname "$settings")/bin/hookyard-bridge.ts"
          local bridge_mjs="$TMPDIR/bridge-drive.mjs"
          # Plain ESM JS under a .ts name (the bridge's own header comment) — node's
          # loader picks modules by extension, so a same-bytes .mjs copy is how this
          # drives the identical file `hookyard install` wrote.
          cp "$bridge" "$bridge_mjs"
          local script="$TMPDIR/bridge-drive-script.json"
          printf '%s' "$steps" >"$script"
          node "$TMPDIR/harness.mjs" "$bridge_mjs" "$cwd" "$script"
        }

        # The payload hookyard's own bridge authors for a pi tool_call. Its shape is
        # pinned upstream by the committed pi-tool_call.json fixture, not invented
        # here; `bash`/`read` are pi's native tool names, which hookyard maps to the
        # canonical Bash/Read the guards match on.
        bash_payload() {
          jq -n --arg cwd "$1" --arg cmd "$2" '{
            hook_event_name: "tool_call", pi_version: "0.0.0-check", session_id: "check",
            cwd: $cwd, session_file: "", argv: [],
            tool_name: "bash", tool_input: {command: $cmd}, tool_use_id: "call-1"
          }'
        }

        read_payload() {
          jq -n --arg cwd "$1" --arg path "$2" --argjson limit "$3" '{
            hook_event_name: "tool_call", pi_version: "0.0.0-check", session_id: "check",
            cwd: $cwd, session_file: "", argv: [],
            tool_name: "read", tool_input: {path: $path, limit: $limit}, tool_use_id: "call-1"
          }'
        }

        # Same, but `path` is whatever raw JSON is passed — used to prove the
        # adapter survives a shape pi's own tool schema should never produce.
        read_payload_raw() {
          jq -n --arg cwd "$1" --argjson path "$2" '{
            hook_event_name: "tool_call", pi_version: "0.0.0-check", session_id: "check",
            cwd: $cwd, session_file: "", argv: [],
            tool_name: "read", tool_input: {path: $path}, tool_use_id: "call-1"
          }'
        }

        grep_payload() {
          jq -n --arg cwd "$1" --arg path "$2" --arg pattern "$3" --arg glob "''${4:-}" '{
            hook_event_name: "tool_call", pi_version: "0.0.0-check", session_id: "check",
            cwd: $cwd, session_file: "", argv: [],
            tool_name: "grep",
            tool_input: ({pattern: $pattern, path: $path} + (if $glob == "" then {} else {glob: $glob} end)),
            tool_use_id: "call-1"
          }'
        }

        fail() { echo "FAIL: $1"; echo "  got: ''${2:-<empty>}"; exit 1; }

        # hookyard's record of the call it just routed: one JSON line per tool
        # call, carrying every handler it ran and what each returned.
        last_record() { cat "$state"/stream/*.jsonl | tail -1; }

        # Every assertion captures this before routing and requires it to have
        # grown: `last_record` alone would re-read the previous call's record if
        # this call produced none, which two adjacent cases expecting the same
        # (handler, outcome) pair would pass on while proving nothing.
        records() {
          local n
          n=$(cat "$state"/stream/*.jsonl 2>/dev/null | wc -l) || n=0
          printf '%s' "$n"
        }

        # The load-bearing half of every case below. A guard that silently stopped
        # matching renders exactly what a guard that deliberately allowed renders —
        # nothing — so asserting the rendered response alone cannot tell "abstained"
        # from "never ran". The record can: it names the handler and its outcome.
        assert_outcome() {
          local name=$1 id=$2 want=$3 before=$4 rec
          [ "$(records)" -gt "$before" ] \
            || fail "$name: routing appended no record, so nothing was actually asked" ""
          rec=$(last_record)
          jq -e --arg i "$id" --arg w "$want" \
            'any(.handlers[]; .name == $i and .outcome == $w)' <<<"$rec" >/dev/null 2>&1 \
            || fail "$name: $id should have recorded outcome $want" "$rec"
        }

        # Positive: the call is blocked, the named guard is the one that objected,
        # and the reason carries every substring.
        assert_blocked() {
          local name=$1 id=$2 outcome=$3 payload=$4 out before
          shift 4
          before=$(records)
          out=$(route <<<"$payload")
          jq -e '.block == true' <<<"$out" >/dev/null 2>&1 || fail "$name: expected block:true" "$out"
          assert_outcome "$name" "$id" "$outcome" "$before"
          for want in "$@"; do
            jq -e --arg w "$want" '.reason | contains($w)' <<<"$out" >/dev/null 2>&1 \
              || fail "$name: reason missing $want" "$out"
          done
        }

        # Negative: nothing is rendered, so pi runs the tool — and the named guard
        # ran and declined, rather than never having been asked.
        assert_allowed() {
          local name=$1 id=$2 outcome=$3 payload=$4 out before
          before=$(records)
          out=$(route <<<"$payload")
          [ -z "$out" ] || fail "$name: expected the call to run" "$out"
          assert_outcome "$name" "$id" "$outcome" "$before"
        }

        ## git-default-branch, with git-commit-autostage's advice riding the denial.
        repo=$TMPDIR/repo
        git init -q "$repo"
        echo one >"$repo/tracked"
        git -C "$repo" add tracked
        git -C "$repo" commit -qm initial
        # Staged + unstaged tracked changes together: the autostage advisory's
        # trigger, so both handlers speak on the same call.
        echo two >>"$repo/tracked"
        git -C "$repo" add tracked
        echo three >>"$repo/tracked"

        assert_blocked "git-default-branch denies a commit on main" \
          guards.pi.git-default-branch deny \
          "$(bash_payload "$repo" 'git commit -m wip')" \
          'Refusing to commit directly to the default branch (main)' \
          'pre-commit will stash them'
        # …and the second substring above is git-commit-autostage's, so that guard
        # also saw a pi-normalized envelope and spoke on it. Named here so its
        # coverage does not rest on reading another guard's assertion.
        assert_outcome "git-commit-autostage advises on the same call" \
          guards.pi.git-commit-autostage advise "$(( $(records) - 1 ))"

        # The advisory must not double-deliver when it rides a denial: the
        # bridge only stashes on a non-block reply, so a blocked call's
        # tool_result must carry nothing extra.
        steps=$(jq -n --arg cmd 'git commit -m wip' '[
          {event:"tool_call", payload:{toolName:"bash", input:{command:$cmd}, toolCallId:"probe-main"}},
          {event:"tool_result", payload:{toolName:"bash", input:{command:$cmd}, toolCallId:"probe-main", content:[{type:"text",text:"stub"}], isError:true}}
        ]')
        returns=$(bridge_drive "$ambient" "$repo" "$steps")
        jq -e '.[0].block == true and (.[0].reason | contains("Refusing to commit directly to the default branch (main)")) and (.[0].reason | contains("pre-commit will stash them"))' <<<"$returns" >/dev/null 2>&1 \
          || fail "bridge tool_call should deny on main, advice riding the reason" "$returns"
        jq -e '.[1] == null' <<<"$returns" >/dev/null 2>&1 \
          || fail "a denied call must not also deliver the advisory via tool_result" "$returns"

        git -C "$repo" checkout -q -b feat/branch
        # Same working tree, same advisory trigger — no denial to ride. pi's
        # tool_call return has no standalone advisory slot (a pi platform limit,
        # proven live: hookyard#72, resolved by hookyard#75;
        # docs/design/hookyard.md §11.1 in the hookyard repo), so the bridge
        # stashes the advice by toolCallId and a bridge-owned tool_result handler
        # appends it onto that call's own tool result. The Go `route` CLI alone
        # can't observe this — only driving the installed bridge (below) can.
        #
        # `route`'s own reply for this exact call is no longer empty since
        # hookyard#75: it now renders {"advisory": "..."} for a pi pre_tool
        # abstain-with-advice, so this checks that shape directly rather than
        # asserting empty output.
        before=$(records)
        # NOT `out` — that is the derivation's own output path; see the comment
        # above the malformed-path probe loop below for why that matters.
        resp=$(route <<<"$(bash_payload "$repo" 'git commit -m wip')")
        jq -e '(.block // false) == false and (.advisory | contains("pre-commit will stash them"))' <<<"$resp" >/dev/null 2>&1 \
          || fail "an off-default-branch commit must not block, and must carry the standalone advisory" "$resp"
        assert_outcome "a commit off the default branch runs" \
          guards.pi.git-default-branch abstain "$before"
        assert_outcome "git-commit-autostage advises on the same call" \
          guards.pi.git-commit-autostage advise "$before"

        # The advisory now reaches the model, attached to this call's own
        # tool_result content, per hookyard#72/#75.
        steps=$(jq -n --arg cmd 'git commit -m wip' '[
          {event:"tool_call", payload:{toolName:"bash", input:{command:$cmd}, toolCallId:"probe-feat"}},
          {event:"tool_result", payload:{toolName:"bash", input:{command:$cmd}, toolCallId:"probe-feat", content:[{type:"text",text:"[feat/branch abc1234] wip"}], isError:false}}
        ]')
        returns=$(bridge_drive "$ambient" "$repo" "$steps")
        jq -e '.[0] == null' <<<"$returns" >/dev/null 2>&1 \
          || fail "bridge tool_call should allow (no block) off the default branch" "$returns"
        jq -e '(.[1].content[-1].text | contains("[hookyard advisory] ")) and (.[1].content[-1].text | contains("pre-commit will stash them"))' <<<"$returns" >/dev/null 2>&1 \
          || fail "bridge tool_result should carry the autostage advisory" "$returns"

        # git-commit-autostage's own negative: `-a` stages the tracked changes
        # itself, so there is no surprise stash to warn about.
        assert_allowed "git-commit-autostage stays quiet for git commit -a" \
          guards.pi.git-commit-autostage abstain \
          "$(bash_payload "$repo" 'git commit -a -m wip')"

        ## nix-stage
        flake=$TMPDIR/flake
        git init -q "$flake"
        touch "$flake/flake.nix"
        git -C "$flake" add flake.nix
        git -C "$flake" commit -qm initial
        touch "$flake/untracked.nix"

        assert_blocked "nix-stage denies a rebuild with an untracked .nix" \
          guards.pi.nix-stage deny \
          "$(bash_payload "$flake" 'nh home switch .')" \
          'Untracked .nix files (untracked.nix)'

        rm "$flake/untracked.nix"
        assert_allowed "nix-stage lets a clean tree rebuild" \
          guards.pi.nix-stage abstain \
          "$(bash_payload "$flake" 'nh home switch .')"

        ## read-skeleton, through its envelope adapter. Both path forms the adapter
        ## resolves are exercised: relative-to-cwd and `~`-rooted.
        big=$HOME/big.txt
        seq 400 >"$big"

        assert_blocked "read-skeleton denies an unbounded read (relative path)" \
          guards.pi.read-skeleton deny \
          "$(read_payload "$HOME" 'big.txt' null)" \
          "$big is 400 lines (>300)"

        assert_blocked "read-skeleton denies an unbounded read (~/ path)" \
          guards.pi.read-skeleton deny \
          "$(read_payload "$TMPDIR" '~/big.txt' null)" \
          "$big is 400 lines (>300)"

        assert_allowed "read-skeleton lets a bounded read through" \
          guards.pi.read-skeleton abstain \
          "$(read_payload "$HOME" 'big.txt' 50)"

        ## secret-read, through the same adapter for Read/Grep and untouched for Bash.
        assert_blocked "secret-read denies a Read of .env (relative path)" \
          guards.pi.secret-read-paths deny \
          "$(read_payload "$HOME" '.env' null)" \
          'Reading '"$HOME"'/.env would print live credentials'

        assert_blocked "secret-read denies a Read of a ~/-rooted credential file" \
          guards.pi.secret-read-paths deny \
          "$(read_payload "$TMPDIR" '~/.aws/credentials' null)" \
          'Reading '"$HOME"'/.aws/credentials would print live credentials'

        assert_blocked "secret-read denies an @-prefixed Read of .env (pi's @file mention)" \
          guards.pi.secret-read-paths deny \
          "$(read_payload "$HOME" '@.env' null)" \
          'Reading '"$HOME"'/.env would print live credentials'

        assert_allowed "secret-read lets an ordinary Read through" \
          guards.pi.secret-read-paths abstain \
          "$(read_payload "$HOME" 'big.txt' 50)"

        assert_allowed "secret-read lets a Read of a committed .env.example through" \
          guards.pi.secret-read-paths abstain \
          "$(read_payload "$HOME" '.env.example' null)"

        assert_blocked "secret-read denies cat .env in bash" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'cat .env')" \
          'prints credential-file content'

        assert_allowed "secret-read lets an ordinary bash command through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'ls -la')"

        ## secret-read: variable-dumping shell builtins that print a value
        ## without echoing it — the LINEAR_API_KEY incident
        ## (`fish -ic 'set -S LINEAR_API_KEY'`) plus the rest of the family
        ## named in nix-config#373: fish's set -S/-x/-gx/-U, bash/zsh's
        ## declare/export/typeset -p/-x, /proc/*/environ, and the
        ## tmux/systemctl/launchctl session-env dumpers.
        assert_blocked "secret-read denies fish set -S" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'set -S FAKE_API_KEY')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies fish set --show" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'set --show FAKE_API_KEY')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies a bare set" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'set')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies bash declare -p" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'declare -p FAKE_API_KEY')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies bash bare declare -x" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'declare -x')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies bash export -p" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'export -p')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies zsh typeset -p" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'typeset -p FAKE_API_KEY')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies tmux show-environment" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'tmux show-environment')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies systemctl --user show-environment" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'systemctl --user show-environment')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies launchctl getenv" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'launchctl getenv FAKE_API_KEY')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies /proc/*/environ" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'cat /proc/1234/environ')" \
          'reads a process'"'"'s environment table'

        assert_blocked "secret-read denies a quoted /proc/*/environ path" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'cat "/proc/1234/environ"')" \
          'reads a process'"'"'s environment table'

        assert_blocked "secret-read denies /proc/*/environ split via tr, not just cat" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "tr '\0' '\n' < /proc/self/environ")" \
          'reads a process'"'"'s environment table'

        # The literal incident: `fish -ic` combines the interactive and
        # command flags into one token, which a shell_c_re requiring a
        # standalone `-c` token would never match — letting the exact command
        # that forced the rotation straight through.
        assert_blocked "secret-read denies the literal LINEAR_API_KEY incident shape" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "fish -ic 'set -S FAKE_API_KEY' | grep -v -i value")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies set -U wrapped in fish -ic" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "fish -ic 'set -U'")" \
          'set -x/-gx/-U'

        assert_blocked "secret-read denies set -S wrapped in fish -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "fish -c 'set -S FAKE_API_KEY'")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies set --show wrapped in fish -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "fish -c 'set --show FAKE_API_KEY'")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies a bare set wrapped in fish -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "fish -c 'set'")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies declare -p wrapped in bash -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "bash -c 'declare -p FAKE_API_KEY'")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies declare -p wrapped in bash -lc" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "bash -lc 'declare -p FAKE_API_KEY'")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies bare declare -x wrapped in bash -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "bash -c 'declare -x'")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies export -p wrapped in sh -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "sh -c 'export -p'")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies typeset -p wrapped in bash -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "bash -c 'typeset -p FAKE_API_KEY'")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies tmux show-environment wrapped in bash -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "bash -c 'tmux show-environment'")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies systemctl --user show-environment wrapped in sh -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "sh -c 'systemctl --user show-environment'")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies launchctl getenv wrapped in bash -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "bash -c 'launchctl getenv FAKE_API_KEY'")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies /proc/*/environ wrapped in bash -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "bash -c 'cat /proc/1234/environ'")" \
          'reads a process'"'"'s environment table'

        assert_blocked "secret-read denies bare set -x wrapped in fish -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "fish -c 'set -x'")" \
          'set -x/-gx/-U'

        assert_blocked "secret-read denies bare set -gx wrapped in fish -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "fish -c 'set -gx'")" \
          'set -x/-gx/-U'

        assert_blocked "secret-read still denies a bare env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env')" \
          'bare env/printenv'

        assert_blocked "secret-read still denies a bare printenv" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'printenv')" \
          'bare env/printenv'

        assert_allowed "secret-read lets set -q through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'set -q FAKE_API_KEY')"

        assert_allowed "secret-read lets a set assignment through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'set -l foo bar')"

        assert_allowed "secret-read lets a bash presence check through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" '[ -n "''${FAKE_API_KEY:-}" ] && echo set || echo unset')"

        assert_allowed "secret-read lets set -gx with a name and value through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'set -gx PATH /usr/bin')"

        assert_allowed "secret-read lets declare -x with a name through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'declare -x FAKE_API_KEY=dummy')"

        assert_allowed "secret-read lets a top-level bash set -x (xtrace) through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'set -x')"

        assert_allowed "secret-read lets bash -c set -x (xtrace) through, not just top-level" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "bash -c 'set -x; true'")"

        assert_allowed "secret-read lets sh -c set -x (xtrace) through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "sh -c 'set -x'")"

        assert_allowed "secret-read lets set -gx with a name wrapped in fish -c through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "fish -c 'set -gx PATH /usr/bin'")"

        assert_allowed "secret-read lets set -q wrapped in fish -c through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "fish -c 'set -q FAKE_API_KEY'")"

        # Rule 2's old (^|[|;&]\s*)(printenv|env) matched a literal | sitting
        # next to the word even inside a quoted argument, so a search for the
        # word itself used to trip the guard it was checking.
        assert_allowed "secret-read lets a quoted regex containing env|printenv through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "rg 'env|printenv|foo' file")"

        # Reviewer-found bypasses (round 1): a single-level -c unwrap missed a
        # second layer of nesting, and neither mask_quotes nor the -c
        # extraction understood a backslash-escaped quote or the standard
        # close-quote/escaped-apostrophe/reopen-quote idiom for embedding a
        # literal apostrophe in a single-quoted argument — both let the rest
        # of the command, including a real dumper, ride past unmasked-away or
        # unextracted.
        assert_blocked "secret-read denies two levels of -c nesting" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "bash -c \"fish -c 'set -S FAKE_API_KEY'\"")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies a backslash-escaped quote at top level" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "echo \"\\\"\" ; declare -p FAKE_API_KEY")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies a backslash-escaped quote inside bash -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "bash -c \"echo \\\"hi\\\"; env\"")" \
          'bare env/printenv'

        assert_blocked "secret-read denies a backslash-escaped quote hiding set -S in fish -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "fish -c \"echo \\\"x\\\"; set -S FAKE_API_KEY\"")" \
          'lists or shows shell variables'

        # Close the quote, an escaped literal apostrophe, reopen — three
        # concatenated fragments with no space between them are ONE shell
        # word to bash. Below, an extra apostrophe is folded into each
        # doubled-up run because this whole file is itself a Nix multi-line
        # string, where two adjacent apostrophes are Nix's own escape
        # trigger for a literal pair of them; once rendered, each such run
        # collapses down to the plain two-apostrophe bash idiom.
        assert_blocked "secret-read denies the close-escape-reopen apostrophe idiom inside bash -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "bash -c 'echo '\\'''hi'\\'''; env'")" \
          'bare env/printenv'

        # Reviewer-found bypasses (round 2, after the round-1 fix above): a
        # single "cur" variable dropped every -c invocation after the first
        # one it matched, and $'...' (ANSI-C quoting) wasn't a recognized
        # quote form at all, so its leading $ survived into the decoded text
        # and pushed the dumper off the command-position anchor.
        assert_blocked "secret-read denies a dumper in a sibling -c invocation" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "bash -c 'true' ; bash -c 'declare -p FAKE_API_KEY'")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies a dumper behind two sibling -c invocations" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "fish -c 'true' ; fish -c 'true' ; fish -c 'set -S FAKE_API_KEY'")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies declare -p wrapped in bash -c with \$'...' quoting" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "bash -c \$'declare -p FAKE_API_KEY'")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies a bare env wrapped in sh -c with \$'...' quoting" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "sh -c \$'env'")" \
          'bare env/printenv'

        # Round 3: a newline is just as ordinary a statement separator as a
        # semicolon (this is what a multi-line Bash tool call looks like),
        # but decode_word's terminator set didn't include one — an unquoted
        # newline got folded into the current word, swallowing the next
        # invocation's shell name along with it and hiding the sibling scan
        # above ever finding it. Built via $'...' rather than a literal
        # newline in this source file, which is itself a Nix multi-line
        # string whose indentation stripping a raw embedded newline would
        # disrupt.
        nl_sibling=$'bash -c \'true\'\nbash -c \'declare -p FAKE_API_KEY\'''
        assert_blocked "secret-read denies a dumper in a newline-separated sibling -c invocation" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "$nl_sibling")" \
          'lists or shows shell variables'

        # Round 4 (nix-config#376): shell_c_re's leading anchor omitted
        # `;&|)`, unlike cmd_start's — so a compact one-liner with no space
        # before the shell -c wrapper (an ordinary shape, not obfuscation)
        # wasn't recognized as a -c invocation at all, and its dumper body
        # slipped through unexamined.
        assert_blocked "secret-read denies a compact ; one-liner before bash -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "true;bash -c 'declare -p FAKE_API_KEY'")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies a compact && one-liner before bash -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "true&&bash -c 'declare -p FAKE_API_KEY'")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies a compact | one-liner before bash -c" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "echo x|bash -c 'declare -p FAKE_API_KEY'")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies a dumper in a no-space sibling -c invocation" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "bash -c 'true';bash -c 'declare -p FAKE_API_KEY'")" \
          'lists or shows shell variables'

        assert_allowed "secret-read lets bash -c set -x (xtrace) through after a compact ; separator" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "true;bash -c 'set -x; true'")"

        # Widening shell_c_re's anchor to ;&|) (round 4, above) initially
        # regressed the false-positive side: those characters are as common
        # inside an ordinary quoted regex/string as a bare space already was,
        # e.g. a grep/rg alternation pattern that happens to mention "bash
        # -c" as literal text. shell_c_re now verifies its match sits outside
        # any quoted span before treating it as a real -c wrapper.
        assert_allowed "secret-read lets a quoted alternation mentioning bash -c through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "rg 'foo|bash -c env x' .")"

        assert_blocked "secret-read denies a real sibling -c invocation after a quoted red herring" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "rg 'foo|bash -c bar' ; bash -c 'declare -p FAKE_API_KEY'")" \
          'lists or shows shell variables'

        # pi's grep always prints matching lines, so the adapter forces
        # output_mode=content; without it the guard would read Claude's default
        # (files_with_matches) and abstain on exactly this call.
        assert_blocked "secret-read denies a grep over .env" \
          guards.pi.secret-read-paths deny \
          "$(grep_payload "$repo" '~/.env' 'FOO')" \
          'Grepping '"$HOME"'/.env'

        assert_blocked "secret-read denies a grep whose glob names .env" \
          guards.pi.secret-read-paths deny \
          "$(grep_payload "$repo" 'src' 'FOO' '**/.env')" \
          'Grepping with glob **/.env'

        assert_blocked "secret-read denies a grep whose glob wildcards .env" \
          guards.pi.secret-read-paths deny \
          "$(grep_payload "$repo" 'src' 'FOO' '.env*')" \
          'Grepping with glob .env*'

        assert_blocked "secret-read denies a template glob that also names .env" \
          guards.pi.secret-read-paths deny \
          "$(grep_payload "$repo" 'src' 'FOO' '{.env.example,.env}')" \
          'Grepping with glob {.env.example,.env}'

        assert_allowed "secret-read lets a grep with an .envrc glob through" \
          guards.pi.secret-read-paths abstain \
          "$(grep_payload "$repo" 'src' 'FOO' '.envrc')"

        assert_allowed "secret-read lets a grep with an .env.example glob through" \
          guards.pi.secret-read-paths abstain \
          "$(grep_payload "$repo" 'src' 'FOO' '.env.example')"

        assert_allowed "secret-read lets an ordinary grep through" \
          guards.pi.secret-read-paths abstain \
          "$(grep_payload "$repo" 'src' 'foo')"

        # Probed directly rather than through the router: hookyard records a handler
        # that exits non-zero as `abstain`, the same outcome a guard that declined
        # produces, so only the exit status distinguishes a crash from a clean
        # abstain — and it is visible nowhere else.
        for malformed in 123 '["/etc/passwd"]' '{"a":1}' null; do
          # NOT `out` — that is the derivation's own output path, and clobbering it
          # makes the final `touch $out` fail in a way that looks nothing like this.
          if ! probe=$(read_payload_raw "$HOME" "$malformed" | ${readAdapterExec} 2>&1); then
            fail "read adapter aborted on a non-string path ($malformed)" "$probe"
          fi
          [ -z "$probe" ] || fail "read adapter should stay silent on a non-string path ($malformed)" "$probe"
        done

        if ! probe=$(read_payload_raw "$HOME" 123 | ${secretReadExec} 2>&1); then
          fail "secret-read adapter aborted on a non-string path" "$probe"
        fi
        [ -z "$probe" ] || fail "secret-read adapter should stay silent on a non-string path" "$probe"

        ## psql: `ask` has no channel on pi, so hookyard degrades it to a block
        ## rather than letting the destructive call run unconfirmed.
        assert_blocked "psql degrades ask to a block" \
          guards.pi.psql ask \
          "$(bash_payload "$repo" "psql -c 'DROP TABLE users'")" \
          'Destructive psql command' \
          'Pi has no ask channel, so the call was denied'

        assert_allowed "psql lets a SELECT through" \
          guards.pi.psql allow \
          "$(bash_payload "$repo" "psql -c 'SELECT 1'")"

        # An allow and an abstain both render empty, so assert the guard actually
        # matched rather than silently skipping the call.
        psql_allow=$(bash_payload "$repo" "psql -c 'SELECT 1'" \
          | jq -c '{tool_name: "Bash", tool_input: .tool_input, cwd: .cwd}' \
          | ${psqlGuardExec})
        jq -e '.hookSpecificOutput.permissionDecision == "allow"' <<<"$psql_allow" >/dev/null \
          || fail "psql guard should allow a SELECT, not abstain" "$psql_allow"

        ## tmux-live-server
        assert_blocked "tmux-live-server denies an unsocketed new-session" \
          guards.pi.tmux-live-server deny \
          "$(bash_payload "$repo" 'tmux new-session -d')" \
          'acts on the LIVE tmux server'

        assert_allowed "tmux-live-server lets a private-socket session through" \
          guards.pi.tmux-live-server abstain \
          "$(bash_payload "$repo" 'TMUX_TMPDIR=/tmp/probe tmux -L probe new-session -d')"

        ## public-leak. A fresh cache stands in for `gh api`, which the sandbox
        ## cannot reach; an ask renders as a block on pi.
        mkdir -p "$HOME/.cache/agent-public-leak-guard"
        printf 'owner/secret\n' >"$HOME/.cache/agent-public-leak-guard/private-repos"

        assert_blocked "public-leak asks before a private repo name goes public" \
          guards.pi.public-leak ask \
          "$(bash_payload "$repo" "gh issue create -R someone/public --title t --body 'Filed from owner/secret#8'")" \
          'owner/secret'

        # Split so the fixture token never appears whole in this file.
        tok="ghp_"aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5
        assert_blocked "public-leak asks before a secret goes public" \
          guards.pi.public-leak ask \
          "$(bash_payload "$repo" "gh issue comment 1 -R someone/public --body 'token $tok'")" \
          'secret: github-pat'

        assert_allowed "public-leak lets a post to a private repo through" \
          guards.pi.public-leak abstain \
          "$(bash_payload "$repo" "gh issue create -R owner/secret --title t --body 'Filed from owner/secret#8'")"

        touch $out
  ''

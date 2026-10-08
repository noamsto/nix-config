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
  dispatcher,
}: let
  inherit (import ./guards.nix {inherit pkgs dispatcher;}) manifest dispatcherManifest handlers;

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
          --manifest ${dispatcherManifest} \
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

        ## nix-config#396: the same dumpers, invoked by an absolute or
        ## relative path instead of the bare word.
        assert_blocked "secret-read denies /usr/bin/env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" '/usr/bin/env')" \
          'bare env/printenv'

        assert_blocked "secret-read denies /usr/bin/printenv" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" '/usr/bin/printenv')" \
          'bare env/printenv'

        assert_blocked "secret-read denies a nix store env path" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" '/run/current-system/sw/bin/printenv')" \
          'bare env/printenv'

        assert_blocked "secret-read denies sudo /usr/bin/env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'sudo /usr/bin/env')" \
          'bare env/printenv'

        assert_blocked "secret-read denies /usr/bin/tmux show-environment" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" '/usr/bin/tmux show-environment')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies /usr/bin/systemctl --user show-environment" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" '/usr/bin/systemctl --user show-environment')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies /usr/bin/launchctl getenv" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" '/usr/bin/launchctl getenv FAKE_API_KEY')" \
          'lists or shows shell variables'

        assert_allowed "secret-read lets /usr/bin/env python3 script.py through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" '/usr/bin/env python3 script.py')"

        assert_allowed "secret-read lets /usr/bin/env -i foo through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" '/usr/bin/env -i foo')"

        assert_allowed "secret-read lets ls /usr/bin/env through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'ls /usr/bin/env')"

        assert_allowed "secret-read lets cat /usr/bin/env through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'cat /usr/bin/env')"

        assert_allowed "secret-read lets echo /usr/bin/env through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'echo /usr/bin/env')"

        assert_allowed "secret-read lets ./env-setup.sh through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" './env-setup.sh')"

        ## nix-config#395: the same dumpers, but with a redirect, comment, or a
        ## null-output flag trailing the dumper word instead of ending it cleanly.
        assert_blocked "secret-read denies env before a stderr redirect" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env 2>&1')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env before an output redirect" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env > /tmp/x')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env directly touching a redirect" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env>/tmp/x')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env before a trailing comment" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env # note')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env -0 (still a dump, just NUL-separated)" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env -0')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env -0 piped through tr" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "env -0 | tr '\0' '\n'")" \
          'bare env/printenv'

        assert_blocked "secret-read denies printenv -0" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'printenv -0')" \
          'bare env/printenv'

        assert_blocked "secret-read denies printenv --null" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'printenv --null')" \
          'bare env/printenv'

        ## env with only its own options/assignments and no command prints the
        ## (modified) environment (#414).
        assert_blocked "secret-read denies env -i (no command)" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env -i')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env - (no command)" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env -')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env -- (no command)" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env --')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env -u NAME (no command)" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env -u NAME')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env -uNAME (no command)" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env -uNAME')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env --unset=NAME (no command)" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env --unset=NAME')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env --unset NAME (no command)" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env --unset NAME')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env FOO=1 (no command)" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env FOO=1')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env -i FOO=1 -u BAR (no command)" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env -i FOO=1 -u BAR')" \
          'bare env/printenv'

        assert_blocked "secret-read denies /usr/bin/env -u NAME (no command)" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" '/usr/bin/env -u NAME')" \
          'bare env/printenv'

        assert_blocked "secret-read denies /usr/bin/env -i FOO=1 (no command)" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" '/usr/bin/env -i FOO=1')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env -u NAME before a semicolon sibling" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env -u NAME; ls')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env -u NAME before a pipe" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env -u NAME | cat')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env FOO=1 before &&" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env FOO=1 && ls')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env -i in a subshell" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" '(env -i)')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env -u NAME newline-separated from a sibling" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'env -u NAME\nls')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env -u NAME before a trailing comment" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env -u NAME # note')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env -i before an output redirect" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env -i > /tmp/x')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env FOO=1 before a stderr redirect" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env FOO=1 2>&1')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env -u with a quoted name (no command)" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env -u "NAME"')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env with a non-identifier assignment (no command)" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env a-b=1')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env with a substitution-valued assignment (no command)" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env FOO=$(pwd)')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env -u X inside a command substitution" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo "$(env -u X)"')" \
          'bare env/printenv'

        assert_blocked "secret-read denies /usr/bin/env before a redirect (#396 composition)" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" '/usr/bin/env 2>&1')" \
          'bare env/printenv'

        ## nix-config#412: a dumper word spelled with unquoted backslash escapes,
        ## which bash removes before running it.
        assert_blocked "secret-read denies p\\rintenv" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'p\rintenv')" \
          'bare env/printenv'

        assert_blocked "secret-read denies \\printenv" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" '\printenv')" \
          'bare env/printenv'

        assert_blocked "secret-read denies /usr/bin/p\\rintenv" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" '/usr/bin/p\rintenv')" \
          'bare env/printenv'

        assert_blocked "secret-read denies e\\nv" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'e\nv')" \
          'bare env/printenv'

        assert_blocked "secret-read denies a backslash-newline continuation inside env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'en\\\nv')" \
          'bare env/printenv'

        assert_blocked "secret-read denies echo hi; p\\rintenv" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo hi; p\rintenv')" \
          'bare env/printenv'

        assert_blocked "secret-read denies d\\eclare -p FAKE_API_KEY" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'd\eclare -p FAKE_API_KEY')" \
          'lists or shows shell variables'

        assert_allowed "secret-read lets echo p\\rintenv through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'echo p\rintenv')"

        assert_allowed "secret-read lets envsubst through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'envsubst')"

        assert_allowed "secret-read lets e\\nvsubst < f through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'e\nvsubst < f')"

        assert_allowed "secret-read lets echo 'p\\rintenv' through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "echo 'p\rintenv'")"

        assert_allowed "secret-read lets echo \"p\\rintenv\" through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'echo "p\rintenv"')"

        assert_blocked "secret-read denies export -p before a redirect" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'export -p > f')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies declare -p touching a redirect with no space" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'declare -p>f')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies an absolute-path tmux show-environment touching a redirect with no space" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" '/usr/bin/tmux show-environment>f')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies bare declare -x before a redirect" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'declare -x 2>&1')" \
          'lists or shows shell variables'

        ## Named-fd redirects (`{fd}>&2`, bash >=4.1) end the command exactly
        ## like a numbered fd (`2>&1`) does, but need their own branch since a
        ## brace identifier isn't a digit.
        assert_blocked "secret-read denies env before a named-fd redirect" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'env {fd}>&2')" \
          'bare env/printenv'

        assert_blocked "secret-read denies bare declare -x before a named-fd redirect" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'declare -x {fd}>&2')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies a bare set before a named-fd redirect" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'set {fd}>&2')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies a bare set before a trailing comment" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'set # x')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies fish set -U wrapped in fish -c before a redirect" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "fish -c 'set -U 2>&1'")" \
          'set -x/-gx/-U'

        assert_allowed "secret-read lets env -i foo through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'env -i foo')"

        assert_allowed "secret-read lets env FOO=1 make through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'env FOO=1 make')"

        assert_allowed "secret-read lets env -i bash -c true through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'env -i bash -c true')"

        assert_allowed "secret-read lets env -u HOME ls through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'env -u HOME ls')"

        assert_allowed "secret-read lets env --unset=HOME ls through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'env --unset=HOME ls')"

        assert_allowed "secret-read lets /usr/bin/env -u HOME ls through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" '/usr/bin/env -u HOME ls')"

        assert_allowed "secret-read lets env -i FOO=1 make through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'env -i FOO=1 make')"

        assert_allowed "secret-read lets env FOO=\"a b\" make through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'env FOO="a b" make')"

        assert_allowed "secret-read lets env -- ls through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'env -- ls')"

        assert_allowed "secret-read lets env FOO=\$(pwd) make through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'env FOO=$(pwd) make')"

        assert_allowed "secret-read lets printenv HOME through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'printenv HOME')"

        assert_allowed "secret-read lets printenv HOME with a trailing redirect through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'printenv HOME 2>&1')"

        assert_allowed "secret-read lets echo env > f through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'echo env > f')"

        assert_allowed "secret-read lets make env through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'make env')"

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

        # Round 5 (nix-config#381): cmd_start's anchor omitted `)`, so a bare
        # dumper right behind a case pattern (`*)env;;`) wasn't at command
        # position. The dumper regexes only run on quote-masked text, so a
        # quoted `)env;` (terminator inside the quotes, so the unmasked text
        # would match) still can't trip it.
        assert_blocked "secret-read denies env behind a compact case arm" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "case x in *)env;;esac")" \
          'bare env/printenv'

        assert_blocked "secret-read denies declare -p behind a compact case arm" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "case x in *)declare -p FAKE_API_KEY;;esac")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies env behind a spaced case arm" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "case x in *) env ;; esac")" \
          'bare env/printenv'

        assert_allowed "secret-read lets a quoted )env; through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'echo "a)env;"')"

        assert_allowed "secret-read lets env= behind a case arm through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "case x in a) env=1 true;; esac")"

        # Round 6 (nix-config#391): cmd_start must chain lead words (reserved
        # words, `{`, `!`, env assignments, sudo/exec/time/nice/xargs/command)
        # but only from command position. The allows pin the false-positive
        # surface: a dumper that isn't the command, or that takes arguments.
        assert_blocked "secret-read denies env in a brace group" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "{ env; }")" \
          'bare env/printenv'

        assert_blocked "secret-read denies env in a function body" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "f() { env; }")" \
          'bare env/printenv'

        assert_blocked "secret-read denies env after then" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "if true; then env; fi")" \
          'bare env/printenv'

        assert_blocked "secret-read denies env after do" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "for a in b; do env; done")" \
          'bare env/printenv'

        assert_blocked "secret-read denies negated env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "! env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies env behind an assignment" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "x=1 env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies env behind two assignments" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "x=1 y=2 env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies time env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "time env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies command env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "command env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies sudo env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "sudo env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies sudo -E env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "sudo -E env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies exec env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "exec env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies nice env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "nice env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies nice -n 5 env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "nice -n 5 env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies xargs env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "xargs env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies env behind an assignment and sudo -E" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "x=1 sudo -E env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies declare -p after then" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "if true; then declare -p FAKE_API_KEY; fi")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies env after else" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "if false; then true; else env; fi")" \
          'bare env/printenv'

        assert_blocked "secret-read denies env after elif" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "if false; then true; elif env; then true; fi")" \
          'bare env/printenv'

        assert_blocked "secret-read denies env as a while condition" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "while env; do true; done")" \
          'bare env/printenv'

        assert_blocked "secret-read denies env as an until condition" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "until env; do true; done")" \
          'bare env/printenv'

        assert_blocked "secret-read denies command -p env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "command -p env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies sudo time env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "sudo time env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies a double negated env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "! ! env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies printenv after then" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "if true; then printenv; fi")" \
          'bare env/printenv'

        assert_blocked "secret-read denies xargs -n 1 env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "xargs -n 1 env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies sudo -u root env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "sudo -u root env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies xargs -I {} env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "xargs -I {} env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies nohup env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "nohup env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies declare -p behind builtin" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "builtin declare -p FAKE_API_KEY")" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies doas env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "doas env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies setsid env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "setsid env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies eval env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "eval env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies command -- env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "command -- env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies sudo -a 1 env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "sudo -a 1 env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies sudo -u 0 env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "sudo -u 0 env")" \
          'bare env/printenv'

        assert_blocked "secret-read denies set -S behind sudo -E" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "sudo -E set -S FAKE_API_KEY")" \
          'lists or shows shell variables'

        # Indented bodies: a dumper on its own line after leading whitespace is
        # command position. Built via $'...' for the same reason as the Round 3
        # newline case above.
        assert_blocked "secret-read denies an indented env in a multi-line if body" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'if true; then\n  env\nfi')" \
          'bare env/printenv'

        assert_blocked "secret-read denies a tab-indented env in a multi-line function body" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'f() {\n\tenv\n}')" \
          'bare env/printenv'

        assert_allowed "secret-read lets sudo env with an assignment and command through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "sudo env VAR=x cmd")"

        assert_allowed "secret-read lets xargs env with a command through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "xargs env cmd")"

        assert_allowed "secret-read lets echo then env through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "echo then env")"

        assert_allowed "secret-read lets echo do env through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "echo do env")"

        assert_allowed "secret-read lets command -v env through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "command -v env")"

        assert_allowed "secret-read lets echo sudo env through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "echo sudo env")"

        assert_allowed "secret-read lets echo x=1 env through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "echo x=1 env")"

        assert_allowed "secret-read lets x=1 env=2 true through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "x=1 env=2 true")"

        assert_allowed "secret-read lets sudo -n make env through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "sudo -n make env")"

        assert_allowed "secret-read lets echo and env through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "echo and env")"

        assert_allowed "secret-read lets command -- echo env through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "command -- echo env")"

        assert_allowed "secret-read lets a quoted then env pattern through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "rg 'then env' .")"

        # Command substitution: mask_quotes blanks a whole "..." span, so the
        # body of $(...) or backticks is scanned as a command string of its own.
        # Payloads are single-quoted so the check's own shell never runs them.
        assert_blocked "secret-read denies env in a double-quoted command substitution" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo "$(env)"')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env in a bare command substitution" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo $(env)')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env in backticks" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo `env`')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env in backticks inside double quotes" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo "`env`"')" \
          'bare env/printenv'

        assert_blocked "secret-read denies declare -p in a double-quoted command substitution" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo "$(declare -p FAKE_API_KEY)"')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies env in a nested command substitution" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo "$(echo "$(env)")"')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env in backticks nested in a command substitution" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo "$(echo `env`)"')" \
          'bare env/printenv'

        assert_blocked "secret-read denies a bash -c dumper inside a command substitution" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo "$(bash -c "declare -p FAKE_API_KEY")"')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies an unbalanced command substitution holding env" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo "$(env')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env in a substitution after a quoted-heredoc one" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'printf %s "$(cat <<\'EOF\'\nx\nEOF\n)" && echo "$(env)"')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env in an unquoted-heredoc command substitution" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'cat <<EOF\n$(env)\nEOF')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env in an unquoted heredoc body with an apostrophe" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'cat <<EOF\nIt\'s here: $(env)\nEOF')" \
          'bare env/printenv'

        assert_blocked "secret-read denies a bash -c dumper in backticks with escaped inner quotes" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo "`bash -c \"declare -p FAKE_API_KEY\"`"')" \
          'lists or shows shell variables'

        # Past the verification ceiling the guard denies instead of abstaining.
        many=$(printf '"$(:)" %.0s' $(seq 1 320))
        assert_blocked "secret-read denies a command with too many substitutions to verify" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "echo $many")" \
          'too many substitutions'

        # Each nesting level re-scans its whole body, so the work is quadratic in
        # depth; past the scan budget the guard denies quickly instead of running
        # over the hook's 4s and abstaining.
        nested_subst() {
          local s='echo x' _
          for _ in $(seq 1 "$1"); do s="echo \$($s)"; done
          printf '%s' "$s"
        }
        assert_blocked "secret-read denies a 250-deep command substitution nest" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "$(nested_subst 250)")" \
          'too many substitutions'

        # A quoted heredoc feeding a shell is scanned as code, so its body counts.
        pad=$(printf 'x=1 # pad\n%.0s' $(seq 1 6000))
        assert_blocked "secret-read denies a 60KB code heredoc before a dumper" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "$(printf "bash <<'EOF'\n%s\nenv\nEOF" "$pad")")" \
          'too many substitutions'

        # Many tiny substitutions and a long heredoc-marker line each cost more per
        # byte than their size suggests; both must deny, not overrun.
        assert_blocked "secret-read denies thousands of tiny substitutions" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "echo $(printf '$() %.0s' $(seq 1 5000))")" \
          'too many substitutions'

        assert_blocked "secret-read denies a long heredoc marker line before a dumper" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "cat <<EOF $(printf 'word %.0s' $(seq 1 20000)); env")" \
          'too many substitutions'

        # Each -c match queues the rest of its source string as a new item that is
        # scanned again, so siblings in front of a long tail multiply its cost.
        sibling_tail=$(printf 'word %.0s' $(seq 1 2000))
        assert_blocked "secret-read denies sibling -c invocations before a 10KB tail" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "$(printf "bash -c 'true'; %.0s" $(seq 1 5))$sibling_tail")" \
          'too many substitutions'

        assert_blocked "secret-read denies 20 sibling -c invocations before a 10KB tail" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "$(printf "bash -c 'true'; %.0s" $(seq 1 20))$sibling_tail")" \
          'too many substitutions'

        assert_allowed "secret-read lets 20 short sibling -c invocations through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "$(printf "bash -c 'true'; %.0s" $(seq 1 20))true")"

        msg=$(printf 'commit message line here.\n%.0s' $(seq 1 330))
        assert_allowed "secret-read lets a 9KB heredoc commit message through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" $'printf %s "$(cat <<\'EOF\'\n'"$msg"$'\nEOF\n)"')"

        assert_allowed "secret-read lets a 60-deep command substitution nest through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "$(nested_subst 60)")"

        assert_blocked "secret-read still scans after a heredoc marker inside a quoted string" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'echo "<<\'X\'"\necho "$(env)"')" \
          'bare env/printenv'

        assert_blocked "secret-read still scans after a heredoc marker in a comment" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'echo hi # <<\'X\'\necho "$(env)"')" \
          'bare env/printenv'

        assert_blocked "secret-read still scans past an apostrophe in a comment" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'# what\'s set\nenv')" \
          'bare env/printenv'

        assert_blocked "secret-read still flags declare -p past an apostrophe in a comment" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'# what\'s set\ndeclare -p FAKE_API_KEY')" \
          'lists or shows shell variables'

        assert_blocked "secret-read still scans a substitution on the line after a comment" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'# x\necho "$(env)"')" \
          'bare env/printenv'

        assert_blocked "secret-read still scans after a heredoc marker in a comment behind a substitution" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'echo $(pwd) # <<\'X\'\necho "$(env)"')" \
          'bare env/printenv'

        assert_blocked "secret-read still scans after a heredoc marker in a comment behind backticks" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'echo `pwd` # <<\'X\'\necho "$(env)"')" \
          'bare env/printenv'

        # A `#` in an unquoted heredoc body is text: the substitution on its line
        # still runs, so collect_substs must not skip it as a comment.
        assert_blocked "secret-read treats a hash in an unquoted heredoc body as text" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'cat <<EOF\n# see `env`\nEOF')" \
          'bare env/printenv'

        # An apostrophe in a heredoc body is text, not a quote: it must not open
        # a phantom span that hides the dumper on a later line.
        assert_blocked "secret-read denies env after a quoted heredoc with an apostrophe in its body" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'git commit -F - <<\'EOF\'\nfix: don\'t crash\nEOF\nenv')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env after an unquoted heredoc with an apostrophe in its body" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'cat <<EOF\nfix: don\'t crash\nEOF\nenv')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env after a tab-stripped heredoc with an apostrophe in its body" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'cat <<-EOF\n\tfix: don\'t crash\n\tEOF\nenv')" \
          'bare env/printenv'

        # The dash-mode tab strip must be linear: a body line of many leading
        # tabs used to be stripped one tab at a time (quadratic copy), which
        # overran the hook's time budget and abstained (fail open).
        many_tabs=$(printf '\t%.0s' $(seq 1 60000))
        assert_blocked "secret-read denies env after a <<- heredoc body line with 60000 tabs" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'cat <<-\'EOF\'\n'"$many_tabs"$'\nEOF\nenv')" \
          'bare env/printenv'

        assert_allowed "secret-read lets a <<- heredoc body line with 60000 tabs and no dumper through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" $'cat <<-\'EOF\'\n'"$many_tabs"$'\nEOF')"

        # heredoc_is_code strips leading assignment/keyword tokens off the marker
        # line the same way, one token at a time via BASH_REMATCH reassignment —
        # the same quadratic shape, on the marker line instead of a body line.
        many_assigns=$(printf 'a=1 %.0s' $(seq 1 4090))
        assert_blocked "secret-read denies env after a heredoc marker line with 4090 leading assignments" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "$many_assigns"$'cat <<EOF\nhello\nEOF\nenv')" \
          'bare env/printenv'

        assert_allowed "secret-read lets a heredoc marker line with 4090 leading assignments and no dumper through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "$many_assigns"$'cat <<EOF\nhello\nEOF')"

        assert_blocked "secret-read denies a backticked bash -c dumper in an unquoted heredoc body" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'cat <<EOF\nrun `bash -c "declare -p FAKE_API_KEY"` now\nEOF')" \
          'lists or shows shell variables'

        assert_blocked "secret-read denies a dumper in the body of a heredoc fed to a shell" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'bash <<\'EOF\'\nenv\nEOF')" \
          'bare env/printenv'

        assert_blocked "secret-read denies a dumper in a quoted heredoc piped to a shell" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'cat <<\'EOF\' | sh\necho "it\'s"\nenv\nEOF')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env after an arithmetic shift that is not a heredoc" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'x=$((1<<n))\nenv')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env after a heredoc marker inside a multi-line quoted string" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'echo "a\nb <<EOF\nc"; env')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env after a heredoc whose delimiter is not a plain word" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'cat <<A.B\nx\nA.B\nenv')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env after a heredoc with a backslash delimiter and an apostrophe" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'cat <<\\EOF\nit\'s\nEOF\nenv')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env after a tab-stripped quoted heredoc with an apostrophe" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'cat <<-\'EOF\'\n\tit\'s\n\tEOF\nenv')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env in an unterminated heredoc" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'cat <<EOF\nno terminator\nenv')" \
          'bare env/printenv'

        assert_blocked "secret-read denies a dumper in a heredoc fed to a shell with no space before the marker" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'bash<<\'EOF\'\nenv\nEOF')" \
          'bare env/printenv'

        assert_blocked "secret-read denies a dumper in a heredoc fed to a quoted shell name" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'\"bash\" <<\'EOF\'\nenv\nEOF')" \
          'bare env/printenv'

        assert_blocked "secret-read denies a dumper in a heredoc fed to source /dev/stdin" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'source /dev/stdin <<\'EOF\'\nenv\nEOF')" \
          'bare env/printenv'

        assert_blocked "secret-read denies a dumper in a heredoc fed to ssh" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'ssh host <<EOF\nenv\nEOF')" \
          'bare env/printenv'

        assert_blocked "secret-read denies a dumper in a heredoc piped to a read loop" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'cat <<EOF | while read l; do eval \"$l\"; done\nenv\nEOF')" \
          'bare env/printenv'

        assert_blocked "secret-read denies a dumper in a heredoc inside an eval substitution" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'eval \"$(cat <<EOF\nenv\nEOF\n)\"')" \
          'bare env/printenv'

        assert_blocked "secret-read denies a dumper in a heredoc whose redirection precedes the shell" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'<<EOF bash\nenv\nEOF')" \
          'bare env/printenv'

        assert_blocked "secret-read denies a dumper in a heredoc fed to a shell behind a stdin redirect" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'</dev/null bash <<EOF\nenv\nEOF')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env after a heredoc with a dashed delimiter" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'cat <<EOF-x\nx\nEOF-x\nenv\nEOF')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env after a heredoc with a partly quoted delimiter" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'cat <<\'E\'OF\nx\nEOF\nenv\nE')" \
          'bare env/printenv'

        assert_blocked "secret-read denies a dumper in a heredoc piped to a shell over a continued line" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'cat <<EOF \\\n | bash\nenv\nEOF')" \
          'bare env/printenv'

        assert_blocked "secret-read denies a dumper in a heredoc whose pipeline continues after the terminator" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'cat <<EOF |\nenv\nEOF\nsh')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env after a backslash-escaped heredoc marker" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'echo \\<<A\nenv\nA')" \
          'bare env/printenv'

        assert_blocked "secret-read denies env after an arithmetic shift by a sink-named operand" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'echo $((cat<<A))\nenv\nA')" \
          'bare env/printenv'

        assert_blocked "secret-read denies a dumper in a heredoc fed to git with an alias" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'git -c alias.a=!sh a <<\'EOF\'\nenv\nEOF')" \
          'bare env/printenv'

        assert_blocked "secret-read does not let a false comment start in a quoted string in a substitution hide a trailing dumper" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo "$(printf "Issue #%s" "$n")"; env')" \
          'bare env/printenv'

        assert_blocked "secret-read does not let a backtick span holding a hash hide a trailing dumper" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'echo `date # now`; env')" \
          'bare env/printenv'

        # The dumpers below sit in backticks with escaped inner quotes, which the
        # raw scan cannot see, so only a wrongly-skipped `#` would let them through.
        assert_blocked "secret-read does not treat a mid-word hash as a comment" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo a#"`bash -c \"declare -p FAKE_API_KEY\"`"')" \
          'lists or shows shell variables'

        assert_blocked "secret-read does not treat a hash after a closing paren as a comment" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo $(x)#"`bash -c \"declare -p FAKE_API_KEY\"`"')" \
          'lists or shows shell variables'

        assert_blocked "secret-read does not treat a hash inside an open parameter expansion as a comment" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo ''${x:- #"`bash -c \"declare -p FAKE_API_KEY\"`"}')" \
          'lists or shows shell variables'

        assert_blocked "secret-read does not treat a hash after an escaped space as a comment" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo a\ #"`bash -c \"declare -p FAKE_API_KEY\"`"')" \
          'lists or shows shell variables'

        assert_blocked "secret-read ends a comment at the newline" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'echo hi # x\necho "`bash -c \\"declare -p FAKE_API_KEY\\"`"')" \
          'lists or shows shell variables'

        assert_blocked "secret-read does not treat a hash after a closing backtick as a comment" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo `x`#"`bash -c \"declare -p FAKE_API_KEY\"`"')" \
          'lists or shows shell variables'

        assert_blocked "secret-read does not treat the argument-count parameter as a comment start" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" 'echo $# "`bash -c \"declare -p FAKE_API_KEY\"`"')" \
          'lists or shows shell variables'

        assert_blocked "secret-read skips a comment holding a paren when finding the end of a substitution" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" $'echo "$(true # )\n env)"')" \
          'bare env/printenv'

        # A comment-heavy command once took ~3s, near the hook's 4s budget (an
        # overrun abstains). This is a deny check, not a timing assertion: it
        # only fails if the guard gets slow enough to hit the build's timeout.
        long=$(for n in $(seq 200); do printf '# note %s\necho hi\n' "$n"; done)
        assert_blocked "secret-read still denies after a long run of comment lines" \
          guards.pi.secret-read deny \
          "$(bash_payload "$repo" "$long"$'\n'"echo \"\$(env)\"")" \
          'bare env/printenv'

        assert_allowed "secret-read lets backticked env in a comment through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" $'# use `env` here')"

        assert_allowed "secret-read lets a mid-word hash through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'echo a#b')"

        assert_allowed "secret-read lets an array length expansion through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'echo ''${#arr[@]}')"

        assert_allowed "secret-read lets the argument-count parameter through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'echo "$#"')"

        assert_allowed "secret-read lets a double-quoted hash through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'echo "#"')"

        assert_allowed "secret-read lets a single-quoted hash through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "echo '#'")"

        assert_allowed "secret-read lets a comment holding a paren and a quote inside a substitution through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" $'echo "$(true # a) \\"b\nx)"')"

        assert_allowed "secret-read lets a single-quoted command substitution through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "echo '\$(env)'")"

        assert_allowed "secret-read lets single-quoted backticks through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "echo '\`env\`'")"

        assert_allowed "secret-read lets a quoted env|printenv regex through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "rg 'env|printenv' file")"

        assert_allowed "secret-read lets a quoted string with a stray paren and env through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'echo "a)env;"')"

        assert_allowed "secret-read lets env as an argument beside a command substitution through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'echo "$(pwd) env"')"

        assert_allowed "secret-read lets an unbalanced command substitution without a dumper through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" 'echo "$(pwd')"

        assert_allowed "secret-read lets a single-quoted string with a paren and env inside a substitution through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" "echo \"\$(echo 'x)env')\"")"

        # The commit-message idiom (via printf, so the git-commit guard stays
        # out of it): a quoted heredoc runs no substitution, so
        # backticked prose and apostrophes in its body must not read as one.
        assert_allowed "secret-read lets a quoted-heredoc commit body with backticked env through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" $'printf %s "$(cat <<\'EOF\'\nfix: x\n\nMentions `env` and `set`, don\'t "quote" it.\nenv\nEOF\n)"')"

        assert_allowed "secret-read lets a quoted-heredoc body with a lone paren and backticked env through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" $'printf %s "$(cat <<\'EOF\'\nFix things\n\n1) first item mentions `env` handling\nEOF\n)"')"

        assert_allowed "secret-read lets a quoted-heredoc body with backticked env through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" $'cat > s.sh <<\'EOF\'\nx `env` y\nEOF')"

        # A quoted heredoc body is literal: no substitution runs in it.
        assert_allowed "secret-read lets a quoted heredoc with literal \$(env) and backticked env through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" $'cat <<\'EOF\'\nrun $(env) or `env` here\nEOF')"

        assert_allowed "secret-read lets a double-quoted-delimiter heredoc with literal \$(env) through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" $'cat <<"EOF"\nrun $(env) or `env` here\nEOF')"

        assert_allowed "secret-read lets a heredoc PR body with an apostrophe through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" $'gh pr create --body-file - <<\'EOF\'\nfix: don\'t crash\n\nIt\'s a "quoted" word.\nEOF')"

        assert_allowed "secret-read lets an unquoted heredoc with an apostrophe and no dumper through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" $'cat <<EOF\nfix: don\'t crash\nEOF')"

        assert_allowed "secret-read lets a tab-stripped heredoc with an apostrophe and no dumper through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" $'cat <<-EOF\n\tfix: don\'t crash\n\tEOF')"

        assert_allowed "secret-read lets a bare env line in an unquoted heredoc body through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" $'cat <<EOF\nenv\nEOF')"

        assert_allowed "secret-read lets a bare env line in a quoted heredoc body with an apostrophe through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" $'cat <<\'EOF\'\ndon\'t\nenv\nEOF')"

        assert_allowed "secret-read lets a gh PR body heredoc with an apostrophe and a bare env line through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" $'gh pr create --body-file - <<\'EOF\'\nfix: don\'t\nenv\nEOF')"

        assert_allowed "secret-read lets a heredoc assigned through a substitution with an apostrophe through" \
          guards.pi.secret-read abstain \
          "$(bash_payload "$repo" $'x=$(cat <<\'EOF\'\nfix: don\'t\nEOF\n)')"

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
        ## cannot reach.
        mkdir -p "$HOME/.cache/dispatcher"
        printf 'owner/secret\n' >"$HOME/.cache/dispatcher/private-repos"

        assert_blocked "public-leak denies before a private repo name goes public" \
          dispatcher.public-leak-guard deny \
          "$(bash_payload "$repo" "gh issue create -R someone/public --title t --body 'Filed from owner/secret#8'")" \
          'owner/secret'

        # Split so the fixture token never appears whole in this file.
        tok="ghp_"aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5
        assert_blocked "public-leak denies before a secret goes public" \
          dispatcher.public-leak-guard deny \
          "$(bash_payload "$repo" "gh issue comment 1 -R someone/public --body 'token $tok'")" \
          'secret: github-pat'

        assert_allowed "public-leak lets a post to a private repo through" \
          dispatcher.public-leak-guard abstain \
          "$(bash_payload "$repo" "gh issue create -R owner/secret --title t --body 'Filed from owner/secret#8'")"

        ## git-identity. Both fixtures stay unborn (no commit, nothing staged) so
        ## git-default-branch and git-commit-autostage abstain.
        idrepo=$TMPDIR/idrepo
        idlocal=$TMPDIR/idlocal
        git init -q "$idrepo"
        git -C "$idrepo" remote add origin https://example.invalid/x.git
        git init -q "$idlocal"

        assert_blocked "git-identity denies -c user.email in a repo with a remote" \
          guards.pi.git-identity deny \
          "$(bash_payload "$idrepo" 'git -c user.email=x@y.z commit -m m')" \
          'commit with the configured git identity'

        assert_allowed "git-identity lets -c user.email through in a repo without a remote" \
          guards.pi.git-identity abstain \
          "$(bash_payload "$idlocal" 'git -c user.email=x@y.z commit -m m')"

        assert_allowed "git-identity lets a plain commit through in a repo with a remote" \
          guards.pi.git-identity abstain \
          "$(bash_payload "$idrepo" 'git commit -m m')"

        ## pgrep-self-match
        assert_blocked "pgrep-self-match denies pgrep -f without a bracket class" \
          guards.pi.pgrep-self-match deny \
          "$(bash_payload "$idlocal" 'pgrep -f "bats .*-j 8"')" \
          'matches its own shell'

        assert_allowed "pgrep-self-match lets the bracket trick through" \
          guards.pi.pgrep-self-match abstain \
          "$(bash_payload "$idlocal" "pgrep -f '[b]ats'")"

        assert_allowed "pgrep-self-match lets pgrep -x through" \
          guards.pi.pgrep-self-match abstain \
          "$(bash_payload "$idlocal" 'pgrep -x bats')"

        touch $out
  ''

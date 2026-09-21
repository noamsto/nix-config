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
    nativeBuildInputs = [hookyard pkgs.jq pkgs.git pkgs.gnugrep pkgs.coreutils];
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

    route() {
      hookyard route --registered-for pi --event pre_tool --state-dir "$state"
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

    git -C "$repo" checkout -q -b feat/branch
    # Same working tree, same advisory trigger — but no denial to ride, and pi's
    # pre_tool return shape has no standalone advisory slot (hookyard#72), so
    # this renders nothing at all. That is the accepted delta, asserted.
    assert_allowed "a commit off the default branch runs (advisory alone cannot render)" \
      guards.pi.git-default-branch abstain \
      "$(bash_payload "$repo" 'git commit -m wip')"
    # The accepted hookyard#72 delta, pinned: the advisory guard still runs and
    # still advises — the record says so — but pi's pre_tool return shape has
    # nowhere to put it once no handler denies, so nothing renders. If pi ever
    # grows a standalone advisory slot, this assertion is what will notice.
    assert_outcome "git-commit-autostage still advises, with nowhere to render it" \
      guards.pi.git-commit-autostage advise "$(( $(records) - 1 ))"

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

    touch $out
  ''

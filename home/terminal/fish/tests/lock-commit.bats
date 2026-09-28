#!/usr/bin/env bats
# Regression suite for the lock-commit fish function and the jq lock-diff
# filter it drives. check.nix renders LOCK_COMMIT_FUNCTION exactly as Home
# Manager installs it, so the tested artifact is the installed one.
#
# Run: bats home/terminal/fish/tests/lock-commit.bats
# or:  nix build .#checks.x86_64-linux.lock-commit

bats_require_minimum_version 1.5.0

setup() {
  FUNCTION=${LOCK_COMMIT_FUNCTION:?LOCK_COMMIT_FUNCTION must be set}
  FILTER=${LOCK_COMMIT_FILTER:?LOCK_COMMIT_FILTER must be set}
  FIXTURES="$BATS_TEST_TMPDIR/fixtures"
  mkdir -p "$FIXTURES"
}

jq_filter() { # <old> <new>
  jq -c -f "$FILTER" --slurpfile new "$2" <"$1"
}

field() { # <old> <new> <field>
  jq_filter "$1" "$2" | jq -r --arg f "$3" '.[$f]'
}

new_repo() { # <dir>
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email lock-commit@test.invalid
  git -C "$1" config user.name lock-commit-test
}

run_lock_commit() { # <dir> [extra args]
  run fish -c "cd '$1'; source '$FUNCTION'; lock-commit ${2:-}"
}

# Build a lock with N github inputs named in $names and every node at $rev.
build_lock() { # <rev> <outfile> <name...>
  local rev="$1" out="$2"
  shift 2
  jq -n --arg rev "$rev" --args '
    $ARGS.positional as $names |
    {
      nodes: (reduce $names[] as $n ({}; .[$n] = {locked: {type: "github", owner: "o", repo: "r", rev: $rev, lastModified: 1600000000}})),
      root: "root",
      version: 7
    }
    | .nodes.root = {inputs: (reduce $names[] as $n ({}; .[$n] = $n))}
  ' -- "$@" >"$out"
}

# --- message shape ---

@test "updated github input: subject names it, body has revs/dates and compare URL" {
  cat >"$FIXTURES/old.json" <<'JSON'
{"nodes":{"root":{"inputs":{"nixpkgs":"nixpkgs"}},"nixpkgs":{"locked":{"type":"github","owner":"NixOS","repo":"nixpkgs","rev":"1111111111111111111111111111111111111111","lastModified":1600000000}}},"root":"root","version":7}
JSON
  cat >"$FIXTURES/new.json" <<'JSON'
{"nodes":{"root":{"inputs":{"nixpkgs":"nixpkgs"}},"nixpkgs":{"locked":{"type":"github","owner":"NixOS","repo":"nixpkgs","rev":"2222222222222222222222222222222222222222","lastModified":1700000000}}},"root":"root","version":7}
JSON
  run field "$FIXTURES/old.json" "$FIXTURES/new.json" subject
  [ "$status" -eq 0 ]
  [ "$output" = "chore(deps): update nixpkgs" ]
  run field "$FIXTURES/old.json" "$FIXTURES/new.json" body
  [ "$status" -eq 0 ]
  [ "$output" = "- nixpkgs: 1111111 → 2222222 (2020-09-13 → 2023-11-14)"$'\n'"  https://github.com/NixOS/nixpkgs/compare/1111111111111111111111111111111111111111...2222222222222222222222222222222222222222" ]
}

@test "added input: short ref and date, no compare URL" {
  cat >"$FIXTURES/old.json" <<'JSON'
{"nodes":{"root":{"inputs":{}}},"root":"root","version":7}
JSON
  cat >"$FIXTURES/new.json" <<'JSON'
{"nodes":{"root":{"inputs":{"foo":"foo"}},"foo":{"locked":{"type":"github","owner":"o","repo":"r","rev":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","lastModified":1600000000}}},"root":"root","version":7}
JSON
  run field "$FIXTURES/old.json" "$FIXTURES/new.json" subject
  [ "$output" = "chore(deps): update foo" ]
  run field "$FIXTURES/old.json" "$FIXTURES/new.json" body
  [ "$output" = "- foo: added (aaaaaaa, 2020-09-13)" ]
}

@test "removed input: just the name" {
  cat >"$FIXTURES/old.json" <<'JSON'
{"nodes":{"root":{"inputs":{"foo":"foo"}},"foo":{"locked":{"type":"github","owner":"o","repo":"r","rev":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","lastModified":1600000000}}},"root":"root","version":7}
JSON
  cat >"$FIXTURES/new.json" <<'JSON'
{"nodes":{"root":{"inputs":{}}},"root":"root","version":7}
JSON
  run field "$FIXTURES/old.json" "$FIXTURES/new.json" subject
  [ "$output" = "chore(deps): update foo" ]
  run field "$FIXTURES/old.json" "$FIXTURES/new.json" body
  [ "$output" = "- foo: removed" ]
}

@test "follows inputs (array nodes) are ignored" {
  cat >"$FIXTURES/old.json" <<'JSON'
{"nodes":{"root":{"inputs":{"foo":"foo"}},"foo":{"locked":{"type":"github","owner":"o","repo":"r","rev":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","lastModified":1600000000}}},"root":"root","version":7}
JSON
  cat >"$FIXTURES/new.json" <<'JSON'
{"nodes":{"root":{"inputs":{"foo":"foo","bar":["foo"]}},"foo":{"locked":{"type":"github","owner":"o","repo":"r","rev":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","lastModified":1600000000}}},"root":"root","version":7}
JSON
  run field "$FIXTURES/old.json" "$FIXTURES/new.json" changed
  [ "$output" = "false" ]
}

@test "follows -> direct transition is reported as added" {
  cat >"$FIXTURES/old.json" <<'JSON'
{"nodes":{"root":{"inputs":{"foo":["bar"]}}},"root":"root","version":7}
JSON
  cat >"$FIXTURES/new.json" <<'JSON'
{"nodes":{"root":{"inputs":{"foo":"foo"}},"foo":{"locked":{"type":"github","owner":"o","repo":"r","rev":"2222222222222222222222222222222222222222","lastModified":1700000000}}},"root":"root","version":7}
JSON
  run field "$FIXTURES/old.json" "$FIXTURES/new.json" subject
  [ "$output" = "chore(deps): update foo" ]
  run field "$FIXTURES/old.json" "$FIXTURES/new.json" body
  [ "$output" = "- foo: added (2222222, 2023-11-14)" ]
}

@test "direct -> follows transition is reported as removed" {
  cat >"$FIXTURES/old.json" <<'JSON'
{"nodes":{"root":{"inputs":{"foo":"foo"}},"foo":{"locked":{"type":"github","owner":"o","repo":"r","rev":"1111111111111111111111111111111111111111","lastModified":1600000000}}},"root":"root","version":7}
JSON
  cat >"$FIXTURES/new.json" <<'JSON'
{"nodes":{"root":{"inputs":{"foo":["bar"]}}},"root":"root","version":7}
JSON
  run field "$FIXTURES/old.json" "$FIXTURES/new.json" subject
  [ "$output" = "chore(deps): update foo" ]
  run field "$FIXTURES/old.json" "$FIXTURES/new.json" body
  [ "$output" = "- foo: removed" ]
}

@test "transitive-only change names no direct input" {
  cat >"$FIXTURES/old.json" <<'JSON'
{"nodes":{"root":{"inputs":{"foo":"foo"}},"foo":{"locked":{"type":"github","owner":"o","repo":"r","rev":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","lastModified":1600000000}},"dep":{"locked":{"type":"github","owner":"o","repo":"r","rev":"1111111111111111111111111111111111111111","lastModified":1600000000}}},"root":"root","version":7}
JSON
  cat >"$FIXTURES/new.json" <<'JSON'
{"nodes":{"root":{"inputs":{"foo":"foo"}},"foo":{"locked":{"type":"github","owner":"o","repo":"r","rev":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","lastModified":1600000000}},"dep":{"locked":{"type":"github","owner":"o","repo":"r","rev":"2222222222222222222222222222222222222222","lastModified":1700000000}}},"root":"root","version":7}
JSON
  run field "$FIXTURES/old.json" "$FIXTURES/new.json" subject
  [ "$output" = "chore(deps): update transitive flake inputs" ]
  run field "$FIXTURES/old.json" "$FIXTURES/new.json" body
  [ "$output" = "- 1 transitive inputs changed" ]
}

@test "subject over 72 chars falls back to the count form" {
  build_lock "1111111111111111111111111111111111111111" "$FIXTURES/old.json" \
    input-alpha-00 input-bravo-00 input-charlie-00 input-delta-00 input-echo-00
  build_lock "2222222222222222222222222222222222222222" "$FIXTURES/new.json" \
    input-alpha-00 input-bravo-00 input-charlie-00 input-delta-00 input-echo-00
  run field "$FIXTURES/old.json" "$FIXTURES/new.json" subject
  [ "$status" -eq 0 ]
  [ "$output" = "chore(deps): update 5 flake inputs" ]
}

@test "changed direct inputs are sorted by name in subject and body" {
  cat >"$FIXTURES/old.json" <<'JSON'
{"nodes":{"root":{"inputs":{"zeta":"zeta","alpha":"alpha"}},"zeta":{"locked":{"type":"github","owner":"o","repo":"r","rev":"1111111111111111111111111111111111111111","lastModified":1600000000}},"alpha":{"locked":{"type":"github","owner":"o","repo":"r","rev":"1111111111111111111111111111111111111111","lastModified":1600000000}}},"root":"root","version":7}
JSON
  cat >"$FIXTURES/new.json" <<'JSON'
{"nodes":{"root":{"inputs":{"zeta":"zeta","alpha":"alpha","mid":"mid"}},"zeta":{"locked":{"type":"github","owner":"o","repo":"r","rev":"2222222222222222222222222222222222222222","lastModified":1700000000}},"alpha":{"locked":{"type":"github","owner":"o","repo":"r","rev":"2222222222222222222222222222222222222222","lastModified":1700000000}},"mid":{"locked":{"type":"github","owner":"o","repo":"r","rev":"3333333333333333333333333333333333333333","lastModified":1700000000}}},"root":"root","version":7}
JSON
  run field "$FIXTURES/old.json" "$FIXTURES/new.json" subject
  [ "$output" = "chore(deps): update alpha, mid, zeta" ]
  run field "$FIXTURES/old.json" "$FIXTURES/new.json" body
  [ "${lines[0]}" = "- alpha: 1111111 → 2222222 (2020-09-13 → 2023-11-14)" ]
  [ "${lines[2]}" = "- mid: added (3333333, 2023-11-14)" ]
  [ "${lines[3]}" = "- zeta: 1111111 → 2222222 (2020-09-13 → 2023-11-14)" ]
}

@test "non-github input without a rev falls back to narHash" {
  cat >"$FIXTURES/old.json" <<'JSON'
{"nodes":{"root":{"inputs":{"foo":"foo"}},"foo":{"locked":{"type":"path","narHash":"sha256-AAAAAAAAAAAAAAAAAAAAAA","lastModified":1600000000}}},"root":"root","version":7}
JSON
  cat >"$FIXTURES/new.json" <<'JSON'
{"nodes":{"root":{"inputs":{"foo":"foo"}},"foo":{"locked":{"type":"path","narHash":"sha256-BBBBBBBBBBBBBBBBBBBBBB","lastModified":1700000000}}},"root":"root","version":7}
JSON
  run field "$FIXTURES/old.json" "$FIXTURES/new.json" body
  [ "$output" = "- foo: AAAAAAAAAAAA → BBBBBBBBBBBB (2020-09-13 → 2023-11-14)" ]
}

# --- the installed fish function ---

@test "fish --no-execute accepts the rendered function" {
  run fish --no-execute "$FUNCTION"
  [ "$status" -eq 0 ]
}

@test "no change: exits 1, prints an error, commits nothing" {
  repo="$BATS_TEST_TMPDIR/repo"
  new_repo "$repo"
  cat >"$FIXTURES/lock.json" <<'JSON'
{"nodes":{"root":{"inputs":{"foo":"foo"}},"foo":{"locked":{"type":"github","owner":"o","repo":"r","rev":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","lastModified":1600000000}}},"root":"root","version":7}
JSON
  cp "$FIXTURES/lock.json" "$repo/flake.lock"
  git -C "$repo" add flake.lock
  git -C "$repo" commit -qm init
  before=$(git -C "$repo" rev-parse HEAD)

  run_lock_commit "$repo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no changes"* ]]
  [ "$(git -C "$repo" rev-parse HEAD)" = "$before" ]
  [ -z "$(git -C "$repo" status --porcelain)" ]
}

@test "dry-run prints the message and commits nothing" {
  repo="$BATS_TEST_TMPDIR/repo"
  new_repo "$repo"
  cat >"$FIXTURES/old.json" <<'JSON'
{"nodes":{"root":{"inputs":{"nixpkgs":"nixpkgs"}},"nixpkgs":{"locked":{"type":"github","owner":"NixOS","repo":"nixpkgs","rev":"1111111111111111111111111111111111111111","lastModified":1600000000}}},"root":"root","version":7}
JSON
  cat >"$FIXTURES/new.json" <<'JSON'
{"nodes":{"root":{"inputs":{"nixpkgs":"nixpkgs"}},"nixpkgs":{"locked":{"type":"github","owner":"NixOS","repo":"nixpkgs","rev":"2222222222222222222222222222222222222222","lastModified":1700000000}}},"root":"root","version":7}
JSON
  cp "$FIXTURES/old.json" "$repo/flake.lock"
  git -C "$repo" add flake.lock
  git -C "$repo" commit -qm init
  before=$(git -C "$repo" rev-parse HEAD)
  cp "$FIXTURES/new.json" "$repo/flake.lock"

  run_lock_commit "$repo" "--dry-run"
  [ "$status" -eq 0 ]
  [[ "$output" == *"chore(deps): update nixpkgs"* ]]
  [[ "$output" == *"https://github.com/NixOS/nixpkgs/compare/1111111111111111111111111111111111111111...2222222222222222222222222222222222222222"* ]]
  [ "$(git -C "$repo" rev-parse HEAD)" = "$before" ]
}

@test "dry-run is byte-identical across runs" {
  repo="$BATS_TEST_TMPDIR/repo"
  new_repo "$repo"
  build_lock "1111111111111111111111111111111111111111" "$FIXTURES/old.json" nixpkgs
  build_lock "2222222222222222222222222222222222222222" "$FIXTURES/new.json" nixpkgs
  cp "$FIXTURES/old.json" "$repo/flake.lock"
  git -C "$repo" add flake.lock
  git -C "$repo" commit -qm init
  cp "$FIXTURES/new.json" "$repo/flake.lock"

  first=$(fish -c "cd '$repo'; source '$FUNCTION'; lock-commit --dry-run")
  second=$(fish -c "cd '$repo'; source '$FUNCTION'; lock-commit --dry-run")
  [ "$first" = "$second" ]
  [ -n "$first" ]
}

@test "real run commits only flake.lock and leaves other staged work staged" {
  repo="$BATS_TEST_TMPDIR/repo"
  new_repo "$repo"
  cat >"$FIXTURES/old.json" <<'JSON'
{"nodes":{"root":{"inputs":{"nixpkgs":"nixpkgs"}},"nixpkgs":{"locked":{"type":"github","owner":"NixOS","repo":"nixpkgs","rev":"1111111111111111111111111111111111111111","lastModified":1600000000}}},"root":"root","version":7}
JSON
  cat >"$FIXTURES/new.json" <<'JSON'
{"nodes":{"root":{"inputs":{"nixpkgs":"nixpkgs"}},"nixpkgs":{"locked":{"type":"github","owner":"NixOS","repo":"nixpkgs","rev":"2222222222222222222222222222222222222222","lastModified":1700000000}}},"root":"root","version":7}
JSON
  cp "$FIXTURES/old.json" "$repo/flake.lock"
  printf 'other\n' >"$repo/other.txt"
  git -C "$repo" add flake.lock other.txt
  git -C "$repo" commit -qm init

  cp "$FIXTURES/new.json" "$repo/flake.lock"
  printf 'changed\n' >"$repo/other.txt"
  git -C "$repo" add other.txt

  run_lock_commit "$repo"
  [ "$status" -eq 0 ]
  [ "$(git -C "$repo" show --name-only --format= HEAD)" = "flake.lock" ]
  [ "$(git -C "$repo" show -s --format=%s HEAD)" = "chore(deps): update nixpkgs" ]
  [ "$(git -C "$repo" diff --cached --name-only)" = "other.txt" ]
}

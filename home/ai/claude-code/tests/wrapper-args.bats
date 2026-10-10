#!/usr/bin/env bats
# Regression suite for wrapper-args.sh: the claude wrapper's --settings scan.
# Caller --settings values (both spellings, repeated) become merge layers; args
# after `--` pass through untouched; with no layer the overlay is used as-is.
# Run directly: bats home/ai/claude-code/tests/wrapper-args.bats

bats_require_minimum_version 1.5.0

setup() {
  ARGS_LIB=${ARGS_LIB:-$BATS_TEST_DIRNAME/../wrapper-args.sh}
  # Stub merge: prints "merged:" plus its argv joined with '|', so tests can
  # assert exactly which overlay and layers it received.
  merge="$BATS_TEST_TMPDIR/merge"
  printf '#!%s\n(IFS="|"; echo "merged:$*")\n' "$BASH" >"$merge"
  chmod +x "$merge"
}

# Runs the function in a subshell and prints settings, then one arg per line.
resolve() {
  bash -c '
    source "$1"; shift
    claude_resolve_args /ov "$@"
    echo "settings=$settings"
    printf "arg=%s\n" "${args[@]}"
  ' _ "$ARGS_LIB" "$@"
}

@test "no --settings: overlay passed unchanged, args kept" {
  run resolve "$merge" -p hello
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "settings=/ov" ]
  [ "${lines[1]}" = "arg=-p" ]
  [ "${lines[2]}" = "arg=hello" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "--settings <v>: layer merged and flag stripped" {
  run resolve "$merge" --settings a.json -p x
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "settings=merged:/ov|a.json" ]
  [ "${lines[1]}" = "arg=-p" ]
  [ "${lines[2]}" = "arg=x" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "--settings=<v>: layer merged and flag stripped" {
  run resolve "$merge" --settings=b.json -p x
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "settings=merged:/ov|b.json" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "multiple flags keep order and mix spellings" {
  run resolve "$merge" --settings a.json -p --settings=b.json x --settings c.json
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "settings=merged:/ov|a.json|b.json|c.json" ]
  [ "${lines[1]}" = "arg=-p" ]
  [ "${lines[2]}" = "arg=x" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "-- passes the rest through untouched" {
  run resolve "$merge" --settings a.json -- --settings b.json --settings=c.json
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "settings=merged:/ov|a.json" ]
  [ "${lines[1]}" = "arg=--" ]
  [ "${lines[2]}" = "arg=--settings" ]
  [ "${lines[3]}" = "arg=b.json" ]
  [ "${lines[4]}" = "arg=--settings=c.json" ]
  [ "${#lines[@]}" -eq 5 ]
}

@test "-- alone leaves the overlay unchanged" {
  run resolve "$merge" -- --settings x
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "settings=/ov" ]
  [ "${lines[1]}" = "arg=--" ]
}

@test "--settings without a value exits 2" {
  run --separate-stderr resolve "$merge" -p --settings
  [ "$status" -eq 2 ]
  [[ $stderr == *"--settings needs a value"* ]]
}

@test "merge failure aborts with its status" {
  fail="$BATS_TEST_TMPDIR/fail"
  printf '#!%s\nexit 7\n' "$BASH" >"$fail"
  chmod +x "$fail"
  run resolve "$fail" --settings a.json
  [ "$status" -eq 7 ]
}

#!/usr/bin/env bats
# Regression suite for the secret-commit fish function and the jq sops-diff
# filter it drives. secret-commit-check.nix renders the function exactly as
# Home Manager installs it (SECRET_COMMIT_FUNCTION) and points
# SECRET_COMMIT_FILTER at secret-commit.jq.
#
# The final section runs a real sops round trip on a throwaway age key, so the
# re-encryption behaviour the filter reasons about is exercised, not assumed.
#
# Run a slice:  bats home/terminal/fish/tests/secret-commit.bats --filter filter
# or build it:  nix build .#checks.x86_64-linux.secret-commit

bats_require_minimum_version 1.5.0

setup() {
  FUNCTION=${SECRET_COMMIT_FUNCTION:?SECRET_COMMIT_FUNCTION must be set}
  FILTER=${SECRET_COMMIT_FILTER:?SECRET_COMMIT_FILTER must be set}
  FIXTURES="$BATS_TEST_TMPDIR/fixtures"
  mkdir -p "$FIXTURES"
}

# --- helpers ---

filter() { # <stem> <old.json> <new.json>
  jq -c -f "$FILTER" --arg stem "$1" --slurpfile new "$3" <"$2"
}

field() { # <stem> <old.json> <new.json> <field>
  filter "$1" "$2" "$3" | jq -r --arg f "$4" '.[$f]'
}

new_repo() { # <dir>
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email secret-commit@test.invalid
  git -C "$1" config user.name secret-commit-test
}

run_secret_commit() { # <dir> [extra args]
  run fish -c "cd '$1'; source '$FUNCTION'; secret-commit ${2:-}"
}

commit_all() { # <dir> <message>
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
}

leaf() { # <key> <file> -> the one ENC[...] leaf with that name
  grep -oE "$1: ENC\[[^]]*\]" "$2" | head -1
}

sops_repo() { # <dir>: a git repo with one age-encrypted secrets/app.yaml
  new_repo "$1"
  age-keygen -o "$1/age.key" 2>/dev/null
  local rec
  rec=$(grep -oE 'age1[a-z0-9]+' "$1/age.key" | head -1)
  cat >"$1/.sops.yaml" <<EOF
creation_rules:
  - path_regex: secrets/.*\.yaml
    age: $rec
EOF
  mkdir -p "$1/secrets"
  printf 'greeting: hello\n' >"$1/secrets/app.yaml"
  (cd "$1" && SOPS_AGE_KEY_FILE="$1/age.key" sops -e -i secrets/app.yaml)
  commit_all "$1" init
}

# --- filter: key-path classification ---

@test "filter: added key is named in subject and body" {
  cat >"$FIXTURES/old.json" <<'EOF'
{"a": "ENC[AES256_GCM,data:old]"}
EOF
  cat >"$FIXTURES/new.json" <<'EOF'
{"a": "ENC[AES256_GCM,data:old]", "b": "ENC[AES256_GCM,data:b]"}
EOF
  [ "$(field app "$FIXTURES/old.json" "$FIXTURES/new.json" subject)" = "chore(secrets): app: add b" ]
  [ "$(field app "$FIXTURES/old.json" "$FIXTURES/new.json" changed)" = "true" ]
  [[ "$(field app "$FIXTURES/old.json" "$FIXTURES/new.json" body)" == *"added: b"* ]]
}

@test "filter: removed key is named in subject and body" {
  cat >"$FIXTURES/old.json" <<'EOF'
{"a": "ENC[AES256_GCM,data:a]", "b": "ENC[AES256_GCM,data:b]"}
EOF
  cat >"$FIXTURES/new.json" <<'EOF'
{"a": "ENC[AES256_GCM,data:a]"}
EOF
  [ "$(field app "$FIXTURES/old.json" "$FIXTURES/new.json" subject)" = "chore(secrets): app: remove b" ]
  [[ "$(field app "$FIXTURES/old.json" "$FIXTURES/new.json" body)" == *"removed: b"* ]]
}

@test "filter: nested key path is dotted" {
  cat >"$FIXTURES/old.json" <<'EOF'
{"db": {"host": "ENC[AES256_GCM,data:h]", "port": "ENC[AES256_GCM,data:p]"}}
EOF
  cat >"$FIXTURES/new.json" <<'EOF'
{"db": {"host": "ENC[AES256_GCM,data:h]", "port": "ENC[AES256_GCM,data:p]", "user": "ENC[AES256_GCM,data:u]"}}
EOF
  [ "$(field app "$FIXTURES/old.json" "$FIXTURES/new.json" subject)" = "chore(secrets): app: add db.user" ]
}

@test "filter: new file reports every key as added" {
  cat >"$FIXTURES/old.json" <<'EOF'
{}
EOF
  cat >"$FIXTURES/new.json" <<'EOF'
{"a": "ENC[AES256_GCM,data:a]", "b": "ENC[AES256_GCM,data:b]"}
EOF
  [ "$(field app "$FIXTURES/old.json" "$FIXTURES/new.json" subject)" = "chore(secrets): app: add a, b" ]
}

@test "filter: deleted file reports every key as removed" {
  cat >"$FIXTURES/old.json" <<'EOF'
{"a": "ENC[AES256_GCM,data:a]", "b": "ENC[AES256_GCM,data:b]"}
EOF
  cat >"$FIXTURES/new.json" <<'EOF'
{}
EOF
  [ "$(field app "$FIXTURES/old.json" "$FIXTURES/new.json" subject)" = "chore(secrets): app: remove a, b" ]
}

@test "filter: recipients-only change (same leaves, different sops metadata)" {
  cat >"$FIXTURES/old.json" <<'EOF'
{"a": "ENC[AES256_GCM,data:same]", "sops": {"age": [{"recipient": "age1old"}], "lastmodified": "1"}}
EOF
  cat >"$FIXTURES/new.json" <<'EOF'
{"a": "ENC[AES256_GCM,data:same]", "sops": {"age": [{"recipient": "age1new"}], "lastmodified": "2"}}
EOF
  [ "$(field app "$FIXTURES/old.json" "$FIXTURES/new.json" subject)" = "chore(secrets): app: update recipients" ]
  [[ "$(field app "$FIXTURES/old.json" "$FIXTURES/new.json" body)" == *"recipients updated"* ]]
}

@test "filter: changed value names the key as updated" {
  cat >"$FIXTURES/old.json" <<'EOF'
{"a": "ENC[AES256_GCM,data:one]", "b": "ENC[AES256_GCM,data:stable]", "sops": {"lastmodified": "1"}}
EOF
  cat >"$FIXTURES/new.json" <<'EOF'
{"a": "ENC[AES256_GCM,data:two]", "b": "ENC[AES256_GCM,data:stable]", "sops": {"lastmodified": "2"}}
EOF
  [ "$(field app "$FIXTURES/old.json" "$FIXTURES/new.json" subject)" = "chore(secrets): app: update a" ]
  [[ "$(field app "$FIXTURES/old.json" "$FIXTURES/new.json" body)" == *"updated: a"* ]]
}

@test "filter: add, update and remove combine into one subject" {
  cat >"$FIXTURES/old.json" <<'EOF'
{"keep": "ENC[AES256_GCM,data:1]", "gone": "ENC[AES256_GCM,data:2]", "edit": "ENC[AES256_GCM,data:3]"}
EOF
  cat >"$FIXTURES/new.json" <<'EOF'
{"keep": "ENC[AES256_GCM,data:1]", "add": "ENC[AES256_GCM,data:4]", "edit": "ENC[AES256_GCM,data:5]"}
EOF
  [ "$(field app "$FIXTURES/old.json" "$FIXTURES/new.json" subject)" = "chore(secrets): app: add add; update edit; remove gone" ]
}

@test "filter: sops metadata keys are never reported as key changes" {
  cat >"$FIXTURES/old.json" <<'EOF'
{"sops": {"lastmodified": "1", "mac": "ENC[AES256_GCM,data:old]"}}
EOF
  cat >"$FIXTURES/new.json" <<'EOF'
{"sops": {"lastmodified": "2", "mac": "ENC[AES256_GCM,data:new]"}}
EOF
  subject=$(field app "$FIXTURES/old.json" "$FIXTURES/new.json" subject)
  [ "$subject" = "chore(secrets): app: update recipients" ]
  [[ "$subject" != *"add"* && "$subject" != *"remove"* && "$subject" != *"mac"* ]]
}

@test "filter: unchanged file reports no change" {
  cat >"$FIXTURES/old.json" <<'EOF'
{"a": "ENC[AES256_GCM,data:a]", "sops": {"lastmodified": "1"}}
EOF
  cp "$FIXTURES/old.json" "$FIXTURES/new.json"
  [ "$(field app "$FIXTURES/old.json" "$FIXTURES/new.json" changed)" = "false" ]
}

@test "filter: subject over 72 chars falls back to the count form with the full body" {
  cat >"$FIXTURES/old.json" <<'EOF'
{}
EOF
  cat >"$FIXTURES/new.json" <<'EOF'
{"aaaaaaaaaa": "x", "bbbbbbbbbb": "x", "cccccccccc": "x", "dddddddddd": "x", "eeeeeeeeee": "x"}
EOF
  [ "$(field app "$FIXTURES/old.json" "$FIXTURES/new.json" subject)" = "chore(secrets): app: update 5 keys" ]
  body=$(field app "$FIXTURES/old.json" "$FIXTURES/new.json" body)
  for key in aaaaaaaaaa bbbbbbbbbb cccccccccc dddddddddd eeeeeeeeee; do
    [[ "$body" == *"$key"* ]]
  done
}

# --- function: git plumbing ---

@test "function: rendered body parses under fish --no-execute" {
  run fish --no-execute "$FUNCTION"
  [ "$status" -eq 0 ]
}

@test "function: dry-run prints the plan, commits nothing and touches no index" {
  repo="$BATS_TEST_TMPDIR/dryrun"
  new_repo "$repo"
  mkdir -p "$repo/secrets"
  printf 'a: ENC[AES256_GCM,data:a]\n' >"$repo/secrets/app.yaml"
  commit_all "$repo" init
  printf 'a: ENC[AES256_GCM,data:a]\nb: ENC[AES256_GCM,data:b]\n' >"$repo/secrets/app.yaml"

  run_secret_commit "$repo" -n
  [ "$status" -eq 0 ]
  [[ "$output" == *"chore(secrets): app: add b"* ]]
  [ "$(git -C "$repo" log --oneline | wc -l)" -eq 1 ]
  [ -z "$(git -C "$repo" diff --cached --name-only)" ]
}

@test "function: real run commits the secret alone and leaves other staged work staged" {
  repo="$BATS_TEST_TMPDIR/realdir"
  new_repo "$repo"
  mkdir -p "$repo/secrets"
  printf 'a: ENC[AES256_GCM,data:a]\n' >"$repo/secrets/app.yaml"
  printf 'base\n' >"$repo/other.txt"
  commit_all "$repo" init
  printf 'a: ENC[AES256_GCM,data:a]\nb: ENC[AES256_GCM,data:b]\n' >"$repo/secrets/app.yaml"
  printf 'unrelated\n' >"$repo/unrelated.txt"
  git -C "$repo" add unrelated.txt

  run_secret_commit "$repo"
  [ "$status" -eq 0 ]
  [ "$(git -C "$repo" log -1 --format=%s)" = "chore(secrets): app: add b" ]
  [ "$(git -C "$repo" diff --cached --name-only)" = "unrelated.txt" ]
  ! git -C "$repo" ls-tree -r --name-only HEAD | grep -qx unrelated.txt
}

@test "function: deleted secret is committed as a removal" {
  repo="$BATS_TEST_TMPDIR/delete"
  new_repo "$repo"
  mkdir -p "$repo/secrets"
  printf 'a: ENC[AES256_GCM,data:a]\n' >"$repo/secrets/app.yaml"
  commit_all "$repo" init
  rm "$repo/secrets/app.yaml"

  run_secret_commit "$repo"
  [ "$status" -eq 0 ]
  [ "$(git -C "$repo" log -1 --format=%s)" = "chore(secrets): app: remove a" ]
  ! git -C "$repo" ls-tree -r --name-only HEAD | grep -qx secrets/app.yaml
}

@test "function: untracked new secret is committed" {
  repo="$BATS_TEST_TMPDIR/untracked"
  new_repo "$repo"
  printf 'base\n' >"$repo/base.txt"
  commit_all "$repo" init
  mkdir -p "$repo/secrets"
  printf 'a: ENC[AES256_GCM,data:a]\n' >"$repo/secrets/new.yaml"

  run_secret_commit "$repo"
  [ "$status" -eq 0 ]
  [ "$(git -C "$repo" log -1 --format=%s)" = "chore(secrets): new: add a" ]
  [ "$(git -C "$repo" log --oneline | wc -l)" -eq 2 ]
}

@test "function: no changed secrets exits 1 and commits nothing" {
  repo="$BATS_TEST_TMPDIR/nochange"
  new_repo "$repo"
  mkdir -p "$repo/secrets"
  printf 'a: ENC[AES256_GCM,data:a]\n' >"$repo/secrets/app.yaml"
  commit_all "$repo" init

  run_secret_commit "$repo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"have no changes"* ]]
  [ "$(git -C "$repo" log --oneline | wc -l)" -eq 1 ]
}

@test "function: no secret files exits 1 with a distinct message" {
  repo="$BATS_TEST_TMPDIR/nofiles"
  new_repo "$repo"
  git -C "$repo" commit -q --allow-empty -m init

  run_secret_commit "$repo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no sops secret files found"* ]]
}

@test "function: unparseable present file errors instead of diffing as empty" {
  repo="$BATS_TEST_TMPDIR/badyaml"
  new_repo "$repo"
  mkdir -p "$repo/secrets"
  printf 'a: ENC[AES256_GCM,data:a]\n' >"$repo/secrets/app.yaml"
  commit_all "$repo" init
  printf 'this: [is: not: valid\n' >"$repo/secrets/app.yaml"

  run_secret_commit "$repo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot parse"* ]]
  [ "$(git -C "$repo" log --oneline | wc -l)" -eq 1 ]
}

@test "function: outside a git repository exits 1" {
  tmp="$BATS_TEST_TMPDIR/notrepo"
  mkdir -p "$tmp"
  run fish -c "cd '$tmp'; source '$FUNCTION'; secret-commit"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not inside a git repository"* ]]
}

# --- function: real sops round trip on a throwaway age key ---

@test "sops: adding a key names it and leaves the other leaf alone" {
  repo="$BATS_TEST_TMPDIR/sopsadd"
  sops_repo "$repo"
  (cd "$repo" && SOPS_AGE_KEY_FILE="$repo/age.key" sops set secrets/app.yaml '["token"]' '"abc"')

  run_secret_commit "$repo"
  [ "$status" -eq 0 ]
  [ "$(git -C "$repo" log -1 --format=%s)" = "chore(secrets): app: add token" ]
}

@test "sops: sops set changes one leaf and leaves siblings byte-identical" {
  repo="$BATS_TEST_TMPDIR/sopsedit"
  sops_repo "$repo"
  (cd "$repo" && SOPS_AGE_KEY_FILE="$repo/age.key" sops set secrets/app.yaml '["other"]' '"keep"')
  commit_all "$repo" "add-other"
  before=$(leaf other "$repo/secrets/app.yaml")

  (cd "$repo" && SOPS_AGE_KEY_FILE="$repo/age.key" sops set secrets/app.yaml '["greeting"]' '"changed"')
  after=$(leaf other "$repo/secrets/app.yaml")

  [ "$before" = "$after" ]
  run_secret_commit "$repo"
  [ "$status" -eq 0 ]
  [ "$(git -C "$repo" log -1 --format=%s)" = "chore(secrets): app: update greeting" ]
}

@test "sops: sops edit changes only the edited leaf and is named" {
  repo="$BATS_TEST_TMPDIR/sopsedit2"
  sops_repo "$repo"
  (cd "$repo" && SOPS_AGE_KEY_FILE="$repo/age.key" sops set secrets/app.yaml '["other"]' '"keep"')
  commit_all "$repo" "add-other"
  before_other=$(leaf other "$repo/secrets/app.yaml")
  before_greeting=$(leaf greeting "$repo/secrets/app.yaml")

  # The sandbox has no /usr/bin/env, so the shebang points at the build's bash.
  {
    printf '#!%s\n' "$(command -v bash)"
    cat <<'EOF'
printf 'greeting: changed\nother: keep\n' > "$1"
EOF
  } >"$repo/editor.sh"
  chmod +x "$repo/editor.sh"
  (cd "$repo" && EDITOR="$repo/editor.sh" SOPS_AGE_KEY_FILE="$repo/age.key" sops edit secrets/app.yaml)

  [ "$(leaf other "$repo/secrets/app.yaml")" = "$before_other" ]
  [ "$(leaf greeting "$repo/secrets/app.yaml")" != "$before_greeting" ]
  run_secret_commit "$repo"
  [ "$status" -eq 0 ]
  [ "$(git -C "$repo" log -1 --format=%s)" = "chore(secrets): app: update greeting" ]
}

@test "sops: updatekeys leaves the leaves and reads as a recipients change" {
  repo="$BATS_TEST_TMPDIR/sopskeys"
  sops_repo "$repo"
  age-keygen -o "$repo/extra.key" 2>/dev/null
  rec1=$(grep -oE 'age1[a-z0-9]+' "$repo/age.key" | head -1)
  rec2=$(grep -oE 'age1[a-z0-9]+' "$repo/extra.key" | head -1)
  cat >"$repo/.sops.yaml" <<EOF
creation_rules:
  - path_regex: secrets/.*\.yaml
    age: $rec1,$rec2
EOF
  before=$(leaf greeting "$repo/secrets/app.yaml")
  (cd "$repo" && echo y | SOPS_AGE_KEY_FILE="$repo/age.key" sops updatekeys secrets/app.yaml)
  after=$(leaf greeting "$repo/secrets/app.yaml")

  [ "$before" = "$after" ]
  run_secret_commit "$repo"
  [ "$status" -eq 0 ]
  [ "$(git -C "$repo" log -1 --format=%s)" = "chore(secrets): app: update recipients" ]
}

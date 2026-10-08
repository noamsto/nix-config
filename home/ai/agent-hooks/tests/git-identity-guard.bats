#!/usr/bin/env bats
# Regression suite for git-identity-guard.sh, run directly (no PreToolUse
# harness). Run: bats home/ai/agent-hooks/tests/git-identity-guard.bats
# or: nix build .#checks.x86_64-linux.agent-hooks

bats_require_minimum_version 1.5.0

REASON='commit with the configured git identity; never set user.name/user.email, --author or GIT_AUTHOR_*/GIT_COMMITTER_* in a repo with a remote'

setup_file() {
  # Hermetic: no host identity, hooks or includes can leak into the fixtures.
  export GIT_CONFIG_GLOBAL=$BATS_FILE_TMPDIR/gitconfig
  export GIT_CONFIG_NOSYSTEM=1
  : >"$GIT_CONFIG_GLOBAL"

  mkdir -p "$BATS_FILE_TMPDIR/remote_repo" "$BATS_FILE_TMPDIR/local_repo" "$BATS_FILE_TMPDIR/norepo"
  git init -q "$BATS_FILE_TMPDIR/remote_repo"
  git -C "$BATS_FILE_TMPDIR/remote_repo" remote add origin https://example.invalid/x.git
  git init -q "$BATS_FILE_TMPDIR/local_repo"
}

setup() {
  export GIT_CONFIG_GLOBAL=$BATS_FILE_TMPDIR/gitconfig
  export GIT_CONFIG_NOSYSTEM=1
  GUARD=${GUARD:-$BATS_TEST_DIRNAME/../git-identity-guard.sh}
  REMOTE=$BATS_FILE_TMPDIR/remote_repo
  LOCAL=$BATS_FILE_TMPDIR/local_repo
  NOREPO=$BATS_FILE_TMPDIR/norepo
}

_feed() {
  printf '%s' "$1" | bash "$GUARD"
}

# guard_bash <command> [cwd]
guard_bash() {
  local json
  json=$(jq -n --arg c "$1" --arg d "${2:-}" \
    '{tool_name:"Bash",tool_input:{command:$c}} + (if $d != "" then {cwd:$d} else {} end)')
  run --separate-stderr _feed "$json"
}

guard_json() {
  run --separate-stderr _feed "$1"
}

assert_deny() {
  [ "$status" -eq 0 ]
  jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$output" >/dev/null || {
    echo "$output"
    return 1
  }
}

assert_allow() {
  [ "$status" -eq 0 ]
  [ -z "$output" ] || {
    echo "$output"
    return 1
  }
}

# Forms whose target comes from cwd; denied in remote_repo, allowed in local_repo.
CWD_FORMS=(
  'git -c user.email=a@b.c -c user.name=X commit -m m'
  'git -c user.name=X commit -m m'
  'git -c User.Email=a@b.c commit -m m'
  'git --config-env=user.name=N commit -m m'
  "git commit --author='X <a@b.c>' -m m"
  "git commit --author 'X <a@b.c>' -m m"
  'GIT_AUTHOR_NAME=X git commit -m m'
  'export GIT_COMMITTER_EMAIL=a@b.c && git commit -m m'
  'env GIT_AUTHOR_EMAIL=a@b.c git commit -m m'
  'git config user.name X'
  'git config --local user.email a@b.c'
  'git config --worktree user.name X'
  'git config set user.name X'
  'git -c author.email=a@b -c committer.email=a@b commit -m m'
  'git config author.email a@b'
  'GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=X git commit -m m'
  'GIT_CONFIG_PARAMETERS="'"'"'user.name=X'"'"'" git commit -m m'
  $'git \\\n  -c user.name=X commit -m m'
  $'git commit -m m \\\n  --author="X <a@b>"'
  'git commit -m "a; b" --author=X'
  'git commit -m "fix a|b" -c user.name=X'
)

# --- deny in a repo with a remote ---

@test "deny in remote_repo: every identity form" {
  local c
  for c in "${CWD_FORMS[@]}"; do
    guard_bash "$c" "$REMOTE"
    assert_deny || {
      echo "not denied: $c"
      return 1
    }
  done
}

@test "deny: -C pins the remote repo, cwd is a non-repo dir" {
  guard_bash "git -C $REMOTE -c user.name=X commit -m m" "$NOREPO"
  assert_deny
}

@test "deny: -C pins the remote repo even when cwd is local_repo" {
  guard_bash "git -C $REMOTE -c user.name=X commit -m m" "$LOCAL"
  assert_deny
}

@test "deny: cd into the remote repo from local_repo" {
  guard_bash "cd $REMOTE && git commit --author='X <a@b.c>' -m m" "$LOCAL"
  assert_deny
}

@test "deny: -C after -c, cwd local_repo" {
  guard_bash "git -c user.name=X -C $REMOTE commit -m m" "$LOCAL"
  assert_deny
}

@test "deny: any trigger with cwd a non-repo dir (fail closed)" {
  guard_bash 'git -c user.name=X commit -m m' "$NOREPO"
  assert_deny
}

@test "deny: one safe target does not excuse a remote target" {
  guard_bash "git -C $LOCAL status && git -C $REMOTE -c user.name=X commit -m m" "$LOCAL"
  assert_deny
}

@test "deny: repo created within the command is unresolvable" {
  guard_bash "mkdir $NOREPO/new && cd $NOREPO/new && git init && git -c user.name=T commit -m m" "$NOREPO"
  assert_deny
}

@test "deny: a safe -C segment does not excuse a later cwd segment" {
  guard_bash "git -C $LOCAL log && git -c user.name=X commit -m m" "$REMOTE"
  assert_deny
}

@test "deny: subshell cd into the remote repo from local_repo" {
  guard_bash "(cd $REMOTE && git -c user.name=X commit -m m)" "$LOCAL"
  assert_deny
}

@test "deny: pushd into the remote repo from local_repo" {
  guard_bash "pushd $REMOTE && git -c user.name=X commit -m m" "$LOCAL"
  assert_deny
}

@test "deny: --git-dir pins the remote repo, cwd local_repo" {
  guard_bash "git --git-dir=$REMOTE/.git -c user.name=X commit -m m" "$LOCAL"
  assert_deny
}

@test "deny: GIT_DIR pins the remote repo, cwd local_repo" {
  guard_bash "GIT_DIR=$REMOTE/.git git -c user.name=X commit -m m" "$LOCAL"
  assert_deny
}

@test "deny: scoped cd does not move the cwd for a later git segment" {
  guard_bash "(cd $LOCAL && true) && git -c user.name=X commit -m m" "$REMOTE"
  assert_deny
}

@test "deny: popd undoes an earlier pushd" {
  guard_bash "pushd $LOCAL; popd; git -c user.name=X commit -m m" "$REMOTE"
  assert_deny
}

@test "deny: cd inside quoted text does not move the cwd" {
  guard_bash "echo 'try cd $LOCAL'; git -c user.name=X commit -m m" "$REMOTE"
  assert_deny
}

@test "deny: -C and --git-dir are both targets" {
  guard_bash "git -C $LOCAL --git-dir=$REMOTE/.git -c user.name=X commit -m m" "$LOCAL"
  assert_deny
}

@test "deny: GIT_DIR and -C are both targets" {
  guard_bash "GIT_DIR=$REMOTE/.git git -C $LOCAL -c user.name=X commit -m m" "$LOCAL"
  assert_deny
}

@test "deny: exported GIT_DIR from an earlier segment is a target" {
  guard_bash "export GIT_DIR=$REMOTE/.git; git -c user.name=X commit -m m" "$LOCAL"
  assert_deny
}

@test "deny: --global/--system identity writes in any repo" {
  local c repo
  for repo in "$REMOTE" "$LOCAL"; do
    for c in \
      'git config --global user.name X' \
      'git config --system user.email a@b' \
      'git config --global committer.name X'; do
      guard_bash "$c" "$repo"
      assert_deny || {
        echo "not denied: $c in $repo"
        return 1
      }
    done
  done
}

@test "deny: --global write is caught when another override matches first" {
  local c
  for c in \
    'git -c user.name=X log; git config --global user.name Evil' \
    'git config user.name A; git config --global user.name Evil' \
    'GIT_AUTHOR_NAME=x true; git config --global user.name Evil'; do
    guard_bash "$c" "$LOCAL"
    assert_deny || {
      echo "not denied: $c"
      return 1
    }
  done
}

@test "deny: --file/-f identity writes in any repo" {
  local c
  for c in \
    'git config --file ~/.gitconfig user.name Evil' \
    'git config -f "$HOME/.config/git/config" user.email evil@x'; do
    guard_bash "$c" "$LOCAL"
    assert_deny || {
      echo "not denied: $c"
      return 1
    }
  done
}

@test "allow: --file/-f identity read" {
  guard_bash 'git config -f ~/.gitconfig user.name' "$REMOTE"
  assert_allow
}

@test "deny: cwd stays a target when a cd is scoped, quoted or in bash -c" {
  local c
  for c in \
    "( true; cd $LOCAL ); git -c user.name=X commit -m m" \
    "echo 'a; cd $LOCAL'; git -c user.name=X commit -m m" \
    "bash -c 'true; cd $LOCAL'; git -c user.name=X commit -m m" \
    $'(\ncd '"$LOCAL"$'\n)\ngit -c user.name=X commit -m m'; do
    guard_bash "$c" "$REMOTE"
    assert_deny || {
      echo "not denied: $c"
      return 1
    }
  done
}

@test "deny: cd/pushd/popd sequences keep every dir a target" {
  local c
  for c in \
    "cd $REMOTE; pushd $LOCAL; popd; git -c user.name=X commit -m m" \
    "pushd $REMOTE; pushd $LOCAL; popd; git -c user.name=X commit -m m"; do
    guard_bash "$c" "$LOCAL"
    assert_deny || {
      echo "not denied: $c"
      return 1
    }
  done
}

@test "deny output carries the exact reason" {
  guard_bash 'git -c user.name=X commit -m m' "$REMOTE"
  assert_deny
  [ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$output")" = "$REASON" ]
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$output")" = PreToolUse ]
}

# --- allow in a repo without a remote ---

@test "allow in local_repo: every identity form" {
  local c
  for c in "${CWD_FORMS[@]}"; do
    guard_bash "$c" "$LOCAL"
    assert_allow || {
      echo "not allowed: $c"
      return 1
    }
  done
}

@test "allow: -C pins the local repo, cwd is remote_repo" {
  guard_bash "git -C $LOCAL -c user.name=X commit -m m" "$REMOTE"
  assert_allow
}

@test "allow: cd into local_repo from remote_repo (scratch repo)" {
  guard_bash "cd $LOCAL && git -c user.name=X commit -m m" "$REMOTE"
  assert_allow
}

# --- allow in a repo with a remote: reads and ordinary use ---

@test "allow in remote_repo: ordinary and read-only commands" {
  local c
  for c in \
    'git commit -m m' \
    'git log --format=%an' \
    'git config user.name' \
    'git config author.email' \
    'git config --get user.email' \
    'git config get user.name' \
    'git config --global user.name' \
    'git config --global --get user.email' \
    'git config --unset user.name' \
    'git config user.name 2>/dev/null' \
    'git config user.email >/tmp/x' \
    'echo "$GIT_AUTHOR_NAME"'; do
    guard_bash "$c" "$REMOTE"
    assert_allow || {
      echo "not allowed: $c"
      return 1
    }
  done
}

@test "allow: non-Bash tool" {
  guard_json "$(jq -n --arg d "$REMOTE" '{tool_name:"Read",tool_input:{command:"git -c user.name=X commit"},cwd:$d}')"
  assert_allow
}

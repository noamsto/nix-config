#!/usr/bin/env bash
# SessionStart hook: suggest enabling repo-relevant Claude Code plugins.
#
# Suppression hierarchy:
#   1. ~/.claude/.skill-suggester-off        — global disable
#   2. <repo>/.claude/.skills-acked (empty)  — repo disable
#   3. <repo>/.claude/.skills-acked (lines)  — per-plugin disable

set -euo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

[ -e "$HOME/.claude/.skill-suggester-off" ] && exit 0

input=$(cat || true)
cwd=$(jq -r '.cwd // empty' 2>/dev/null <<<"$input" || true)
cwd=${cwd:-$PWD}

repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0

acked_file="$repo_root/.claude/.skills-acked"
if [ -f "$acked_file" ] && [ ! -s "$acked_file" ]; then
  exit 0
fi

is_acked() {
  [ -f "$acked_file" ] && grep -qxF "$1" "$acked_file"
}

project_settings="$repo_root/.claude/settings.json"
global_settings="$HOME/.claude/settings.json"

is_enabled() {
  local plugin=$1 val=""
  if [ -f "$project_settings" ]; then
    val=$(jq -r --arg p "$plugin" '.enabledPlugins[$p] // empty' "$project_settings" 2>/dev/null) || val=""
    if [ -n "$val" ]; then
      [ "$val" = "true" ]
      return
    fi
  fi
  val=$(jq -r --arg p "$plugin" '.enabledPlugins[$p] // empty' "$global_settings" 2>/dev/null) || val=""
  [ "$val" = "true" ]
}

suggestions=()
suggest() {
  local plugin=$1 reason=$2
  is_acked "$plugin" && return 0
  is_enabled "$plugin" && return 0
  suggestions+=("$plugin — $reason")
}

# Go projects
if [ -f "$repo_root/go.mod" ]; then
  suggest "cc-skills-golang@samber" "Go project (go.mod)"
fi

# Postgres
pg_reason=""
for dir in migrations db/migrations; do
  if [ -d "$repo_root/$dir" ]; then
    sql_found=$(find "$repo_root/$dir" -maxdepth 2 -name '*.sql' -print -quit 2>/dev/null || true)
    if [ -n "$sql_found" ]; then
      pg_reason="$dir/*.sql present"
      break
    fi
  fi
done
[ -n "$pg_reason" ] && suggest "pg@aiguide" "$pg_reason"

[ ${#suggestions[@]} -eq 0 ] && exit 0

repo_name=$(basename "$repo_root")
body="Skill suggestions for ${repo_name}:"
for s in "${suggestions[@]}"; do
  body="${body}"$'\n  • '"${s}"
done
body="${body}"$'\n\nEnable per-repo: add the plugin to .claude/settings.json enabledPlugins.'
body="${body}"$'\nSuppress this repo: touch .claude/.skills-acked (empty=all, or one plugin per line).'
body="${body}"$'\nDisable globally: touch ~/.claude/.skill-suggester-off'

jq -nc --arg ctx "$body" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'

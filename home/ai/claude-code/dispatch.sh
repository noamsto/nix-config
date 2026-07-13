# shellcheck shell=bash
# dispatch — scaffold a worker: issue/ticket -> worktree -> task file -> baked agent.
# Native PATH tool (was a fish autoload function). Crew id is delivered
# explicitly (--crew-id > $CREW_ID > error); a binary can't export env back to
# its caller, so the old `set -gx CREW_ID` persistence trick is gone.
# The shebang + `set -euo pipefail` are prepended by writeShellApplication, so
# this file is only the function body (see crew.sh for the same pattern).

usage() {
  echo "usage: dispatch <trivial|standard|deep> <model> --effort <low|medium|high|xhigh> [--agent claude|codex] [--mcp <profile>] [--crew-id <id>] [LINEAR-ID] <title...>" >&2
}

tier="${1:-}"
model="${2:-}"
case "$tier" in
trivial | standard | deep) ;;
*)
  usage
  exit 1
  ;;
esac
[ -n "$model" ] || {
  usage
  exit 1
}
shift 2

# Leading options before the free-form title, order-independent. LINEAR-ID is
# detected by shape so the bare <title...> form still works.
agent=claude
effort=""
linear_id=""
mcp_profile=""
crew_id_flag=""
while [ $# -gt 0 ]; do
  case "$1" in
  --agent)
    agent="${2:-}"
    case "$agent" in
    claude | codex) ;;
    *)
      echo "dispatch: --agent must be claude or codex" >&2
      exit 1
      ;;
    esac
    shift 2
    ;;
  --effort)
    effort="${2:-}"
    case "$effort" in
    low | medium | high | xhigh) ;;
    *)
      echo "dispatch: --effort must be low, medium, high, or xhigh" >&2
      exit 1
      ;;
    esac
    shift 2
    ;;
  --mcp)
    mcp_profile="${2:-}"
    [ -n "$mcp_profile" ] || {
      echo "dispatch: --mcp needs a profile (analytics)" >&2
      exit 1
    }
    shift 2
    ;;
  --crew-id)
    crew_id_flag="${2:-}"
    [ -n "$crew_id_flag" ] || {
      echo "dispatch: --crew-id needs a value" >&2
      exit 1
    }
    shift 2
    ;;
  *)
    if printf '%s' "$1" | grep -Eq '^[A-Z]{2,}-[0-9]+$'; then
      linear_id="$1"
      shift
    else
      break
    fi
    ;;
  esac
done

[ -n "$effort" ] || {
  echo "dispatch: --effort is required and must be judged independently from tier" >&2
  exit 1
}

# Crew id: explicit flag > inherited env > error. Launcher dispatchers inherit
# $CREW_ID from the claude process env; in-session dispatchers pass --crew-id.
crew_id="${crew_id_flag:-${CREW_ID:-}}"
[ -n "$crew_id" ] || {
  # shellcheck disable=SC2016  # $CREW_ID is documentation text, not an expansion
  echo 'dispatch: no crew id — pass --crew-id <id> (in-session) or run under a launcher/registered dispatcher ($CREW_ID)' >&2
  exit 1
}

# Work-only engine gate. $DISPATCH_PROFILE is set from osConfig.profile by
# home-manager (was a source-baked literal in the fish heredoc). Reject before
# scaffolding a worktree, so the failure is a clear message not a later
# `codex: command not found`.
profile="${DISPATCH_PROFILE:-personal}"
if [ "$agent" = codex ] && [ "$profile" != work ]; then
  echo "dispatch: --agent codex is work-profile only (no personal codex account)" >&2
  exit 1
fi
if [ "$agent" = codex ] && [ -n "$mcp_profile" ]; then
  echo "dispatch: --mcp is claude-only; codex base MCP comes from --profile worker" >&2
  exit 1
fi

# Map an additive --mcp profile to its generated config (claude-only).
mcp_flag=""
if [ -n "$mcp_profile" ]; then
  case "$mcp_profile" in
  analytics) mcp_file="$HOME/.config/claude-code/mcp-posthog.json" ;;
  *)
    echo "dispatch: unknown --mcp profile '$mcp_profile' (valid: analytics)" >&2
    exit 1
    ;;
  esac
  [ -f "$mcp_file" ] || {
    echo "dispatch: --mcp $mcp_profile config not found at $mcp_file" >&2
    exit 1
  }
  mcp_flag="--mcp-config $mcp_file"
fi

title="$*"
[ -n "$title" ] || {
  usage
  exit 1
}

# slug: lowercase, non-alnum -> single dash, first 40 chars, strip edge dashes.
slug=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | cut -c1-40 | sed -E 's/^-+//; s/-+$//')

# Identity + closes line. Linear mode derives both from the ticket (no gh).
# GitHub mode mints an issue and aborts cleanly if that fails (issues disabled)
# rather than scaffolding a half-broken worker off an empty number.
if [ -n "$linear_id" ]; then
  branch="$(printf '%s' "$linear_id" | tr '[:upper:]' '[:lower:]')-$slug"
  closes="Closes $linear_id"
else
  url=$(gh issue create --assignee @me --title "$title" --body "Dispatched worker task." 2>/dev/null || true)
  num=$(printf '%s' "$url" | sed -nE 's#.*/([0-9]+)$#\1#p')
  [ -n "$num" ] || {
    echo "dispatch: could not create a GitHub issue (issues disabled?). Pass a Linear id, e.g. dispatch $tier $model ENG-1234 $title" >&2
    exit 1
  }
  branch="feat/$num-$slug"
  closes="Closes #$num"
fi

# Branch path must match worktrunk's {{ repo_path }}-worktrees/{{ branch |
# sanitize }} template (slash -> dash) — wt won't tell us where it put it.
sanitized="${branch//\//-}"
wt_path="$(git rev-parse --show-toplevel)-worktrees/$sanitized"

# post-switch tmux hook is disabled under CLAUDECODE, so wt only creates the
# worktree here — we drive tmux ourselves below.
wt switch -c "$branch" -y

crew_dir="$(git rev-parse --path-format=absolute --git-common-dir)/crew"
mkdir -p "$crew_dir"

# Log the dispatch decision to the crew bus for later `crew report`.
dispatch_shape="${DISPATCH_SHAPE:-}"
jq -nc --arg crew "$crew_id" --arg branch "$branch" \
  --arg engine "$agent" --arg model "$model" --arg tier "$tier" --arg effort "$effort" \
  --arg shape "$dispatch_shape" \
  '{ts:(now*1000|floor), crew_id:$crew, kind:"dispatch", branch:$branch, engine:$engine, model:$model, tier:$tier, effort:$effort, shape:$shape}' \
  >>"$crew_dir/events.jsonl"

# FleetView-style codename+color, derived from the branch (deterministic).
ident=$(crew identity "$branch")
agent_name=$(printf '%s' "$ident" | jq -r .name)
agent_color=$(printf '%s' "$ident" | jq -r .tmux)

# Stamp the task file: header fields the worker protocol reads, the closes
# line, and the full task body from $DISPATCH_SPEC (falls back to the title).
{
  printf 'tier: %s\neffort: %s\ntitle: %s\n%s\ndispatcher_pane: %s\ncrew_dir: %s\ncrew_id: %s\nagent_name: %s\n' \
    "$tier" "$effort" "$title" "$closes" "${TMUX_PANE:-}" "$crew_dir" "$crew_id" "$agent_name"
  if [ -n "${DISPATCH_SPEC:-}" ] && [ -f "${DISPATCH_SPEC:-}" ]; then
    printf '\n## Task\n\n'
    cat "$DISPATCH_SPEC"
  fi
} >"$wt_path/WORKER_TASK.md"

read -r win pane < <(tmux new-window -d -c "$wt_path" -n "$sanitized" -P -F '#{window_id} #{pane_id}')

# Identity surfaces: codename on the pane border + the CC prompt box (--name).
# lazytmux owns the tab text; @crew_* tint the status-bar tab.
tmux set-window-option -t "$win" @crew_name "$agent_name"
tmux set-window-option -t "$win" @crew_color "$agent_color"
tmux set-window-option -t "$win" pane-border-style "bg=#{@thm_bg},fg=$agent_color"
tmux set-window-option -t "$win" pane-active-border-style "bg=#{@thm_bg},fg=$agent_color,bold"
tmux set-window-option -t "$win" pane-border-format " #[bold]#{@crew_name}#[nobold] "

# Deep claude workers get the read-only codex MCP for cross-model review
# (work profile only — mcp-codex.json is generated work-gated).
xreview_mcp=""
if [ "$profile" = work ] && [ "$agent" = claude ] && [ "$tier" = deep ]; then
  xreview_mcp="--mcp-config $HOME/.config/claude-code/mcp-codex.json"
fi

if [ "$agent" = codex ]; then
  tmux send-keys -t "$pane" \
    "codex --profile worker -m $model -c model_reasoning_effort=$effort --dangerously-bypass-approvals-and-sandbox 'Read ~/nix-config/home/ai/claude-code/WORKER_PROTOCOL.md and WORKER_TASK.md, then run the task end-to-end. Push when pre-push passes; open a PR.'" Enter
else
  tmux send-keys -t "$pane" \
    "claude --name $agent_name --model $model --effort $effort $mcp_flag $xreview_mcp --append-system-prompt-file ~/nix-config/home/ai/claude-code/WORKER_PROTOCOL.md --permission-mode auto 'Read WORKER_TASK.md and run it end-to-end. Push when pre-push passes; open a PR.'" Enter
fi

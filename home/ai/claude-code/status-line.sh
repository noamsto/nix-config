#!/usr/bin/env bash

input=$(cat)
if [[ -z $input ]] || ! echo "$input" | jq empty 2>/dev/null; then
  echo "Claude Code"
  exit 0
fi

model='' model_id='' proj_dir='' ctx_size=0 ctx_pct=0 ctx_used_exact=0 r5_pct='' r5_reset='' r7_pct='' r7_reset='' effort=''
eval "$(echo "$input" | jq -r '
  @sh "model=\(.model.display_name // "Unknown")",
  @sh "model_id=\(.model.id // "")",
  @sh "proj_dir=\(.workspace.project_dir // .workspace.current_dir // .cwd // "")",
  @sh "ctx_size=\(.context_window.context_window_size // 0)",
  @sh "ctx_pct=\(.context_window.used_percentage // 0)",
  @sh "ctx_used_exact=\(((.context_window.context_window_size | numbers // 0) * (.context_window.used_percentage | numbers // 0) / 100) | round)",
  @sh "r5_pct=\(.rate_limits.five_hour.used_percentage // "")",
  @sh "r5_reset=\(.rate_limits.five_hour.resets_at // "")",
  @sh "r7_pct=\(.rate_limits.seven_day.used_percentage // "")",
  @sh "r7_reset=\(.rate_limits.seven_day.resets_at // "")",
  @sh "effort=\(.effort.level // "")"
')"

# A billing-month rollover also clears the weekly window; tmux-og's usage cache
# is the only source of the monthly reset. Mirrors tmux-agent-usage.sh's dir
# resolution and owner checks (the dir may sit in a world-writable /tmp).
if [[ -n $r7_reset ]]; then
  usage_dir=${OG_AGENT_USAGE_DIR:-}
  if [[ -z $usage_dir ]]; then
    usage_dir=${XDG_RUNTIME_DIR:-}
    [[ $usage_dir == /* ]] || usage_dir=${TMPDIR:-/tmp}
    usage_dir="${usage_dir%"${usage_dir##*[!/]}"}/og-agent-usage-$UID"
  fi
  usage_file=$usage_dir/claude.json
  if [[ -d $usage_dir && -O $usage_dir && -f $usage_file && ! -L $usage_file && -O $usage_file ]]; then
    monthly_reset=$(jq -r '.monthly.reset_at | numbers // empty' "$usage_file" 2>/dev/null) || monthly_reset=''
    if [[ $monthly_reset =~ ^[1-9][0-9]{0,11}$ ]]; then
      printf -v now '%(%s)T' -1
      if ((monthly_reset > now && monthly_reset < ${r7_reset%%.*})); then
        r7_reset=$monthly_reset
      fi
    fi
  fi
fi

R="\033[0m"

# Emoji via hex (avoids encoding issues in nix builds)
robot=$(printf '\xF0\x9F\xA4\x96')
chart=$(printf '\xF0\x9F\x93\x8A')
zap=$(printf '\xE2\x9A\xA1')
arrow=$(printf '\xE2\x86\x92')
brain=$(printf '\xF0\x9F\xA7\xA0')

# Color by threshold
color_pct() {
  local p=${1%%.*}
  if ((p >= 90)); then
    printf "\033[1;31m"
  elif ((p >= 70)); then
    printf "\033[1;33m"
  else
    printf "\033[1;32m"
  fi
}

fmt_countdown() {
  local now
  printf -v now '%(%s)T' -1
  local left=$(($1 - now))
  ((left <= 0)) && {
    echo "0m"
    return
  }
  local d=$((left / 86400)) h=$(((left % 86400) / 3600)) m=$(((left % 3600) / 60))
  ((d > 0)) && {
    echo "${d}d${h}h"
    return
  }
  ((h > 0)) && echo "${h}h${m}m" || echo "${m}m"
}

fmt_clock() {
  printf '%(%H:%M)T' "$1"
}

# --- Model ---
# 1M context is the default now, so drop the "(1M context)" display suffix
model=${model% (1M context)}
out="\033[1;34m$robot $model$R"
if [[ -n $effort ]]; then
  case $effort in
  medium) eff=med ;;
  xhigh) eff=xhi ;;
  *) eff=$effort ;;
  esac
  out+=" \033[2m$brain $eff$R"
fi

# --- Context ---
# Auto-compact fires before the window fills, so measure against its trigger:
# window - 20000 (output reserve, assumes maxOutputTokens >= 20000) - 13000.
# CLAUDE_AUTOCOMPACT_PCT_OVERRIDE can only lower it. The window comes from
# CLAUDE_CODE_AUTO_COMPACT_WINDOW or autoCompactWindow in the user, project and
# project-local settings files. The `--settings` overlay and managed/policy
# settings are not read. Unconfigured keeps the full window.
is_truthy() {
  case ${1,,} in
  1 | true | yes | on) return 0 ;;
  *) return 1 ;;
  esac
}

# Layers are read lowest to highest precedence. Mirroring Claude Code's merge,
# a layer's valid top-level autoCompactWindow (integer in 100000..1000000; any
# other value is dropped as if absent) sets the default and discards lower
# layers' per-model values; otherwise its per-model value ("auto" or the same
# integer) sets the model override. "auto" is kept so it can clear lower layers.
ac_default='' ac_model='' ac_enabled=''
read_ac_layer() {
  local out t m e
  [[ -f $1 ]] || return 0
  # Key normalisation is a subset of Claude Code's model-alias resolution.
  out=$(jq -r --arg m "$canon_model" '
    def win: type == "number" and . == floor and . >= 100000 and . <= 1000000;
    def top: if win then tostring else "-" end;
    def per: if . == "auto" then "auto" else top end;
    def norm: sub("\\[.*$"; "") | sub("[-@][0-9]{8}$"; "");
    ([.modelSettings | objects | to_entries[]
      | select((.key | norm) == $m)
      | {k: .key, v: (.value | objects | .autoCompactWindow | per)}
      | select(.v != "-")] as $c
     | (.autoCompactWindow | top),
       (([$c[] | select(.k == $m)][0].v) // $c[0].v // "-"),
       (.autoCompactEnabled | if type == "boolean" then tostring else "-" end))
  ' "$1" 2>/dev/null | tr '\n' ' ') || return 0
  read -r t m e <<<"$out"
  if [[ -n $t && $t != - ]]; then
    ac_default=$t
    ac_model=''
    [[ -z $m || $m == - ]] || ac_model=$m
  elif [[ -n $m && $m != - ]]; then
    ac_model=$m
  fi
  [[ -z $e || $e == - ]] || ac_enabled=$e
}

canon_model=${model_id%%\[*}
if [[ $canon_model =~ ^(.*)[-@][0-9]{8}$ ]]; then
  canon_model=${BASH_REMATCH[1]}
fi
user_dir=${CLAUDE_CONFIG_DIR:-${HOME:+$HOME/.claude}}
if [[ -n $user_dir ]]; then
  read_ac_layer "$user_dir/settings.json"
fi
if [[ -n $proj_dir ]]; then
  read_ac_layer "$proj_dir/.claude/settings.json"
  read_ac_layer "$proj_dir/.claude/settings.local.json"
fi
ac_window=${ac_model:-$ac_default}

env_window=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}
if [[ $env_window =~ ^[0-9]+$ ]]; then
  env_digits=${env_window#"${env_window%%[!0]*}"}
  if [[ -n $env_digits ]]; then
    env_n=1000000
    if ((${#env_digits} <= 7 && 10#$env_digits < 1000000)); then
      env_n=$((10#$env_digits))
    fi
    ac_window=$((env_n < 100000 ? 100000 : env_n))
  fi
fi
if [[ $ac_window =~ ^[0-9]{1,12}$ ]] && ((10#$ac_window > 0)); then
  ac_window=$((10#$ac_window))
else
  ac_window=''
fi

ac_pm='' # percent * 1000: Claude Code accepts decimals
env_pct=${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-}
if [[ $env_pct =~ ^([0-9]{1,6})(\.([0-9]+))?$ ]]; then
  pm_int=$((10#${BASH_REMATCH[1]}))
  pm_frac=${BASH_REMATCH[3]}000
  pm=$((pm_int * 1000 + 10#${pm_frac:0:3}))
  # Reject above 100 before the fraction is truncated to three digits.
  if ((pm >= 1 && pm <= 100000)); then
    if ((pm_int != 100)) || [[ $pm_frac != *[1-9]* ]]; then
      ac_pm=$pm
    fi
  fi
fi

ac_off=0
if is_truthy "${DISABLE_COMPACT:-}" || is_truthy "${DISABLE_AUTO_COMPACT:-}"; then
  ac_off=1
else
  if [[ -z $ac_enabled ]]; then
    cfg_dir=${CLAUDE_CONFIG_DIR:-${HOME:-}}
    if [[ -n $cfg_dir && -f $cfg_dir/.claude.json ]]; then
      ac_enabled=$(jq -r '.autoCompactEnabled | booleans' "$cfg_dir/.claude.json" 2>/dev/null) || ac_enabled=''
    fi
  fi
  if [[ $ac_enabled == false ]]; then
    ac_off=1
  fi
fi

ctx_den=${ctx_size:-200000}
ctx_int=${ctx_pct%%.*}
ctx_used=$(((${ctx_size:-200000} * ctx_int + 50) / 100))
if ((ac_off == 0)) && [[ -n $ac_window || -n $ac_pm ]]; then
  eff=${ctx_size:-200000}
  if [[ -n $ac_window ]] && ((ac_window < eff)); then
    eff=$ac_window
  fi
  reserve=$((eff - 20000))
  trigger=$((reserve - 13000))
  if [[ -n $ac_pm ]] && ((reserve * ac_pm / 100000 < trigger)); then
    trigger=$((reserve * ac_pm / 100000))
  fi
  if ((trigger > 0)); then
    ctx_den=$trigger
    ctx_used=$ctx_used_exact
    ctx_int=$((ctx_used * 100 / trigger))
  fi
fi

tc=$(color_pct "$ctx_int")
if ((ctx_den >= 1000000)); then
  out+=" | ${tc}$chart $((ctx_used / 1000))k/$((ctx_den / 1000000))M$R"
else
  out+=" | ${tc}$chart $((ctx_used / 1000))k/$((ctx_den / 1000))k$R"
fi
if ((ac_off == 1)); then
  out+=" \033[2mno-ac$R"
fi

# --- Rate limits ---
# Formats: ⚡ 56% (32m) · 7d 76% (15h)  |  ⚡ 7d 46% (3d)
if [[ -n $r5_pct ]]; then
  r5i=${r5_pct%%.*}
  rc=$(color_pct "$r5i")
  part="${rc}${r5i}%"
  [[ -n $r5_reset ]] && part+=" ($(fmt_countdown "${r5_reset%%.*}") $arrow $(fmt_clock "${r5_reset%%.*}"))"
  part+="$R"

  # Show 7d only when >50%
  if [[ -n $r7_pct ]]; then
    r7i=${r7_pct%%.*}
    if ((r7i > 50)); then
      r7c=$(color_pct "$r7i")
      part+=" ${r7c}7d ${r7i}%"
      [[ -n $r7_reset ]] && part+=" ($(fmt_countdown "${r7_reset%%.*}"))"
      part+="$R"
    fi
  fi

  out+=" | $zap $part"
elif [[ -n $r7_pct ]]; then
  # No five-hour window: the 7d window is the only one, so show it regardless of share
  r7i=${r7_pct%%.*}
  part="$(color_pct "$r7i")7d ${r7i}%"
  [[ -n $r7_reset ]] && part+=" ($(fmt_countdown "${r7_reset%%.*}"))"
  part+="$R"
  out+=" | $zap $part"
fi

echo -e "$out"

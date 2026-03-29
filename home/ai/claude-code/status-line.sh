#!/usr/bin/env bash

input=$(cat)
if [[ -z $input ]] || ! echo "$input" | jq empty 2>/dev/null; then
  echo "Claude Code"
  exit 0
fi

model='' ctx_size=0 ctx_pct=0 r5_pct='' r5_reset='' r7_pct='' r7_reset=''
eval "$(echo "$input" | jq -r '
  @sh "model=\(.model.display_name // "Unknown")",
  @sh "ctx_size=\(.context_window.context_window_size // 0)",
  @sh "ctx_pct=\(.context_window.used_percentage // 0)",
  @sh "r5_pct=\(.rate_limits.five_hour.used_percentage // "")",
  @sh "r5_reset=\(.rate_limits.five_hour.resets_at // "")",
  @sh "r7_pct=\(.rate_limits.seven_day.used_percentage // "")",
  @sh "r7_reset=\(.rate_limits.seven_day.resets_at // "")"
')"

R="\033[0m"

# Emoji via hex (avoids encoding issues in nix builds)
robot=$(printf '\xF0\x9F\xA4\x96')
chart=$(printf '\xF0\x9F\x93\x8A')
zap=$(printf '\xE2\x9A\xA1')

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
  local h=$(((left % 86400) / 3600)) m=$(((left % 3600) / 60))
  ((h > 0)) && echo "${h}h${m}m" || echo "${m}m"
}

# --- Model ---
out="\033[1;34m$robot $model$R"

# --- Context ---
ctx_int=${ctx_pct%%.*}
ctx_used=$(((${ctx_size:-200000} * ctx_int + 50) / 100))
tc=$(color_pct "$ctx_int")
if ((${ctx_size:-200000} >= 1000000)); then
  out+=" | ${tc}$chart $((ctx_used / 1000))k/$((ctx_size / 1000000))M$R"
else
  out+=" | ${tc}$chart $((ctx_used / 1000))k/$((${ctx_size:-200000} / 1000))k$R"
fi

# --- Rate limits ---
# Format: ⚡ 56% (32m) · 7d 76% (15h)
if [[ -n $r5_pct ]]; then
  r5i=${r5_pct%%.*}
  rc=$(color_pct "$r5i")
  part="${rc}${r5i}%"
  [[ -n $r5_reset ]] && part+=" ($(fmt_countdown "${r5_reset%%.*}"))"
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
fi

echo -e "$out"

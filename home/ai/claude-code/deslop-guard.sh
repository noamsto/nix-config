#!/usr/bin/env bash
# PreToolUse hook: block `git push` and `gh pr create` until the deslop skill
# has run on this branch in the current session. deslop-mark.sh (PostToolUse on
# Skill) records the per-session, per-branch sentinel this guard checks for.
# A hook can't run the deslop review itself (that needs Claude to read the diff
# and edit) — it only forces /deslop to run first. Set
# ALLOW_PUSH_WITHOUT_DESLOP=1 for a deliberate bypass.

set -euo pipefail

input=$(cat)

tool_name=$(jq -r '.tool_name // empty' <<<"$input")
[[ $tool_name == "Bash" ]] || exit 0

command=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ -n $command ]] || exit 0

# Byte offsets throughout: the masked views are indexed alongside the raw text.
export LC_ALL=C

# Same-length copy of $1 with command separators inside quotes replaced by `_`,
# so quoted text (`-m 'a; cd x'`) can't pose as structure. Lenient: used only
# when scan() can't parse the command.
mask_quoted() {
  local s=$1 out="" q="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    if [[ -n $q ]]; then
      [[ $c == "$q" ]] && q=""
      [[ $c == [\;\&\|$'\n'] ]] && c=_
    elif [[ $c == [\"\'] ]]; then
      q=$c
    fi
    out+=$c
  done
  printf '%s' "$out"
}

# Whether a command is a push or a `gh pr create` is decided on a masked view of
# its text, so the words inside a quoted argument, a comment or a heredoc body
# don't count. Text that really runs does: command position, wrappers, command
# substitutions and the payload of `bash -c`, `eval`, `ssh` and friends, which
# are rescanned as commands of their own.
seps=$';&|(){}!`\n'
size_cap=32768     # a longer text isn't masked (the loop is slow); raw detection gates it
special_cap=2000   # likewise a text with more separators/quotes/parens than this
special_total=6000 # and across a command with all its payloads
special_chars=$';&|(){}$\'"`\\\\<#\n'
max_payloads=16
push_re='^git[[:space:]]+(-[Cc][[:space:]]+[^[:space:]]+[[:space:]]+|-[^[:space:]]+[[:space:]]+)*push([[:space:]]|$|[;&|(){}`])'
gh_re='^gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$|[;&|(){}`])'

# Scan $1 as shell source. $2 is the starting context ("" for a command, "h" for
# the body of an unquoted heredoc), $3 the offset of $1 in the outermost text.
# Sets sc_full (text of quotes, comments and heredoc bodies blanked to `_`) and
# sc_sep (the same, but quoted text kept and only separators in it blanked), both
# as long as $1, and records quote pairs in qclose[] and heredoc bodies in
# hd_body[], keyed by outermost offsets. Returns 1 when $1 isn't well formed
# (unbalanced quote or substitution, unterminated heredoc).
# shellcheck disable=SC1003,SC2016 # `'\'` and `'$('` are the shell syntax being scanned
scan() {
  local s=$1 st=$2 base=$3 st0=$2
  local n=${#s} i=0 c top run x j pos b0 b1 k rest line cmp body delim q strip bf bs nx esc_at=-1
  local full="" sep=""
  local -a qopen=() pdelim=() pquoted=() pstrip=() poff=() pdepth=()
  local re_sq="^'([^']*)'" re_dq='^"([^"]*)"' re_bs='^\\([^[:space:];&|()<>]+)'
  local re_bare="^([^[:space:];&|()<>'\"\\\\]+)" case_re='(^|[[:space:];&|])case([[:space:]]|$)'
  local dq_special='["\\$`]' h_special='[\\$`]'
  local norm_special=$'[\\\\\'"`$(){}#<\n]'
  while ((i < n)); do
    c=${s:i:1}
    top=${st: -1}
    case $top in
    "'")
      if [[ $c == "'" ]]; then
        st=${st%?}
        qclose[qopen[-1]]=$((base + i))
        unset 'qopen[-1]'
        full+=$c sep+=$c
        i=$((i + 1))
      else
        run=${s:i}
        run=${run%%\'*}
        full+=${run//?/_}
        sep+=${run//[;&|$'\n']/_}
        i=$((i + ${#run}))
      fi
      ;;
    A)
      if [[ $c == "'" ]]; then
        st=${st%?}
        qclose[qopen[-1]]=$((base + i))
        unset 'qopen[-1]'
        full+=$c sep+=$c
        i=$((i + 1))
      elif [[ $c == '\' ]]; then
        x=${s:i:2}
        full+=${x//?/_}
        sep+=${x//[;&|$'\n']/_}
        i=$((i + ${#x}))
      else
        run=${s:i}
        run=${run%%[\\\']*}
        full+=${run//?/_}
        sep+=${run//[;&|$'\n']/_}
        i=$((i + ${#run}))
      fi
      ;;
    '"' | h)
      if [[ $top == '"' && $c == '"' ]]; then
        st=${st%?}
        qclose[qopen[-1]]=$((base + i))
        unset 'qopen[-1]'
        full+=$c sep+=$c
        i=$((i + 1))
      elif [[ $c == '\' ]]; then
        x=${s:i:2}
        full+=${x//?/_}
        sep+=${x//[;&|$'\n']/_}
        i=$((i + ${#x}))
      elif [[ $c == '$' && ${s:i+1:1} == '(' ]]; then
        st+='$'
        full+='$(' sep+='$('
        i=$((i + 2))
      elif [[ $c == '`' ]]; then
        st+='`'
        full+=$c sep+=$c
        i=$((i + 1))
      elif [[ $c == '$' && ${s:i+1:1} == '{' ]]; then
        # Quotes nested in "${…}" nest in ways this scanner doesn't follow.
        rest=${s:i+2}
        [[ ${rest%%\}*} == *[\'\"]* ]] && return 1
        full+=_ sep+=$c
        i=$((i + 1))
      else
        run=${s:i}
        # shellcheck disable=SC2295 # the specials are glob bracket sets, not literals
        if [[ $top == h ]]; then run=${run%%$h_special*}; else run=${run%%$dq_special*}; fi
        [[ -n $run ]] || run=$c
        full+=${run//?/_}
        sep+=${run//[;&|$'\n']/_}
        i=$((i + ${#run}))
      fi
      ;;
    *)
      # Jump over text that can't change the scan state.
      run=${s:i}
      # shellcheck disable=SC2295 # $norm_special is a glob bracket set, not a literal
      run=${run%%$norm_special*}
      if [[ -n $run ]]; then
        # A `case` pattern's `)` would end the substitution early; don't guess.
        [[ -n $top && $run =~ $case_re ]] && return 1
        full+=$run sep+=$run
        i=$((i + ${#run}))
        continue
      fi
      case $c in
      '\')
        x=${s:i:2}
        full+=$x sep+=$x
        i=$((i + ${#x}))
        esc_at=$i
        ;;
      "'")
        # Inside backquotes the next backquote ends the command whatever quotes or
        # comments come first; don't guess.
        [[ $top == '`' ]] && return 1
        qopen+=("$((base + i))")
        if ((i > 0)) && [[ ${s:i-1:1} == '$' ]]; then
          # `\$'` and `$$'` aren't ANSI-C quotes; don't guess.
          ((i > 1)) && [[ ${s:i-2:1} == [\\\$] ]] && return 1
          st+=A
        else
          st+="'"
        fi
        full+=$c sep+=$c
        i=$((i + 1))
        ;;
      '"')
        [[ $top == '`' ]] && return 1
        qopen+=("$((base + i))")
        st+='"'
        full+=$c sep+=$c
        i=$((i + 1))
        ;;
      '`')
        if [[ $top == '`' ]]; then st=${st%?}; else st+='`'; fi
        full+=$c sep+=$c
        i=$((i + 1))
        ;;
      '$')
        if [[ ${s:i+1:1} == '(' ]]; then
          st+='$'
          full+='$(' sep+='$('
          i=$((i + 2))
        elif [[ ${s:i+1:1} == '{' ]]; then
          st+='{'
          full+='${' sep+='${'
          i=$((i + 2))
        else
          full+=$c sep+=$c
          i=$((i + 1))
        fi
        ;;
      '(')
        # `((` is arithmetic, where `<<` and `#` mean other things; don't guess.
        [[ ${s:i+1:1} == '(' || (i -gt 0 && ${s:i-1:1} == '(') ]] && return 1
        [[ $top == '$' || $top == '(' ]] && st+='('
        full+=$c sep+=$c
        i=$((i + 1))
        ;;
      ')')
        [[ $top == '$' || $top == '(' ]] && st=${st%?}
        full+=$c sep+=$c
        i=$((i + 1))
        ;;
      '}')
        [[ $top == '{' ]] && st=${st%?}
        full+=$c sep+=$c
        i=$((i + 1))
        ;;
      '#')
        [[ $top == '`' ]] && return 1
        # Not a comment inside `${…}` or after an escaped blank.
        if [[ $top != '{' ]] && { ((i == 0)) || { ((i != esc_at)) && [[ ${s:i-1:1} == [[:space:]\;\&\|\(] ]]; }; }; then
          run=${s:i}
          run=${run%%$'\n'*}
          full+=${run//?/_} sep+=${run//?/_}
          i=$((i + ${#run}))
        else
          full+=$c sep+=$c
          i=$((i + 1))
        fi
        ;;
      '<')
        if [[ ${s:i:3} == '<<<' ]]; then
          full+='<<<' sep+='<<<'
          i=$((i + 3))
        elif [[ ${s:i:2} == '<<' ]]; then
          j=$((i + 2)) strip=0
          if [[ ${s:j:1} == - ]]; then
            strip=1
            j=$((j + 1))
          fi
          rest=${s:j}
          x=${rest%%[![:blank:]]*}
          j=$((j + ${#x}))
          rest=${s:j}
          if [[ $rest =~ $re_sq || $rest =~ $re_dq || $rest =~ $re_bs ]]; then
            delim=${BASH_REMATCH[1]} q=1
          elif [[ $rest =~ $re_bare ]]; then
            delim=${BASH_REMATCH[1]} q=0
          else
            return 1
          fi
          # A delimiter quoted mid-word (`E"OF"`), or a shift (`1<<2`), isn't read here.
          nx=${rest:${#BASH_REMATCH[0]}:1}
          [[ -z $nx || $nx == [[:space:]\;\&\|\<\>\(\)] ]] || return 1
          [[ $delim =~ ^[0-9]+$ || $delim == *[\\\'\"]* || $top == '(' || $top == '{' ]] && return 1
          pdelim+=("$delim") pquoted+=("$q") pstrip+=("$strip") poff+=("$((base + i))") pdepth+=("${#st}")
          x=${s:i:j-i}
          full+=$x sep+=$x
          i=$j
        else
          full+=$c sep+=$c
          i=$((i + 1))
        fi
        ;;
      $'\n')
        full+=$c sep+=$c
        i=$((i + 1))
        pos=$i
        for k in "${!pdelim[@]}"; do
          # Bash reads the body after the whole command line, past any `)` that
          # closes a substitution opened since; don't guess when the depth moved.
          ((${#st} == pdepth[k])) || return 1
          b0=$pos
          while :; do
            ((pos < n)) || return 1
            rest=${s:pos}
            line=${rest%%$'\n'*}
            cmp=$line
            ((pstrip[k])) && cmp=${cmp#"${cmp%%[!$'\t']*}"}
            [[ $cmp == "${pdelim[k]}" ]] && break
            # An end-of-line backslash joins lines, and `EOF)` ends a body inside `$(`.
            if [[ $cmp == "${pdelim[k]})" ]] || { ((! pquoted[k])) && [[ $line == *\\ ]]; }; then
              return 1
            fi
            pos=$((pos + ${#line} + 1))
          done
          b1=$pos
          body=${s:b0:b1-b0}
          body=${body%$'\n'}
          hd_body[poff[k]]=$body
          if ((pquoted[k])); then
            bf=${body//[!$'\n']/_}
            bs=$bf
          else
            scan "$body" h "$((base + b0))" || return 1
            bf=$sc_full bs=$sc_sep
          fi
          if ((b1 > b0)); then
            full+=$bf$'\n' sep+=$bs$'\n'
          fi
          line=${s:b1:${#line}}
          full+=$line sep+=$line
          pos=$((b1 + ${#line}))
          if ((pos < n)); then
            full+=$'\n' sep+=$'\n'
            pos=$((pos + 1))
          fi
        done
        pdelim=() pquoted=() pstrip=() poff=() pdepth=()
        i=$pos
        ;;
      *)
        full+=$c sep+=$c
        i=$((i + 1))
        ;;
      esac
      ;;
    esac
  done
  [[ $st == "$st0" && ${#pdelim[@]} -eq 0 ]] || return 1
  sc_full=$full sc_sep=$sep
  return 0
}

# Scan $1 for the views below, or fail so callers fall back to raw detection.
scan_text() {
  local x
  qclose=() hd_body=()
  m_full="" m_sep=""
  ((${#1} <= size_cap)) || return 1
  # The scanner's cost grows with its state-changing characters, not just length.
  x=${1//[^$special_chars]/}
  ((${#x} <= special_cap)) || return 1
  spec_total=$((spec_total + ${#x}))
  ((spec_total <= special_total)) || return 1
  scan "$1" "" 0 || return 1
  m_full=$sc_full m_sep=$sc_sep
  return 0
}

# True when the segment before a hit ($1, starting at offset $2 of view $3) starts
# with a command that only prints its arguments, unless the printed text is
# executed anyway through a substitution.
printer_segment() {
  local -a t=()
  local base lead idx i=0
  read -ra t <<<"$1"
  while ((i < ${#t[@]})); do
    case ${t[i]} in
    if | then | do | else | elif | while | until | '!' | [A-Za-z_]*=*) ;;
    *) break ;;
    esac
    i=$((i + 1))
  done
  ((i < ${#t[@]})) || return 1
  base=${t[i]##*/}
  case $base in echo | printf | :) ;; *) return 1 ;; esac
  idx=$(($2 - 1))
  if ((idx >= 0)); then
    lead=${3:idx:1}
    [[ $lead == '`' ]] && return 1
    [[ $lead == '(' ]] && ((idx > 0)) && [[ ${3:idx-1:1} == '$' ]] && return 1
  fi
  return 0
}

# Occurrences of a push or `gh pr create` in view $1 -> hit_kind[], hit_pos[],
# hit_len[] (len covers the match through the whitespace after its last word).
# $2 = strict: only where the command could run, i.e. not as the argument of a
# printer. Non-strict is the plain raw-text match of a command that can't be masked.
find_hits() {
  local m=$1 strict=$2 off=0 ss=0 rest pre pos prev word kind len tail head pipes=false
  hit_kind=() hit_pos=() hit_len=()
  # Printed text can be piped into a shell in more ways than are worth following,
  # so a printer is only trusted in a command with no pipe or process substitution.
  tail=${m//||/}
  [[ $tail == *'|'* || $m == *'<('* || $m == *'>('* ]] && pipes=true
  while :; do
    rest=${m:off}
    [[ $rest =~ (git|gh)[[:space:]] ]] || break
    pre=${rest%%"${BASH_REMATCH[0]}"*}
    pos=$((off + ${#pre}))
    off=$((pos + 1))
    if ((pos > 0)); then
      prev=${m:pos-1:1}
      [[ $prev == [[:space:]\;\&\|\(\)\{\}\!\`/] ]] || continue
    fi
    word=${rest:${#pre}}
    if [[ $word =~ $push_re ]]; then
      kind=push
    elif [[ $word =~ $gh_re ]]; then
      kind=gh
    else
      continue
    fi
    len=${#BASH_REMATCH[0]}
    # A separator ending the match isn't part of it: whatever follows is a new command.
    [[ ${BASH_REMATCH[0]: -1} == [$seps] ]] && len=$((len - 1))
    if [[ $strict == true ]]; then
      # Walk forward to the segment holding the hit (a backward glob is quadratic).
      while :; do
        tail=${m:ss}
        # shellcheck disable=SC2295 # $seps is a glob bracket set, not a literal
        head=${tail%%[$seps]*}
        ((ss + ${#head} < pos)) || break
        ss=$((ss + ${#head} + 1))
      done
      if [[ $pipes == false ]] && printer_segment "${m:ss:pos-ss}" "$ss" "$m"; then continue; fi
    fi
    hit_kind+=("$kind") hit_pos+=("$pos") hit_len+=("$len")
  done
  return 0
}

# Shell payloads in $1 (the text last given to scan_text) -> pl_text[], pl_at[]
# (offset where each starts). A segment that runs `eval`/`ssh` (any quoted
# argument), a shell (a quoted argument after a `-…c` flag) or feeds one a
# here-string or heredoc contributes those texts; so does everything quoted or
# heredoc'd before a `| shell`. Returns 1 when there are too many to chase.
collect_payloads() {
  local text=$1 m=$m_full off=0 rest seg segstart segend ext mode w b prev pprev
  local pre rel abs close ok segrest k n
  local -a toks=() bt=()
  pl_text=() pl_at=()
  while ((off <= ${#m})); do
    rest=${m:off}
    # shellcheck disable=SC2295 # $seps is a glob bracket set, not a literal
    seg=${rest%%[$seps]*}
    segstart=$off
    segend=$((off + ${#seg}))
    off=$((segend + 1))
    read -ra toks <<<"$seg"
    mode=""
    for w in "${toks[@]}"; do
      b=${w##*/}
      case $b in
      eval | ssh)
        mode=any
        break
        ;;
      bash | sh | zsh | fish | dash | ksh | source | .)
        mode=shell
        break
        ;;
      esac
    done
    [[ -n $mode ]] || continue
    ext=$segend
    segrest=$seg rel=0
    while [[ $segrest == *[\'\"]* ]]; do
      pre=${segrest%%[\'\"]*}
      rel=$((rel + ${#pre}))
      abs=$((segstart + rel))
      if [[ -n ${qclose[abs]+x} ]]; then
        close=${qclose[abs]}
        ((close > ext)) && ext=$close
        ok=false
        b=${seg:0:rel}
        if [[ $b =~ \<\<\<[[:space:]]*$ || $mode == any ]]; then
          ok=true
        else
          read -ra bt <<<"$b"
          for w in "${bt[@]}"; do
            [[ $w =~ ^-[a-zA-Z]*c[a-zA-Z]*$ ]] && ok=true
          done
        fi
        if [[ $ok == true ]]; then
          pl_text+=("${text:abs+1:close-abs-1}") pl_at+=("$abs")
        fi
        rel=$((close - segstart + 1))
        ((rel <= ${#seg})) || break
        segrest=${seg:rel}
      else
        rel=$((rel + 1))
        segrest=${seg:rel}
      fi
    done
    for k in "${!hd_body[@]}"; do
      if ((k >= segstart && k <= ext)); then
        pl_text+=("${hd_body[k]}") pl_at+=("$k")
      fi
    done
    prev="" pprev=""
    ((segstart > 0)) && prev=${m:segstart-1:1}
    ((segstart > 1)) && pprev=${m:segstart-2:1}
    if [[ $mode == shell && $prev == '|' && $pprev != '|' ]] ||
      [[ $mode == shell && $prev == '&' && $pprev == '|' ]]; then
      for k in "${!qclose[@]}"; do
        ((k < segstart)) && { pl_text+=("${text:k+1:qclose[k]-k-1}") pl_at+=("$k"); }
      done
      for k in "${!hd_body[@]}"; do
        ((k < segstart)) && { pl_text+=("${hd_body[k]}") pl_at+=("$k"); }
      done
    fi
    n=${#pl_text[@]}
    ((n <= max_payloads)) || return 1
  done
  return 0
}

# Whether $1 (a payload) holds a push or `gh pr create`, rescanning nested payloads.
gated_in() {
  local text=$1 depth=$2 p
  local -a pls=()
  if ((depth > 3)); then return 0; fi
  if ! scan_text "$text"; then
    find_hits "$text" false
    ((${#hit_pos[@]} > 0))
    return
  fi
  find_hits "$m_full" true
  ((${#hit_pos[@]} == 0)) || return 0
  collect_payloads "$text" || return 0
  pls=("${pl_text[@]}")
  for p in "${pls[@]}"; do
    if gated_in "$p" $((depth + 1)); then return 0; fi
  done
  return 1
}

# Settle for raw-text detection of $1: eff_* come from the unmasked text.
# $3 = true forces other_gated (a payload that couldn't be masked).
resolve_raw() {
  find_hits "$1" false
  ((${#hit_pos[@]} > 0)) || return 1
  eff=$1 eff_prefix=$2
  eff_sep=$1
  ((${#1} > size_cap)) || eff_sep=$(mask_quoted "$1")
  eff_kind=("${hit_kind[@]}") eff_pos=("${hit_pos[@]}") eff_len=("${hit_len[@]}")
  other_gated=false
  if ((${#hit_pos[@]} > 1)) || [[ $3 == true ]]; then other_gated=true; fi
  return 0
}

# Find the text a push really runs in: $1 when it holds a push or `gh pr create`
# at a command, else the first payload that does (recursively). Sets eff (that
# text), eff_sep (its masked view), eff_prefix (the outer text before
# it, so an outer `cd` still decides the target), eff_kind/pos/len (its hits) and
# other_gated (a second push, or a push elsewhere that the single-push exemptions
# below mustn't overlook). Returns 1 when nothing in $1 is a push.
resolve() {
  local text=$1 depth=$2 prefix=$3 k first=-1 sib=0 outer_sep p s_ force=false
  local -a pls=() pat=() k_=() p_=() l_=()
  ((depth > 0)) && force=true
  if ((depth > 3)) || ! scan_text "$text"; then
    resolve_raw "$text" "$prefix" "$force" || return 1
    return 0
  fi
  find_hits "$m_full" true
  if ((${#hit_pos[@]} > 0)); then
    k_=("${hit_kind[@]}") p_=("${hit_pos[@]}") l_=("${hit_len[@]}")
    s_=$m_sep
    other_gated=false
    ((${#p_[@]} > 1)) && other_gated=true
    if [[ $other_gated == false ]]; then
      if collect_payloads "$text"; then
        pls=("${pl_text[@]}")
        for p in "${pls[@]}"; do
          if gated_in "$p" $((depth + 1)); then
            other_gated=true
            break
          fi
        done
      else
        other_gated=true
      fi
    fi
    eff=$text eff_sep=$s_ eff_prefix=$prefix
    eff_kind=("${k_[@]}") eff_pos=("${p_[@]}") eff_len=("${l_[@]}")
    return 0
  fi
  collect_payloads "$text" || {
    resolve_raw "$text" "$prefix" false
    return
  }
  pls=("${pl_text[@]}") pat=("${pl_at[@]}")
  outer_sep=$m_sep
  for k in "${!pls[@]}"; do
    if gated_in "${pls[k]}" $((depth + 1)); then
      if ((first < 0)); then first=$k; else sib=$((sib + 1)); fi
    fi
  done
  ((first >= 0)) || return 1
  resolve "${pls[first]}" $((depth + 1)) "${prefix}${outer_sep:0:${pat[first]}}"$'\n' || return 1
  ((sib == 0)) || other_gated=true
  return 0
}

# Deliberate override. Honor it both as a hook-process env var and as an inline
# prefix in the intercepted command — env vars set inline (`ALLOW_…=1 git push`)
# reach only the git subprocess, never this hook, so the documented bypass is
# otherwise unusable from an agent (#25).
[[ ${ALLOW_PUSH_WITHOUT_DESLOP:-} == 1 ]] && exit 0
[[ $command =~ (^|[[:space:]])ALLOW_PUSH_WITHOUT_DESLOP=1([[:space:]]|$) ]] && exit 0

eff="" eff_sep="" eff_prefix="" other_gated=false spec_total=0
eff_kind=() eff_pos=() eff_len=()
resolve "$command" 0 "" || exit 0

session=$(jq -r '.session_id // empty' <<<"$input")
[[ -n $session ]] || exit 0

# git runs in the intercepted command's cwd, not the hook process's cwd.
cwd=$(jq -r '.cwd // empty' <<<"$input" || true)
cwd=${cwd:-$PWD}

# Resolve the directory the gated command truly runs in, so the branch matches
# what deslop-mark recorded: the push's own `git -C <dir>`, else the nearest `cd
# <dir>` before it. An earlier `git -C`/`cd` aimed at another checkout must not
# decide which repo is checked.
dq='"' sq="'"
path_re="(${dq}[^${dq}]+${dq}|${sq}[^${sq}]+${sq}|[^[:space:];&|]+)"
target=$cwd
anchor=""
# The hit the checks below follow: the first push, else the first `gh pr create`.
sel=-1 any_gh=false
for k in "${!eff_kind[@]}"; do
  [[ ${eff_kind[k]} == gh ]] && any_gh=true
  if ((sel < 0)) && [[ ${eff_kind[k]} == push ]]; then sel=$k; fi
done
((sel >= 0 || ${#eff_kind[@]} == 0)) || sel=0
if ((sel >= 0)); then
  hit_at=${eff_pos[sel]} hit_n=${eff_len[sel]}
  anchor=${eff_sep:hit_at:hit_n}
  if [[ ${eff_kind[sel]} == push && $anchor =~ git[[:space:]]+(.*[[:space:]])?-C[[:space:]]+$path_re ]]; then
    target=${BASH_REMATCH[2]}
    anchor=""
  fi
fi
if [[ -n $anchor ]]; then
  before_anchor=${eff_prefix}${eff_sep:0:hit_at}
  cd_re="^[[:space:]]*(([{(!]|if|then|do|else|elif|while|until|command|builtin)[[:space:]]*)*cd[[:space:]]+$path_re"
  while IFS= read -r seg; do
    if [[ $seg =~ $cd_re ]]; then
      dir=${BASH_REMATCH[3]}
      dir=${dir#[\"\']}
      dir=${dir%[\"\']}
      if [[ $dir == /* ]]; then target=$dir; else target=$target/$dir; fi
    fi
  done < <(tr ';&|' '\n' <<<"$before_anchor")
fi
target=${target#[\"\']}
target=${target%[\"\']}
[[ $target == /* ]] || target=$cwd/$target

git -C "$target" rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# `gh pr create --repo`/`-R` can target a different repository than `target`'s
# local checkout — the cross-repo git-common-dir fallback further down never
# fires here, since target == cwd for this command. Parse --repo/-R directly:
# if it names a repo other than target's origin, the local branch isn't what's
# being reviewed, so skip the gate (no network call — origin comes from the
# local git config).
normalize_repo() {
  local url=$1
  url=${url%.git}
  url=${url%/}
  url=${url#*://}
  url=${url##*@}
  url=${url/:/\/}
  while [[ $url == */*/* ]]; do
    url=${url#*/}
  done
  printf '%s' "${url,,}"
}

if [[ $any_gh == true ]]; then
  repo_flag=""
  # Tokenize with the shell's own quoting rules (via xargs) rather than
  # regex-scanning the raw string, so `--repo=` text embedded inside an
  # unrelated quoted --title/--body argument can't be mistaken for the flag.
  prev=""
  while IFS= read -r tok; do
    if [[ $prev == "--repo" || $prev == "-R" ]]; then
      repo_flag=$tok
      break
    fi
    case $tok in
    --repo=*) repo_flag=${tok#--repo=} ;;
    -R=*) repo_flag=${tok#-R=} ;;
    esac
    [[ -n $repo_flag ]] && break
    prev=$tok
  done < <(xargs -n1 <<<"$eff" 2>/dev/null || true)
  if [[ -n $repo_flag ]]; then
    origin_url=$(git -C "$target" remote get-url origin 2>/dev/null || true)
    if [[ -n $origin_url ]]; then
      [[ $(normalize_repo "$origin_url") != "$(normalize_repo "$repo_flag")" ]] && exit 0
    fi
  fi
fi

# Tag-only pushes carry no branch commits to review, so the deslop gate doesn't
# apply — the deploy flow here is all tag pushes (`git push origin v*-…`). Skip
# the gate when every pushed refspec resolves to a tag (or deletes one) and no
# flag drags commits along. A tag created earlier in the same command counts:
# this hook runs before the command, so the ref doesn't exist yet. Bare
# `git push` (current branch), any branch refspec, --follow-tags/--all/--mirror/
# --branches, a second push, and `gh pr create` fall through to the gate.
# Tag names a segment creates: `git [globals] tag [flags] <name>`, skipping
# list/delete/verify modes.
created_tags_in() {
  local -a t=()
  local i=0 n name listing=false tok
  mapfile -t t < <(xargs -n1 <<<"$1" 2>/dev/null || true)
  n=${#t[@]}
  while ((i < n)) && [[ ${t[i]} =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do i=$((i + 1)); done
  ((i < n)) && [[ ${t[i]} == git ]] || return 0
  i=$((i + 1))
  while ((i < n)) && [[ ${t[i]} == -* ]]; do
    case ${t[i]} in -C | -c) i=$((i + 2)) ;; *) i=$((i + 1)) ;; esac
  done
  ((i < n)) && [[ ${t[i]} == tag ]] || return 0
  i=$((i + 1))
  name=""
  while ((i < n)); do
    tok=${t[i]}
    case $tok in
    -m | -F | -u | --message | --file | --local-user | --trailer | --cleanup | --color) i=$((i + 1)) ;;
    -d | --delete | -l | --list | -v | --verify | -n* | --contains* | --no-contains* | --points-at* | --merged* | --no-merged* | --sort* | --format*) listing=true ;;
    -*) : ;;
    *)
      name=$tok
      break
      ;;
    esac
    i=$((i + 1))
  done
  [[ $listing == false && -n $name ]] && printf '%s\n' "$name"
  return 0
}

is_push=false
refspecs=() push_remote=""
if ((sel >= 0)) && [[ ${eff_kind[sel]} == push ]]; then
  is_push=true
  before=${eff:0:hit_at}
  after=${eff:hit_at+hit_n} # args after the `push` word
  # Drop redirections (`2>&1`, `&>f`, `> f`, `<f`) so they aren't read as refspecs.
  after=$(sed -E 's/(^|[[:space:]])(&>>?|[0-9]*[<>]+\|?&?)[[:space:]]*[^[:space:];&|]*/ /g' <<<"$after")
  # A redirect glued to a word (`v1>/dev/null`) is cut off the word.
  after=$(sed -E 's/([^[:space:]])[<>][^[:space:];&|]*/\1/g' <<<"$after")
  args=${after%%[;&|$'\n']*} # ignore anything past a shell separator

  created_tags=()
  while IFS= read -r seg; do
    [[ $seg == *git*tag* ]] || continue # created_tags_in forks xargs; skip lines it can't match
    while IFS= read -r name; do
      [[ -n $name ]] && created_tags+=("$name")
    done < <(created_tags_in "$seg")
  done < <(tr ';&|' '\n' <<<"$before")

  is_tag() {
    local x
    # A name that is also a local branch may belong to a `git tag` that never
    # ran (or ran elsewhere), so only a pre-existing tag counts then.
    git -C "$target" rev-parse --verify --quiet "refs/tags/$1" >/dev/null 2>&1 && return 0
    for x in "${created_tags[@]}"; do
      [[ $x == "$1" ]] &&
        ! git -C "$target" rev-parse --verify --quiet "refs/heads/$1" >/dev/null 2>&1 && return 0
    done
    return 1
  }

  read -ra ptoks <<<"$args"
  carries_commits=false saw_remote=false saw_refspec=false tag_only=true
  for tok in "${ptoks[@]}"; do
    case $tok in
    --follow-tags | --all | --mirror | --branches) carries_commits=true ;;
    --tags) saw_refspec=true ;; # all tags, no branch
    -*) : ;;                    # other flags (-f, --force-with-lease, …)
    *)
      if [[ $saw_remote == false ]]; then
        saw_remote=true # first positional is the remote
        push_remote=$tok
      else
        saw_refspec=true
        refspecs+=("$tok")
        ref=${tok#+}                 # strip force '+'
        src=${ref%%:*} dst=${ref#*:} # split a src:dst refspec
        if [[ $src == *[~^*]* ]]; then
          tag_only=false # peeled/globbed source may resolve to a branch tip
        elif [[ $ref == *:* && $dst != refs/tags/* ]]; then
          tag_only=false # destination must be a tag (also covers deletions)
        elif [[ -z $src ]]; then
          :
        elif [[ $src != refs/tags/* ]] && ! is_tag "$src"; then
          tag_only=false # branch or unknown ref
        fi
      fi
      ;;
    esac
  done
  if [[ $carries_commits == false && $saw_refspec == true && $tag_only == true &&
    $other_gated == false ]]; then
    exit 0
  fi
fi

branch=$(git -C "$target" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
[[ -n $branch ]] || exit 0

safe=${branch//\//%2F}
[[ -f "${TMPDIR:-/tmp}/claude-deslop/$session/$safe" ]] && exit 0

# The per-branch sentinel is only recorded for worktrees of the session cwd's
# repo (deslop-mark). A push from a *different* repo's worktree can never match
# it, so fall back to the session-level marker: if deslop ran at all this
# session and the push targets a different repo than the session cwd, allow it.
# Same-repo pushes keep the strict per-branch requirement above.
git_common() { git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null; }
if [[ -f "${TMPDIR:-/tmp}/claude-deslop/$session/.ran" && -n $(git_common "$target") && $(git_common "$target") != "$(git_common "$cwd")" ]]; then
  exit 0
fi

# A branch whose diff against its deslop base touches only non-source files has
# nothing for the skill to review, so the gate doesn't apply. The base mirrors
# the skill's own resolution (@{push}, @{upstream}, else merge-base main HEAD);
# it's captured under `if !` so a failing rev-parse can't trip `set -e` into a
# non-blocking hook error — which would fail open.
deslop_base() {
  git -C "$target" rev-parse --verify --quiet '@{push}' ||
    git -C "$target" rev-parse --verify --quiet '@{upstream}' ||
    git -C "$target" merge-base main HEAD
}

is_nonsource_path() {
  case $1 in
  *.json | *.lock | *.lockb | *.lock.toml | *.md | \
    *.yaml | *.yml | *.png | *.jpg | *.jpeg | *.gif | *.svg | *.webp | *.ico | \
    docs/*) return 0 ;;
  esac
  return 1
}

if ! base=$(deslop_base 2>/dev/null); then
  : # unresolvable base → today's deny
else
  # Nothing ahead of upstream (e.g. a branch merely behind it) leaves nothing to
  # review. Only for a push of the current branch to its own upstream: `gh pr
  # create` and pushes to another destination still need the gate.
  if [[ $is_push == true && $any_gh == false ]] &&
    { git -C "$target" rev-parse --verify --quiet '@{push}' ||
      git -C "$target" rev-parse --verify --quiet '@{upstream}'; } >/dev/null 2>&1 &&
    [[ $(git -C "$target" rev-list --count "$base"..HEAD 2>/dev/null) == 0 ]]; then
    to_upstream=true
    upstream_remote=$(git -C "$target" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)
    upstream_remote=${upstream_remote%%/*}
    [[ -z $push_remote || $push_remote == "$upstream_remote" ]] || to_upstream=false
    for r in "${refspecs[@]}"; do
      [[ $r == "$branch" || $r == HEAD ]] || to_upstream=false
    done
    [[ $carries_commits == false && $other_gated == false ]] || to_upstream=false
    [[ $to_upstream == true ]] && exit 0
  fi
  # Diff only the commits being pushed, not upstream's side of a diverged history.
  base=$(git -C "$target" merge-base "$base" HEAD 2>/dev/null || printf '%s' "$base")
  nonsource_only=true
  changed=0
  paths_left=0
  # `--name-status -z` emits a status token then one path (two for R/C), so a
  # source path removed by a rename is still judged.
  while IFS= read -r -d '' tok; do
    if ((paths_left > 0)); then
      paths_left=$((paths_left - 1))
      changed=$((changed + 1))
      if ! is_nonsource_path "$tok"; then
        nonsource_only=false
      fi
    elif [[ $tok =~ ^[A-Z][0-9]*$ ]]; then
      case $tok in
      R* | C*) paths_left=2 ;;
      *) paths_left=1 ;;
      esac
    fi
  done < <(git -C "$target" diff -z --name-status "$base"..HEAD 2>/dev/null)
  if ((changed > 0)) && [[ $nonsource_only == true ]]; then
    exit 0
  fi
fi

jq -n --arg branch "$branch" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("Run the deslop skill on this branch (\($branch)) before pushing or opening a PR. Invoke the /deslop skill, commit the cleanup, then retry. Set ALLOW_PUSH_WITHOUT_DESLOP=1 to bypass.")
  }
}'

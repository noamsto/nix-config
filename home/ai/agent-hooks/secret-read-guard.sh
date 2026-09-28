#!/usr/bin/env bash
# PreToolUse hook: stop an agent printing a secret into its own transcript.
#
# Three real incidents, none of them careless: a malformed ${VAR:-default}
# expansion echoed an API key, a read-only reviewer subagent grepped .env to
# ground its review, and `fish -ic 'set -S LINEAR_API_KEY' | grep -v -i value`
# printed the key on a `$NAME[1]: |…|` line the grep never touched. All three
# landed a live value in a transcript, forcing a credential rotation. `.env`
# here holds resolved op:// values in plaintext and agents are told to read
# the repo, so "check the key is set" reaches for it by instinct. Guidance
# cannot fix an instinct; a guard can.
#
# Blocks the printing paths only. Writing, testing existence, ignoring, and
# deleting stay allowed, because update-env, direnv, and `test -f .env` are
# ordinary work. Fires for Bash, Read and Grep; abstains on everything else.

set -euo pipefail

# Byte semantics: every delimiter this guard cares about is ASCII, and the
# character-by-character scanners below are quadratic in a UTF-8 locale (each
# ${s:i:1} walks from the start) — 3-4x slower on a 10KB command, close to the
# hook's 4s budget, and an overrun abstains.
export LC_ALL=C

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
[[ -n $tool_name ]] || exit 0

# Files whose whole content is credentials. Kept narrow on purpose: a broad
# pattern that catches `.env.example` (a committed template of op:// refs, not
# secrets) would train people to work around the guard.
secret_path_re='(^|/)\.env($|\.[A-Za-z0-9_-]+$)|(^|/)\.envrc\.local$|\.aws/credentials|(^|/)\.netrc$|(^|/)id_(rsa|ed25519|ecdsa)$|\.pem$|\.p12$|\.pfx$'
# Grep globs spell the same files by pattern (`.env*`, `.env.*`, `*.env`), so
# they get this looser test on top of secret_path_re.
glob_secret_re='(^|[/*{,[])\.env($|[]*.?,}])|\.(pem|p12|pfx)($|[]*?,}])|\.netrc($|[]*?,}])|id_(rsa|ed25519|ecdsa)($|[]*?,}])|\.aws(/|$)'
# On a command line the same path is preceded by a space, quote, = or /, and
# followed by whitespace, a redirect or a pipe — never by a line anchor. Reusing
# the path-anchored pattern above here silently matches nothing, which is a
# guard that looks installed and blocks the exact case it was written for.
cmd_secret_re='(^|[[:space:]"'"'"'=/])\.env([[:space:]"'"'"';|&)>]|$|\.[A-Za-z0-9_-]+)|\.aws/credentials|(^|[[:space:]])\.netrc([[:space:]]|$)|id_(rsa|ed25519|ecdsa)([[:space:]]|$)|\.(pem|p12|pfx)([[:space:]]|$)'
# `.env.example` and `.env.template` are committed templates of op:// refs, not
# resolved values. Blocking them would teach people to route around the guard.
template_re='\.env\.(example|template|sample|dist)'

# Command-position anchor for the env, builtin and fish checks below: start of
# a line (after any indentation, so an indented body counts), or after
# ; && || | ( ) — never a bare mid-argument character. `)` covers a case
# pattern like `*)env`. After the separator, any chain of lead words still
# counts as command position: reserved words, `{`, `!`, env assignments, and
# prefix commands (sudo exec time nice xargs nohup setsid doas builtin eval,
# with their option flags and the value of -u/-g/-a/-U/-I; `command` only with
# -p or --, so `command -v env` stays allowed). Anchoring to the separator is
# what keeps `echo then env` allowed; the dumper regexes still require the
# dumper to END the command — now widened to also accept a following redirect
# (`>`, `<`, `2>&1`, …) or an unquoted `#` comment, not just a separator or
# end-of-line — which keeps `sudo env VAR=x cmd` and `xargs env cmd` allowed.
# Matching is per line (grep runs line by line), so a
# wrapped commit-body line inside a quoted string that is only lead words plus a
# dumper word (`if set`), a `\`-continuation line, or a line starting with a
# quoted/expanded word before a dumper argument also counts as command position:
# accepted false positives, on the safe side. Not followed (accepted limits):
# flags with other non-numeric values, `timeout N env`, stdbuf/ionice/`env FOO=1
# env` wrappers, `{env` without a space. A redirect or numbered fd right after
# the dumper word now also ends it, even when a command follows the redirect
# (`env >/dev/null cmd`, `env 2>/dev/null FOO=1 make` are denied, though `env`
# there still just runs `cmd` — an accepted false positive, on the safe side).
# Every dumper is matched only here,
# against text with quoted spans already replaced by spaces (mask_quotes), which
# is what lets
# `rg 'env|printenv|x' file` stay allowed (the literal `|` next to the word,
# inside the quotes, used to look like a real pipe) while `env` on its own is
# still denied. A trailing unquoted `$(...)`/`(...)` before a bare dumper word
# (`echo $(pwd) env`) is an accepted rare false positive, on the safe side.
# The body of every `$(...)`/backtick substitution — quoted or not, nested or
# not — is also scanned as its own command string (collect_substs, below), so
# `echo "$(env)"` is denied while `echo '$(env)'` and `echo "$(pwd) env"` are
# not. Accepted limits: a `)` inside a `case` pattern ends the body early
# (`$(case x in a) env;; esac)`), fish `(...)` substitutions are not collected,
# substitutions found in a `fish -c` body are checked for bash dumpers only,
# `$'...\'...'` is read as a plain single-quoted string, and two heredocs on
# one line track only the first delimiter, so the second body is read as shell
# code. Heredoc bodies (strip_heredocs) are text, not code: they never reach
# mask_quotes, so an apostrophe in one cannot hide a later line, and a bare
# `env` line inside one is allowed; only the substitutions in an unquoted one, or
# the whole body of one whose marker line feeds anything but a known text sink
# (`bash <<'EOF'`, `ssh h <<EOF`, `cat <<EOF | sh`), are scanned. Comments
# (comment_at) are skipped by the substitution scanners and quote-neutralized,
# not blanked, by mask_quotes; a nested `${a:-${b} #c}` is treated as one. An
# unclosed `${` earlier on the same line (even inside quotes, e.g. `'${' # it's`)
# disables comment recognition for the rest of that line. Comment text is still scanned as ordinary text, so a
# comment holding a separator before a dumper (`# run: a; env`) is denied
# (safe-side false positive).
cmd_sep='(^[[:space:]]*|[;&|()]+[[:space:]]*)'
cmd_lead_res='((then|do|else|elif|if|while|until|!|[{])[[:space:]]+)'
cmd_lead_asg='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)'
cmd_lead_opt='(-[ugaUI][[:space:]]+[^-0-9[:space:]][^[:space:]]*[[:space:]]+|-[^[:space:]]+[[:space:]]+([0-9]+[[:space:]]+)?)*'
cmd_lead_pfx='((sudo|exec|time|nice|xargs|nohup|setsid|doas|builtin|eval)[[:space:]]+'"$cmd_lead_opt"'|command[[:space:]]+((-p|--)[[:space:]]+)*)'
cmd_start="$cmd_sep($cmd_lead_res|$cmd_lead_asg|$cmd_lead_pfx)*"
# External dumper binaries (env, printenv, tmux, systemctl, launchctl) can be
# invoked by an absolute or relative path, not just the bare word — a shell
# builtin (set, declare, export, typeset) never has a path in front of it, so
# this prefix is only spliced into the external-binary alternatives below.
path_pfx='([^[:space:];&|()]*/)?'
# Terminator classes shared by the three dump regexes below: does the dumper
# word end the command, where "end" now also covers a redirect or an unquoted
# comment, not only a separator/end-of-line. `term_bare` skips trailing
# whitespace before checking — used where a following name changes the
# verdict (bare `env`/`printenv`, bare `set`, `declare -x` with no name): it
# accepts a redirect char (`<`/`>`, which covers `>>`/`>|`/`&>` since only the
# first char must match), a numbered fd redirect (`2>&1` — digits directly
# followed by `<`/`>`), a named-fd redirect (`{fd}>&2`, bash ≥4.1 — a brace
# identifier directly followed by `<`/`>`, which dumps exactly like the
# numbered form), or a `#` comment (requires at least one preceding space,
# matching bash's own comment-start rule, so `env#x` stays one word, not a
# dumper plus a comment). `term_imm` checks only the very next character —
# used where the form always dumps regardless of a trailing name (`-S`/
# `--show`/`-p`, `show-environment`, `getenv`): a bare space already satisfies
# it unconditionally, so only `<`/`>` need adding, for the no-space case
# (`declare -p>f`).
term_bare='([[:space:]]*($|[;&|)<>])|[[:space:]]*[0-9]+[<>]|[[:space:]]*\{[A-Za-z_][A-Za-z0-9_]*\}[<>]|[[:space:]]+#)'
term_imm='([[:space:]]|$|[;&|)<>])'
# `-0`/`--null` NUL-separate the output instead of newline-separating it, but
# every variable still comes out — still a dump, unlike `-i`/`FOO=1`/`-u NAME`,
# which change what env runs rather than how it prints.
env_dump_re="$cmd_start$path_pfx"'(printenv|env)([[:space:]]+(-0|--null))?'"$term_bare"
# Listing/show forms that print a variable's value without echoing it — the
# gap behind the LINEAR_API_KEY rotation. `-S`/`--show`/`-p` always print,
# with or without a name, so those ignore whatever follows; the rest only
# dump when bare (no name), matching real shell semantics: `declare -x
# NAME=value` just marks NAME for export and prints nothing.
builtin_dump_re="$cmd_start"'(set([[:space:]]+(-S|--show)'"$term_imm"'|'"$term_bare"')|declare[[:space:]]+-p'"$term_imm"'|declare[[:space:]]+-x'"$term_bare"'|export[[:space:]]+-p'"$term_imm"'|typeset[[:space:]]+-p'"$term_imm"'|'"$path_pfx"'tmux[[:space:]]+show-environment'"$term_imm"'|'"$path_pfx"'systemctl([[:space:]]+--user)?[[:space:]]+show-environment'"$term_imm"'|'"$path_pfx"'launchctl[[:space:]]+getenv'"$term_imm"')'
# fish's `-x`/`-gx`/`-U` mean export/universal scope, not bash's xtrace: bare
# (no name) they list that scope's variables, same as `-S`; WITH a name
# they're the ordinary `set -gx PATH …` assignment idiom. Checked only inside
# a confirmed `fish -c`/`fish -ic` body (see shell_c_re below), never at top
# level or inside a bash/sh/zsh -c: bash's own `set -x` there is the
# ubiquitous, harmless xtrace toggle, and `-gx`/`-U` aren't even valid bash
# flags for set.
fish_dump_re="$cmd_start"'set[[:space:]]+(-x|-gx|-U)'"$term_bare"
# A `fish -c`/`bash -c`/`sh -c`/`zsh -c` argument is quoted, so mask_quotes
# alone would erase a dumper hiding inside it even though the shell actually
# runs it — pull it out with decode_word (below) and test it as its own
# command string, recursing to catch nesting (`bash -c "fish -c '...'"`,
# arbitrarily deep) rather than a single fixed level.
#
# This only locates *where* the argument starts — through the interpreter,
# its flags, and the trailing whitespace — it does not capture the
# argument's quoted content itself; decode_word does that.
#
# The final flag is `-[A-Za-z]*c`, not a literal `-c`, so a combined flag
# cluster like `-ic` (interactive + command, as in `fish -ic '...'`) or
# `-lc`/`-ec` still matches. The leading anchor also allows `/` and `(`
# ahead of the shell name, for `/usr/bin/fish -c '...'` and `(bash -c
# '...')`, and `;`/`&`/`|`/`)` for a compact one-liner or sibling -c
# invocation with no space before the wrapper (`true;bash -c '...'`,
# `x&&bash -c '...'`, `echo x|bash -c '...'`).
shell_c_re="(^|[[:space:]/(;&|)])(fish|bash|sh|zsh)[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*c[[:space:]]+"
# /proc/<pid>/environ is a process's whole environment, NUL-joined — reading
# it any way (cat, a redirect, tr/xargs/sort splitting the NUL bytes, …) is
# exactly as much a dump as env/printenv, so this denies unconditionally
# rather than gating on a printing-tool list the way rule 3 does for .env:
# there's no non-printing reason to open this path. Checked against the raw
# command, not the quote-masked spaces — the path itself is what's dangerous,
# with or without quotes around it, so it also catches `fish -c 'cat
# /proc/1/environ'` without needing the -c extraction above.
proc_environ_re="(^|[[:space:]\"'<=])/proc/[^[:space:]\"']*/environ"
# A single backslash, spelled this way (rather than the bare '\' shellcheck
# flags as SC1003, a likely quote-escaping mistake) so mask_quotes and
# decode_word below can compare against it unambiguously.
bs=$'\\'

# Succeeds, setting COMMENT_END to the index of the newline ending the comment
# (or the string length), iff s[i] starts a shell comment: an unquoted `#` at a
# word start. Deliberately not a comment: `#` after `)`, `<`, `>` (`$(x)#y`,
# `<#`) or after a backslash-escaped char, and `#` inside an open `${` (`${#a}`,
# `${x:- #$(cmd)}`), where substitutions still run. Callers pass only unquoted
# positions and call it from `if` conditions (a failing return would trip set -e).
comment_at() {
  local s=$1 i=$2 pre rest
  if ((i > 0)); then
    case ${s:i-1:1} in
    ' ' | $'\t' | $'\n' | ';' | '&' | '|' | '(') ;;
    *) return 1 ;;
    esac
    if ((i > 1)) && [[ ${s:i-2:1} == "$bs" ]]; then return 1; fi
  fi
  pre=${s:0:i}
  rest=${pre%\$\{*}
  if [[ $rest != "$pre" ]]; then
    rest=${pre:${#rest}}
    if [[ $rest != *'}'* && $rest != *$'\n'* ]]; then return 1; fi
  fi
  rest=${s:i}
  rest=${rest%%$'\n'*}
  COMMENT_END=$((i + ${#rest}))
}

# Replaces every character inside a '...' or "..." span (quotes included)
# with a space, so quoted data can never look like a command. Positional, not
# a strip, so a caller that only needs one span (decode_word, below) can pull
# the original quoted text out first and mask *that* on its own. Command
# substitutions inside a span are blanked with it and scanned separately
# (collect_substs). A span ends at the first unescaped quote of its kind, so a
# nested `"$(echo "x")"` masks in pieces and the inner quoted text can land
# bare at command position (accepted false positive).
#
# Backslash-aware on both sides of the quote boundary, matching real bash:
# outside any quote, `\X` is a literal X with no special meaning, so `\"`/
# `\'` there is not a quote-open. Inside `"..."`, only \$, \`, \", \\ and
# \<newline> are real escapes, so a bare `\"` doesn't close the span either.
# Single quotes have no escape mechanism in bash, so no such handling inside
# them — a `\` there is just another masked character.
#
# A comment (comment_at) is not blanked: an apostrophe in `# what's set` would
# open a phantom quote and hide the next line, but blanking the text instead
# would let a false comment start hide a real dumper. So it is copied verbatim
# with only its quote characters turned into spaces.
mask_quotes() {
  local s=$1 out='' i=0 c q seg
  local len=${#s}
  while ((i < len)); do
    c=${s:i:1}
    if [[ $c == "$bs" ]] && ((i + 1 < len)); then
      out+=$c
      out+=${s:i+1:1}
      i=$((i + 2))
    elif [[ $c == '#' ]] && comment_at "$s" "$i"; then
      seg=${s:i:COMMENT_END-i}
      seg=${seg//\'/ }
      out+=${seg//\"/ }
      i=$COMMENT_END
    elif [[ $c == "'" || $c == '"' ]]; then
      q=$c
      out+=' '
      i=$((i + 1))
      while ((i < len)) && [[ ${s:i:1} != "$q" ]]; do
        if [[ $q == '"' && ${s:i:1} == "$bs" ]] && ((i + 1 < len)); then
          out+='  '
          i=$((i + 2))
        else
          out+=' '
          i=$((i + 1))
        fi
      done
      if ((i < len)); then
        out+=' '
        i=$((i + 1))
      fi
    else
      out+=$c
      i=$((i + 1))
    fi
  done
  printf '%s' "$out"
}

# Extracts one shell WORD starting at index `start` of `s` (the caller has
# already skipped any leading whitespace): concatenated unquoted/single-
# quoted/double-quoted/ANSI-C-quoted segments with bash's own quote-removal
# already applied, stopping at the first unquoted, unescaped word terminator
# or end of string — e.g. `bash -c 'echo '\''hi'\''; env'` is, to bash, ONE
# argument built from three concatenated quoted/escaped fragments.
#
# No variable/command substitution or expansion is attempted: none of that
# affects where a word or a `-c` argument's boundary falls, which is all this
# guard needs — the decoded text is only ever fed back into mask_quotes and
# the dumper regexes as a new candidate command string, never executed.
#
# Sets DECODED_WORD (the decoded value) and DECODE_WORD_END (the index in
# `s` one past the last character consumed) rather than printing, so the
# caller can keep scanning `s` past this word for a SIBLING invocation —
# `bash -c 'true' ; bash -c 'declare -p NAME'` is two separate `-c` bodies at
# the same level, not one nested inside the other, and a caller that only
# ever recurses into the extracted word (discarding everything after it)
# never looks at the second one. A `$(...)` command-substitution return here
# would run in a subshell and lose that second value silently.
decode_word() {
  local s=$1 i=$2 out='' c
  local len=${#s}
  while ((i < len)); do
    c=${s:i:1}
    case $c in
    ' ' | $'\t' | $'\n' | ';' | '&' | '|' | '(' | ')')
      # An unquoted newline separates statements exactly like `;` — an
      # ordinary multi-line command, not just a semicolon-joined one-liner.
      break
      ;;
    "$bs")
      i=$((i + 1))
      if ((i < len)); then
        out+=${s:i:1}
        i=$((i + 1))
      fi
      ;;
    '$')
      # $'...' (ANSI-C quoting) is an ordinary way to embed \n/\t in a -c
      # body. The leading $ must be dropped here, not kept, or it survives
      # into the decoded text and breaks the dumper regexes' command-
      # position anchor below.
      if [[ ${s:i+1:1} == "'" ]]; then
        i=$((i + 2))
        while ((i < len)) && [[ ${s:i:1} != "'" ]]; do
          if [[ ${s:i:1} == "$bs" ]] && ((i + 1 < len)); then
            out+=${s:i+1:1}
            i=$((i + 2))
          else
            out+=${s:i:1}
            i=$((i + 1))
          fi
        done
        ((i < len)) && i=$((i + 1))
      else
        out+=$c
        i=$((i + 1))
      fi
      ;;
    "'")
      i=$((i + 1))
      while ((i < len)) && [[ ${s:i:1} != "'" ]]; do
        out+=${s:i:1}
        i=$((i + 1))
      done
      ((i < len)) && i=$((i + 1))
      ;;
    '"')
      i=$((i + 1))
      while ((i < len)) && [[ ${s:i:1} != '"' ]]; do
        if [[ ${s:i:1} == "$bs" ]] && ((i + 1 < len)); then
          out+=${s:i+1:1}
          i=$((i + 2))
        else
          out+=${s:i:1}
          i=$((i + 1))
        fi
      done
      ((i < len)) && i=$((i + 1))
      ;;
    *)
      out+=$c
      i=$((i + 1))
      ;;
    esac
  done
  DECODED_WORD=$out
  DECODE_WORD_END=$i
}

# True iff a heredoc whose `<<` sits on `line` feeds something that may run its
# body as code. Only a marker line whose every pipeline stage is a known text
# sink (cat, tee, git commit -F -, gh --body-file -, ...) is text; any other
# command — a shell, ssh, `source /dev/stdin`, `eval`, `while read`, an unknown
# tool — is treated as running it, so an unrecognised consumer errs toward
# scanning. Quote characters are blanked and `$(`/backticks/`(` split stages, so
# `x="$(cat <<'EOF'` is judged by its `cat`.
heredoc_is_code() {
  local l=${1//[\'\"]/ } seg w t=${1%"${1##*[![:space:]]}"}
  # A trailing `|`/`&` continues the pipeline on the line after the terminator.
  if [[ $t == *[\|\&] ]]; then return 0; fi
  l=${l//\$\(/;}
  l=${l//\`/;}
  l=${l//[;&|(]/$'\n'}
  # Capturing the tail after a repeated group strips every leading token in
  # one pass; stripping one token per loop iteration is quadratic and can
  # overrun the hook's time budget.
  local lead_re='^(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|sudo|time|nice|nohup|exec|command|then|do|else|!|\{)[[:space:]]+)*(.*)$'
  while IFS= read -r seg; do
    seg=${seg#"${seg%%[![:space:]]*}"}
    [[ $seg =~ $lead_re ]] && seg=${BASH_REMATCH[3]}
    w=${seg%%[[:space:]<>]*}
    w=${w##*/}
    case $w in
    '')
      # A redirection before the command word (`<<EOF bash`) hides it.
      if [[ -n ${seg//[[:space:]]/} ]]; then return 0; fi
      ;;
    [A-Za-z_]*=*) ;;
    git)
      # `git -c alias.x=!sh x` runs stdin as a script.
      if [[ $seg =~ [[:space:]]-c[[:space:]] ]]; then return 0; fi
      ;;
    cat | tee | printf | echo | gh | patch | sponge | sort | tr | wc | head | tail | grep | rg | jq | base64 | curl | diff | cmp | read | mapfile | readarray) ;;
    *) return 0 ;;
    esac
  done <<<"$l"
  return 1
}

# Splits heredoc bodies out of a command, line by line, so an apostrophe or `#`
# in a body can never desync mask_quotes or the substitution scanners. Sets
# HD_VIEW to the command with every body removed (the `<<` line and the
# delimiter line stay): a body is text for the heredoc's command, not shell
# code, so the dumper regexes must not see it. Bodies of unquoted-delimiter
# heredocs (<<EOF) land in HD_PLAIN, because `$(...)` and backticks still run
# in them; quoted ones (<<'EOF', <<"EOF", <<\EOF) substitute nothing and are
# dropped, which is what lets the `git commit -m "$(cat <<'EOF' ... EOF)"` idiom
# carry prose full of backticks and apostrophes. When the marker line does not
# feed a known text sink (heredoc_is_code) the body may be code, so it also
# lands in HD_CODE for the caller to scan as a command string. A `<<` inside a
# quoted string or after a `#` comment start is not a heredoc (checked on the
# quote-masked line). A heredoc whose delimiter line never appears is not one —
# `$((1<<n))`, a `<<EOF` inside a multi-line string, `<<A.B` — so its lines are
# put back into the view instead of hiding the rest of the command. Accepted
# limits: only the first heredoc marker on a line is recognised, and a body
# only reaches a shell through its marker line (`cat <<'EOF' > s.sh` then
# `bash s.sh`, or `s=$(cat <<'EOF' ...)` then `eval "$s"`, is not followed). A
# marker line ending in `\`, or following one that does, or whose delimiter is
# not a plain word, or a `<<` after `\` or inside `((`, is not treated as a
# heredoc, leaving its body visible; so is one ending in `|` or `&`, whose
# consumer is on a later line. A `<<` on a line inside a quoted string that
# opened on an earlier line is still read as a marker (the quote-masking is per
# line), which hides the lines up to a matching terminator.
strip_heredocs() {
  local s=$1 out='' line cmp delim='' dash=0 quoted=0 code=0 pre at lead rest masked_line body='' cont=0
  local hd_re="(^|[^<])<<(-?)[[:space:]]*('([^']+)'|\"([^\"]+)\"|[$bs]([A-Za-z0-9_]+)|([A-Za-z_][A-Za-z0-9_]*))"
  local delim_end_re='^[[:space:];&|<>()]'
  local tab_strip_re=$'^\t*(.*)$'
  HD_PLAIN=()
  HD_CODE=()
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ -n $delim ]]; then
      cmp=$line
      if ((dash)); then
        # A per-tab strip loop, and bash's own `${cmp%%[!\t]*}` glob match,
        # are both quadratic here; the regex quantifier is linear.
        [[ $cmp =~ $tab_strip_re ]] && cmp=${BASH_REMATCH[1]}
      fi
      if [[ $cmp == "$delim" ]]; then
        out+=$line$'\n'
        if ((! quoted)); then HD_PLAIN+=("$body"); fi
        if ((code)); then HD_CODE+=("$body"); fi
        delim=''
        body=''
      else
        body+=$line$'\n'
      fi
      continue
    fi
    out+=$line$'\n'
    # Past scan_budget the caller denies whatever follows, and a long marker line
    # is scanned character by character below.
    if ((${#out} > scan_budget)); then break; fi
    if [[ $line =~ $hd_re ]] && ((! cont)); then
      delim=${BASH_REMATCH[4]}${BASH_REMATCH[5]}${BASH_REMATCH[6]}${BASH_REMATCH[7]}
      quoted=1
      if [[ -n ${BASH_REMATCH[7]} ]]; then quoted=0; fi
      dash=0
      if [[ ${BASH_REMATCH[2]} == - ]]; then dash=1; fi
      lead=${BASH_REMATCH[1]}
      rest=${line#*"${BASH_REMATCH[0]}"}
      pre=${line%%"${BASH_REMATCH[0]}"*}
      at=$((${#pre} + ${#lead}))
      # The regex stops at the first non-word character, but bash takes the whole
      # word (`EOF-x`, `E'O'F`), so a longer delimiter would end the body at the
      # wrong line and swallow real code after it.
      if [[ -n $rest && ! $rest =~ $delim_end_re ]]; then delim=''; fi
      # `\<<A` is a literal `<` and a file redirect, `((1<<n))` a shift.
      if [[ $lead == "$bs" || ${line:0:at} == *'(('* ]]; then delim=''; fi
      masked_line=$(mask_quotes "$line")
      # `"$(cat <<'EOF'` opens its quote on the same line, so mask_quotes
      # blanks the `<<`: a `$(` or backtick before it restarts quote context.
      if [[ ${masked_line:0:at} =~ (^|[[:space:]])# ]] ||
        [[ ${masked_line:at:2} != '<<' && ${line:0:at} != *'$'\(* && ${line:0:at} != *'`'* ]]; then
        delim=''
      fi
      code=0
      if [[ -n $delim ]] && heredoc_is_code "$line"; then code=1; fi
      if [[ $line == *"$bs" ]]; then delim=''; fi
    fi
    cont=0
    if [[ $line == *"$bs" ]]; then cont=1; fi
  done <<<"$s"
  if [[ -n $delim ]]; then out+=$body; fi
  HD_VIEW=$out
}

# Index of the backtick closing the span opened at s[i], or the string length
# when it never closes. Sets BT_END.
skip_backtick() {
  local s=$1 i=$(($2 + 1))
  local len=${#s}
  while ((i < len)) && [[ ${s:i:1} != '`' ]]; do
    if [[ ${s:i:1} == "$bs" ]]; then i=$((i + 2)); else i=$((i + 1)); fi
  done
  if ((i > len)); then i=$len; fi
  BT_END=$i
}

# Index of the `)` matching a `$(` whose body starts at s[i], or the string
# length when unbalanced (the rest of the string is then the body: scanning
# more errs toward denying, and the scan still terminates). A stack of
# contexts — P paren, D double quote, S single quote — because `$(` opens an
# independent quoting context even inside "...": `"$(echo "$(env)")"` nests.
# Sets FPE_END.
find_paren_end() {
  local s=$1 i=$2
  local len=${#s} c top
  local st=(P) sp=1
  while ((i < len)); do
    c=${s:i:1}
    top=${st[sp - 1]}
    if [[ $top == S ]]; then
      if [[ $c == "'" ]]; then sp=$((sp - 1)); fi
    elif [[ $c == "$bs" ]]; then
      i=$((i + 1))
    elif [[ $c == '`' ]]; then
      skip_backtick "$s" "$i"
      i=$BT_END
    elif [[ $top == D ]]; then
      if [[ $c == '"' ]]; then
        sp=$((sp - 1))
      elif [[ $c == '$' && ${s:i+1:1} == '(' ]]; then
        st[sp]=P
        sp=$((sp + 1))
        i=$((i + 1))
      fi
    else
      case $c in
      '#')
        if comment_at "$s" "$i"; then i=$COMMENT_END; fi
        ;;
      "'")
        st[sp]=S
        sp=$((sp + 1))
        ;;
      '"')
        st[sp]=D
        sp=$((sp + 1))
        ;;
      '(')
        st[sp]=P
        sp=$((sp + 1))
        ;;
      ')')
        sp=$((sp - 1))
        if ((sp == 0)); then
          FPE_END=$i
          return
        fi
        ;;
      esac
    fi
    i=$((i + 1))
  done
  FPE_END=$len
}

# Appends to SUBST_BODIES the body of every top-level command substitution in
# s — `$(...)` and backticks, outside '...' and inside or outside "..." — each
# as the shell would run it. mask_quotes blanks a whole "..." span, so without
# this a dumper inside one is invisible. With plain=1 (a heredoc body) quotes
# and `#` are literal text, so only `$(`, backticks and backslashes matter.
# Unbalanced input takes the rest of the string as the body.
scan_substs() {
  local s=$1 plain=$2 i=0 len c dq=0 body out n
  len=${#s}
  while ((i < len)); do
    c=${s:i:1}
    if [[ $c == "$bs" ]]; then
      i=$((i + 2))
    elif [[ $c == '`' ]]; then
      skip_backtick "$s" "$i"
      body=${s:i+1:BT_END-i-1}
      out=''
      n=0
      while ((n < ${#body})); do
        if [[ ${body:n:1} == "$bs" ]]; then
          case ${body:n+1:1} in
          "$bs" | '`' | '$') n=$((n + 1)) ;;
          '"') if ((dq)); then n=$((n + 1)); fi ;;
          esac
        fi
        out+=${body:n:1}
        n=$((n + 1))
      done
      SUBST_BODIES+=("$out")
      i=$((BT_END + 1))
    elif [[ $c == '$' && ${s:i+1:1} == '(' ]]; then
      find_paren_end "$s" $((i + 2))
      SUBST_BODIES+=("${s:i+2:FPE_END-i-2}")
      i=$((FPE_END + 1))
    elif ((plain)); then
      i=$((i + 1))
    elif ((dq)); then
      if [[ $c == '"' ]]; then dq=0; fi
      i=$((i + 1))
    elif [[ $c == '#' ]] && comment_at "$s" "$i"; then
      i=$COMMENT_END
    elif [[ $c == "'" ]]; then
      i=$((i + 1))
      while ((i < len)) && [[ ${s:i:1} != "'" ]]; do i=$((i + 1)); done
      i=$((i + 1))
    else
      if [[ $c == '"' ]]; then dq=1; fi
      i=$((i + 1))
    fi
  done
}

# Sets SUBST_BODIES to everything in s worth scanning as a command string of
# its own: the substitutions of the heredoc-free view (HD_VIEW) plus those in
# each unquoted heredoc body, and the bodies of heredocs that may be code verbatim.
# Callers re-scan each as a command string, which is how nested substitutions
# (and `-c` bodies inside one) are reached. Must directly follow strip_heredocs
# on the same string: it reads HD_VIEW/HD_PLAIN/HD_CODE.
collect_substs() {
  local body
  local plain=("${HD_PLAIN[@]}")
  local code=("${HD_CODE[@]}")
  SUBST_BODIES=()
  scan_substs "$HD_VIEW" 0
  for body in "${plain[@]}"; do scan_substs "$body" 1; done
  SUBST_BODIES+=("${code[@]}")
}

# mask_quotes over a command's heredoc-free view: the text the dumper regexes
# may match against.
masked_view() {
  strip_heredocs "$1"
  mask_quotes "$HD_VIEW"
}

# The scanners above walk a string character by character, and each nested
# command substitution re-runs them over its whole body, so the work grows
# with (nesting depth x length) and a single long command is superlinear too.
# scan_budget caps the bytes they are asked to read across one command: the
# heredoc-free view plus unquoted heredoc bodies of the command itself (a
# quoted heredoc body is dropped whole and costs almost nothing), then each
# queued substitution or -c body in full, and strip_heredocs stops reading once
# its view passes the budget. max_command_len bounds the one thing that scan
# still reads whole, the body of a quoted heredoc. The hook has 4000ms and an
# overrun abstains, so a command past either ceiling is denied.
# Measured on the dev box (LC_ALL=C), at 16384 bytes: flat words ~0.6s, nested
# $(...) ~0.4s, a 12KB python heredoc ~0.5s, a 9KB unquoted heredoc ~0.1s, and
# 3000 heredoc markers ~0.7s; realistic commands sit far below both ceilings.
# Bytes are only a proxy: comment-dense text (comment_at copies the string per
# `#`) and a `<<-` line of thousands of tabs still cost more than their size
# and can pass 4s under the budget (#405, #407).
scan_budget=16384
max_command_len=524288
scanned=0

# Adds $1 bytes to scanned; succeeds when that puts the command past scan_budget.
over_scan_budget() {
  scanned=$((scanned + $1))
  ((scanned > scan_budget))
}

deny() {
  jq -n --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

case $tool_name in
Read)
  path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
  [[ -n $path ]] || exit 0
  [[ $path =~ $template_re ]] && exit 0
  [[ $path =~ $secret_path_re ]] || exit 0
  deny "Reading $path would print live credentials into this transcript, which costs a rotation. Nothing needs the value: the tool that consumes it reads the environment itself, and a missing key produces a clear error — run the tool and read that instead. To know a key is merely present without seeing it: grep -c '^NAME=' (count, not content)."
  ;;
Grep)
  pattern=$(echo "$input" | jq -r '.tool_input.pattern // empty')
  mode=$(echo "$input" | jq -r '.tool_input.output_mode // "files_with_matches"')
  # files_with_matches and count never emit file content.
  [[ $mode == "content" ]] || exit 0
  # secret_path_re is anchored, so path and glob are tested separately, never
  # joined. Template names are stripped rather than exempting the whole call, so
  # `{.env.example,.env}` still trips on its `.env`.
  grep_path=$(echo "$input" | jq -r '.tool_input.path // empty')
  grep_glob=$(echo "$input" | jq -r '.tool_input.glob // empty')
  path_left=$(sed -E "s/$template_re//g" <<<"$grep_path")
  glob_left=$(sed -E "s/$template_re//g" <<<"$grep_glob")
  # A glob names files by pattern, so `.env*`, `.env.*` and `*.env` are the
  # spellings that reach a real .env; `.envrc` is direnv config and stays out.
  if [[ $path_left =~ $secret_path_re ]]; then
    deny "Grepping $grep_path with output_mode=content would print credential lines into this transcript. Use output_mode=\"count\" to confirm a key exists, or run the consuming tool and read its error."
  fi
  if [[ $glob_left =~ $secret_path_re || $glob_left =~ $glob_secret_re ]]; then
    deny "Grepping with glob $grep_glob and output_mode=content would print credential lines into this transcript. Use output_mode=\"count\" to confirm a key exists, or run the consuming tool and read its error."
  fi
  # A secret-shaped pattern with content output leaks even when the path is broad.
  if [[ $pattern =~ (API_?KEY|SECRET|TOKEN|PASSWORD|CREDENTIAL|PRIVATE_KEY) ]]; then
    deny "Pattern '$pattern' with output_mode=content will print any matching credential line it finds. Use output_mode=\"files_with_matches\" or \"count\" — you need to know where a key is configured, not what it is."
  fi
  ;;
Bash)
  command=$(echo "$input" | jq -r '.tool_input.command // empty')
  [[ -n $command ]] || exit 0

  # 1. Expanding a secret-named variable into output. This is incident one:
  #    echo "${MISTRAL_API_KEY:-x}" prints the key. Catches the whole
  #    echo/printf family, including the malformed-default form.
  if echo "$command" | grep -qE '(echo|printf|print)\b[^|;&]*\$\{?[A-Za-z_]*(API_?KEY|SECRET|TOKEN|PASSWORD|PASSWD|CREDENTIAL|PRIVATE_KEY)[A-Za-z_]*'; then
    deny "This expands a secret-named variable into stdout, which writes the live value into this transcript (the exact shape that already forced one rotation). To test presence instead, branch on an -n test of the variable and echo only the words set or unset — never the variable itself."
  fi

  # 2. Dumping the whole environment, or listing/showing shell variables
  #    through set -S / declare -p / show-environment and friends — same
  #    leak, different command. Matched only at command position, against
  #    text with quoted spans masked out, so a quoted regex or string
  #    argument can never look like one of these.
  unverified=0
  masked=''
  if ((${#command} > max_command_len)); then
    unverified=1
  else
    strip_heredocs "$command"
    size=${#HD_VIEW}
    for body in "${HD_PLAIN[@]}"; do size=$((size + ${#body})); done
    if over_scan_budget "$size"; then
      unverified=1
    else
      masked=$(mask_quotes "$HD_VIEW")
    fi
  fi
  search_spaces=("$masked")
  fish_spaces=()
  # Recurse through nested -c wrapping (bash -c "fish -c '...'") and scan for
  # sibling -c invocations at the same level (bash -c 'true' ; bash -c
  # 'declare -p NAME' are two separate bodies). A worklist, not a single
  # variable: each match queues the extracted word plus the remainder of the
  # source string after it, so neither a nested nor a sibling body is ever
  # dropped. Command-substitution bodies ride the same worklist (the flag array
  # marks the items still worth scanning for them: not a -c remainder, whose
  # substitutions its source string already yielded), so a dumper inside
  # `$(...)` or backticks, nested or not, is tested at command position. Every
  # item is visited once and each queued item is shorter than its
  # source, so the loop terminates. 20 -c matches, 300 visited items and
  # scan_budget bytes are generous ceilings; a command past any cannot be
  # verified, so it is denied rather than left to abstain. A remainder is
  # scanned again in full, so it is charged along with the body it follows.
  worklist=("$command")
  collect_flags=(1)
  wi=0
  matches=0
  while ((! unverified && wi < ${#worklist[@]})) && ((wi < 300)); do
    strip_heredocs "${worklist[wi]}"
    cur=$HD_VIEW
    if ((collect_flags[wi])); then
      collect_substs
      for body in "${SUBST_BODIES[@]}"; do
        if ((${#worklist[@]} >= 300)) || over_scan_budget "${#body}"; then
          unverified=1
          break
        fi
        worklist+=("$body")
        collect_flags+=(1)
        search_spaces+=("$(masked_view "$body")")
      done
    fi
    wi=$((wi + 1))
    if ((matches >= 20)); then
      if [[ $cur =~ $shell_c_re ]]; then unverified=1; fi
      continue
    fi
    # shell_c_re's ;&|) anchors (see above) are as common inside an ordinary
    # quoted regex/string as a bare space already was, e.g. `rg 'foo|bash -c
    # env x' .`. So a match only counts if its full text (anchor through
    # trailing whitespace) falls outside any quoted span — checked against
    # the quote-masked form, which is length-preserving, so an index into
    # one applies to the other. A match that fails this is rejected and the
    # search resumes just past it, since $cur may still hold a real sibling
    # invocation later on.
    masked_cur=$(mask_quotes "$cur")
    search_from=0
    found=0
    while ((search_from <= ${#cur})); do
      candidate=${cur:search_from}
      [[ $candidate =~ $shell_c_re ]] || break
      match=${BASH_REMATCH[0]}
      interpreter=${BASH_REMATCH[2]}
      local_prefix=${candidate%%"$match"*}
      match_idx=$((search_from + ${#local_prefix}))
      if [[ ${masked_cur:match_idx:${#match}} != "${cur:match_idx:${#match}}" ]]; then
        search_from=$((match_idx + 1))
        continue
      fi
      arg_start=$((match_idx + ${#match}))
      found=1
      break
    done
    ((found)) || continue
    decode_word "$cur" "$arg_start"
    sub=$DECODED_WORD
    if over_scan_budget $((${#sub} + ${#cur} - DECODE_WORD_END)); then
      unverified=1
      continue
    fi
    masked_sub=$(masked_view "$sub")
    search_spaces+=("$masked_sub")
    [[ $interpreter == fish ]] && fish_spaces+=("$masked_sub")
    matches=$((matches + 1))
    worklist+=("$sub" "${cur:DECODE_WORD_END}")
    collect_flags+=(1 0)
  done
  if ((unverified || wi < ${#worklist[@]})); then
    deny "This command is too long, or nests too many substitutions or shell -c wrappers, for the secret-read guard to verify that none prints an environment dump. Split it into simpler commands, or move the logic into a script file."
  fi
  for space in "${search_spaces[@]}"; do
    if echo "$space" | grep -qE "$env_dump_re"; then
      deny "A bare env/printenv prints every secret in scope into this transcript. Name the one variable you need and test it without echoing its value."
    fi
    if echo "$space" | grep -qE "$builtin_dump_re"; then
      deny "This lists or shows shell variables, which prints live values into this transcript — the same leak as env/printenv, just through a different command (set -S, declare -p, show-environment, …). To test presence: set -q NAME (fish), or branch on an -n test of the variable and echo only the words set or unset (bash/sh) — never the variable itself."
    fi
  done
  for space in "${fish_spaces[@]}"; do
    if echo "$space" | grep -qE "$fish_dump_re"; then
      deny "set -x/-gx/-U with no name lists that scope's variables in fish, printing live values into this transcript — same leak as set -S. To test presence: set -q NAME."
    fi
  done

  # Reading a process's environment table directly is the same dump by
  # another door, unconditionally (no printing-tool gate — there's no
  # non-printing reason to open this path at all).
  if echo "$command" | grep -qE "$proc_environ_re"; then
    deny "This reads a process's environment table directly, which prints every secret in scope into this transcript — same leak as env/printenv, just via /proc instead. To test presence: set -q NAME (fish), or branch on an -n test of the variable and echo only the words set or unset (bash/sh) — never the variable itself."
  fi

  # 3. Reading a credential file's content. Non-printing inspection stays
  #    allowed: test, [, git check-ignore, ls, stat, wc, chmod, rm, gtrash,
  #    update-env, direnv — none of which emit the value.
  if echo "$command" | grep -qE "$cmd_secret_re" && ! echo "$command" | grep -qE "$template_re"; then
    if echo "$command" | grep -qE '\b(cat|bat|head|tail|less|more|strings|xxd|od|nl|tac|rev|cut|paste|sed|awk|dotenv|source)\b'; then
      deny "This prints credential-file content into the transcript. If you need to confirm a key is configured, use grep -c '^NAME=' (a count), or run the consuming tool and read its error — a missing key fails loudly and that failure is the signal."
    fi
    # grep/rg leak unless restricted to a non-printing mode.
    if echo "$command" | grep -qE '\b(grep|rg|ripgrep|ag)\b' && ! echo "$command" | grep -qE '(-[a-zA-Z]*[cqlL]|--count|--quiet|--silent|--files-with-matches|--files-without-match)\b'; then
      deny "grep/rg over a credential file prints the matching line, value included. Add -c (count) or -q (quiet) if you only need to know whether it is set."
    fi
  fi
  ;;
*)
  exit 0
  ;;
esac

exit 0

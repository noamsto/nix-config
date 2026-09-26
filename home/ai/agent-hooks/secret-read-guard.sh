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
# string, or after ; && || | ( ) — never a bare mid-argument character. `)`
# covers a case pattern like `*)env`. Every dumper is matched
# only here, against text with quoted spans already replaced by spaces
# (mask_quotes), which is what lets `rg 'env|printenv|x' file` stay allowed
# (the literal `|` next to the word, inside the quotes, used to look like a
# real pipe) while `env` on its own is still denied. A trailing unquoted
# `$(...)`/`(...)` before a bare dumper word (`echo $(pwd) env`) is an accepted
# rare false positive, on the safe side.
cmd_start='(^|[;&|()]+[[:space:]]*)'
env_dump_re="$cmd_start"'(printenv|env)[[:space:]]*($|[;&|)])'
# Listing/show forms that print a variable's value without echoing it — the
# gap behind the LINEAR_API_KEY rotation. `-S`/`--show`/`-p` always print,
# with or without a name, so those ignore whatever follows; the rest only
# dump when bare (no name), matching real shell semantics: `declare -x
# NAME=value` just marks NAME for export and prints nothing.
builtin_dump_re="$cmd_start"'(set([[:space:]]+(-S|--show)([[:space:]]|$|[;&|)])|[[:space:]]*($|[;&|)]))|declare[[:space:]]+-p([[:space:]]|$|[;&|)])|declare[[:space:]]+-x[[:space:]]*($|[;&|)])|export[[:space:]]+-p([[:space:]]|$|[;&|)])|typeset[[:space:]]+-p([[:space:]]|$|[;&|)])|tmux[[:space:]]+show-environment([[:space:]]|$|[;&|)])|systemctl([[:space:]]+--user)?[[:space:]]+show-environment([[:space:]]|$|[;&|)])|launchctl[[:space:]]+getenv([[:space:]]|$|[;&|)]))'
# fish's `-x`/`-gx`/`-U` mean export/universal scope, not bash's xtrace: bare
# (no name) they list that scope's variables, same as `-S`; WITH a name
# they're the ordinary `set -gx PATH …` assignment idiom. Checked only inside
# a confirmed `fish -c`/`fish -ic` body (see shell_c_re below), never at top
# level or inside a bash/sh/zsh -c: bash's own `set -x` there is the
# ubiquitous, harmless xtrace toggle, and `-gx`/`-U` aren't even valid bash
# flags for set.
fish_dump_re="$cmd_start"'set[[:space:]]+(-x|-gx|-U)[[:space:]]*($|[;&|)])'
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

# Replaces every character inside a '...' or "..." span (quotes included)
# with a space, so quoted data can never look like a command. Positional, not
# a strip, so a caller that only needs one span (decode_word, below) can pull
# the original quoted text out first and mask *that* on its own.
#
# Backslash-aware on both sides of the quote boundary, matching real bash:
# outside any quote, `\X` is a literal X with no special meaning, so `\"`/
# `\'` there is not a quote-open. Inside `"..."`, only \$, \`, \", \\ and
# \<newline> are real escapes, so a bare `\"` doesn't close the span either.
# Single quotes have no escape mechanism in bash, so no such handling inside
# them — a `\` there is just another masked character.
mask_quotes() {
  local s=$1 out='' i=0 c q
  local len=${#s}
  while ((i < len)); do
    c=${s:i:1}
    if [[ $c == "$bs" ]] && ((i + 1 < len)); then
      out+=$c
      out+=${s:i+1:1}
      i=$((i + 2))
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
  masked=$(mask_quotes "$command")
  search_spaces=("$masked")
  fish_spaces=()
  # Recurse through nested -c wrapping (bash -c "fish -c '...'") and scan for
  # sibling -c invocations at the same level (bash -c 'true' ; bash -c
  # 'declare -p NAME' are two separate bodies). A worklist, not a single
  # variable: each match queues the extracted word plus the remainder of the
  # source string after it, so neither a nested nor a sibling body is ever
  # dropped. Bounded by total matches rather than nesting depth — each match
  # queues at most 2 items and every item is visited once, so this always
  # terminates.
  worklist=("$command")
  wi=0
  matches=0
  while ((wi < ${#worklist[@]})) && ((matches < 20)); do
    cur=${worklist[wi]}
    wi=$((wi + 1))
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
    masked_sub=$(mask_quotes "$sub")
    search_spaces+=("$masked_sub")
    [[ $interpreter == fish ]] && fish_spaces+=("$masked_sub")
    matches=$((matches + 1))
    worklist+=("$sub" "${cur:DECODE_WORD_END}")
  done
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

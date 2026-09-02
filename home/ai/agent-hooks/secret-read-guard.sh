#!/usr/bin/env bash
# PreToolUse hook: stop an agent printing a secret into its own transcript.
#
# Two real incidents, neither one careless: a malformed ${VAR:-default}
# expansion echoed an API key, and a read-only reviewer subagent grepped .env
# to ground its review. Both landed the live value in a transcript, forcing a
# credential rotation. `.env` here holds resolved op:// values in plaintext and
# agents are told to read the repo, so "check the key is set" reaches for it by
# instinct. Guidance cannot fix an instinct; a guard can.
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
# On a command line the same path is preceded by a space, quote, = or /, and
# followed by whitespace, a redirect or a pipe — never by a line anchor. Reusing
# the path-anchored pattern above here silently matches nothing, which is a
# guard that looks installed and blocks the exact case it was written for.
cmd_secret_re='(^|[[:space:]"'"'"'=/])\.env([[:space:]"'"'"';|&)>]|$|\.[A-Za-z0-9_-]+)|\.aws/credentials|(^|[[:space:]])\.netrc([[:space:]]|$)|id_(rsa|ed25519|ecdsa)([[:space:]]|$)|\.(pem|p12|pfx)([[:space:]]|$)'
# `.env.example` and `.env.template` are committed templates of op:// refs, not
# resolved values. Blocking them would teach people to route around the guard.
template_re='\.env\.(example|template|sample|dist)'

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
  target=$(echo "$input" | jq -r '[.tool_input.path // "", .tool_input.glob // ""] | join(" ")')
  pattern=$(echo "$input" | jq -r '.tool_input.pattern // empty')
  mode=$(echo "$input" | jq -r '.tool_input.output_mode // "files_with_matches"')
  # files_with_matches and count never emit file content.
  [[ $mode == "content" ]] || exit 0
  [[ $target =~ $template_re ]] && exit 0
  if [[ $target =~ $secret_path_re ]]; then
    deny "Grepping $target with output_mode=content would print credential lines into this transcript. Use output_mode=\"count\" to confirm a key exists, or run the consuming tool and read its error."
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

  # 2. Dumping the whole environment.
  if echo "$command" | grep -qE '(^|[|;&]\s*)(printenv|env)\s*($|[|;&])'; then
    deny "A bare env/printenv prints every secret in scope into this transcript. Name the one variable you need and test it without echoing its value."
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

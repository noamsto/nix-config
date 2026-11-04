#!/usr/bin/env bash
# PreToolUse hook: enforce skeleton-first reads.
# Blocks an unbounded Read of a file >300 lines, telling the model to slice.
# Bounded reads (limit), short files (<=300 lines), binary files (images/PDFs),
# notebooks, and missing files pass through.
# An explicit `limit` is the deliberate opt-in for a genuine whole-file read.

set -euo pipefail

input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
[[ $tool_name == "Read" ]] || exit 0

# An explicit limit is the intended slice-read (or the deliberate full-read
# opt-in) -> allow.
limit=$(echo "$input" | jq -r '.tool_input.limit // empty')
[[ -z $limit ]] || exit 0

file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ -n $file_path && -f $file_path ]] || exit 0

# Formats Read renders whole, plus lockfiles and minified/generated files where a
# windowed read is useless -> allow. grep -I treats binary (images/PDFs) as no-match.
case "${file_path,,}" in
*.ipynb | *.lock | *.lockb | package-lock.json | *.min.js | *.min.css) exit 0 ;;
esac
grep -qI '' "$file_path" || exit 0

lines=$(wc -l <"$file_path" 2>/dev/null) || exit 0

# offset without limit still reads to EOF -> guard the remaining span.
offset=$(echo "$input" | jq -r '.tool_input.offset // 0')
remaining=$((lines - offset))
[[ $remaining -gt 300 ]] || exit 0

reason="${file_path} is ${lines} lines (>300). Skeleton-first: run ast-grep / the context-efficient-tools:code-structure skill / Grep for the symbol you need first, then Read with offset+limit for the region that matters. To read the whole file deliberately (security review, top-to-bottom audit, every-line-matters config), re-issue Read with an explicit limit covering the file."

jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'

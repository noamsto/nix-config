# shellcheck shell=bash
#
# halo-strata-smoke: post-deploy checks for halo's resident Strata model
# (installed via hosts/halo/default.nix). Read-only: no load/unload/pin calls.
# Run after `halo-ops rebuild` once strata-prepare and lemond-preload finish.
# Each check prints PASS or FAIL; the exit status is non-zero if any failed.

PORT="${LEMOND_PORT:-13305}"
BASE="http://127.0.0.1:${PORT}"
MODEL="Qwen3.8-Flash-Next-Strata"
CTX=262144

failed=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() {
  printf 'FAIL  %s\n' "$1"
  failed=1
}

# One OpenAI-compatible chat request; writes the response body to stdout.
chat() {
  curl --silent --show-error --max-time 300 \
    --header 'Content-Type: application/json' \
    --data "$1" \
    "${BASE}/v1/chat/completions"
}

health=$(curl --silent --show-error --max-time 10 "${BASE}/api/v1/health" 2>/dev/null) || {
  fail "lemond /api/v1/health unreachable on ${BASE}"
  exit 1
}

# /health lists the loaded models; Strata must be the only one.
loaded_names=$(jq -r '.all_models_loaded[]?.model_name' <<<"$health" 2>/dev/null || true)
loaded_count=$(jq -r '.all_models_loaded | length' <<<"$health" 2>/dev/null || echo 0)
if [[ $loaded_count == 1 && $loaded_names == "$MODEL" ]]; then
  pass "health: only ${MODEL} loaded"
else
  fail "health: loaded models = ${loaded_names:-none} (${loaded_count})"
fi

# Resident means pinned; GSQHalo must not be.
pinned=$(jq -r --arg m "$MODEL" '.all_models_loaded[]? | select(.model_name == $m) | .pinned' <<<"$health" 2>/dev/null || true)
if [[ $pinned == true ]]; then
  pass "health: ${MODEL} pinned"
else
  fail "health: ${MODEL} pinned = ${pinned:-unknown}"
fi

# The loaded context comes from recipe_options.ctx_size, not a top-level key.
ctx=$(jq -r --arg m "$MODEL" '.all_models_loaded[]? | select(.model_name == $m) | .recipe_options.ctx_size' <<<"$health" 2>/dev/null || true)
if [[ $ctx == "$CTX" ]]; then
  pass "health: context ${ctx}"
else
  fail "health: context = ${ctx:-unknown} (want ${CTX})"
fi

# Plain text completion. thinking:false (lemonade normalizes it to
# enable_thinking/reasoning_effort none) keeps a reasoning trace from eating the
# whole token budget.
body=$(jq -nc --arg m "$MODEL" '{model:$m,messages:[{role:"user",content:"Reply with the single word: pong"}],max_tokens:64,thinking:false,stream:false}')
reply=$(chat "$body" 2>/dev/null) || reply=""
if jq -e '(.choices[0].message.content? // "") | length > 0' <<<"$reply" >/dev/null 2>&1; then
  pass "text: chat completion answered"
else
  fail "text: no content (${reply:0:200})"
fi

# Tool call.
tools='[{"type":"function","function":{"name":"get_time","description":"Return the current time.","parameters":{"type":"object","properties":{},"required":[]}}}]'
body=$(jq -nc --arg m "$MODEL" --argjson t "$tools" '{model:$m,messages:[{role:"user",content:"What time is it? Call the get_time tool."}],tools:$t,max_tokens:256,thinking:false,stream:false}')
reply=$(chat "$body" 2>/dev/null) || reply=""
if jq -e '(.choices[0].message.tool_calls[0].function.name? // "") == "get_time"' <<<"$reply" >/dev/null 2>&1; then
  pass "tool: get_time called"
else
  fail "tool: no get_time tool call (${reply:0:200})"
fi

# Image via a data: URL; behind lemond, file paths and http(s) URLs are refused.
img='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='
body=$(jq -nc --arg m "$MODEL" --arg u "$img" '{model:$m,messages:[{role:"user",content:[{type:"text",text:"Describe this image."},{type:"image_url",image_url:{url:$u}}]}],max_tokens:128,thinking:false,stream:false}')
reply=$(chat "$body" 2>/dev/null) || reply=""
if jq -e '(.error? // null) == null and ((.choices[0].message.content? // "") | length > 0)' <<<"$reply" >/dev/null 2>&1; then
  pass "image: data: URL accepted"
else
  fail "image: request failed (${reply:0:200})"
fi

if [[ $failed -eq 0 ]]; then
  echo "STRATA SMOKE: PASS"
else
  echo "STRATA SMOKE: ${failed} check(s) FAILED"
fi
exit "$failed"

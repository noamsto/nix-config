{pkgs, ...}:
pkgs.writeShellApplication {
  name = "claude-statusline";

  runtimeInputs = with pkgs; [
    jq
    bc
    coreutils
  ];

  excludeShellChecks = ["SC2155"];

  text = ''
    #!/usr/bin/env bash
    # Claude Code Statusline
    # Shows: Model | Tokens | Duration | Messages
    # Focused on Claude-specific info (tmux shows path/branch)

    # Read Claude Code session data from stdin
    input=$(cat)

    # Exit gracefully if no input (e.g., during home-manager activation)
    if [[ -z "$input" ]] || ! echo "$input" | jq empty 2>/dev/null; then
      echo "Claude Code"
      exit 0
    fi

    # ========================================
    # Extract basic info from stdin (Claude Code 2.0.65+)
    # ========================================
    model=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
    conversation_duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')

    # Context window size from API (this field is accurate)
    context_window_size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')

    # Use context_window_size from Claude Code, fallback to 200k if not provided
    if [[ "$context_window_size" -gt 0 ]]; then
      TOKEN_LIMIT=$context_window_size
    else
      TOKEN_LIMIT=200000
    fi

    # Get transcript info for token calculation
    transcript_path=$(echo "$input" | jq -r '.transcript_path // ""')
    session_id=$(echo "$input" | jq -r '.session_id // ""')
    message_count=0
    token_count=0

    # NOTE: context_window.total_input_tokens and total_output_tokens are CUMULATIVE
    # session totals, NOT current context usage. They don't update when context is
    # auto-compacted. We must parse the transcript to get actual current usage.
    if [[ -f "$transcript_path" && -r "$transcript_path" && -n "$session_id" ]]; then
      message_count=$(jq -s --arg sid "$session_id" '[.[] | select(.sessionId == $sid)] | length' "$transcript_path" 2>/dev/null || echo "0")

      # Get LAST assistant message's token usage (represents current active context)
      # Context window = input_tokens + cache_read_input_tokens
      # NOTE: cache_creation_input_tokens is a subset of input (what was newly cached)
      # NOTE: output_tokens are the response, not part of context window limit
      token_count=$(jq -s --arg sid "$session_id" '
        [.[] |
          select(.sessionId == $sid and .type == "assistant" and .message.usage)] |
        if length > 0 then
          .[-1].message.usage |
          ((.cache_read_input_tokens // 0) + (.input_tokens // 0))
        else
          0
        end
      ' "$transcript_path" 2>/dev/null || echo "0")
    fi

    # Safe defaults
    message_count=''${message_count:-0}
    token_count=''${token_count:-0}
    token_percent=$(echo "scale=1; ($token_count * 100) / $TOKEN_LIMIT" | bc 2>/dev/null || echo "0.0")

    # ========================================
    # Color coding based on token usage
    # ========================================
    token_percent_int=$(echo "$token_percent / 1" | bc 2>/dev/null || echo "0")
    if [[ "$token_percent_int" -ge 95 ]]; then
      token_color="\033[1;31m"  # Red
    elif [[ "$token_percent_int" -ge 80 ]]; then
      token_color="\033[1;33m"  # Yellow
    else
      token_color="\033[1;32m"  # Green
    fi

    reset="\033[0m"

    # ========================================
    # Build statusline components
    # ========================================

    # Model info
    model_display=$(printf "\033[1;34m🤖 %s\033[0m" "$model")

    # Token info with color coding
    if [[ "$TOKEN_LIMIT" -ge 1000000 ]]; then
      # For 1M contexts: show as "200k/1M (20%)"
      token_count_k=$((token_count / 1000))
      token_limit_m=$(echo "scale=0; $TOKEN_LIMIT / 1000000" | bc 2>/dev/null || echo "1")

      token_display=$(printf "%b📊 %dk/%sM (%s%%)%b" \
        "$token_color" \
        "$token_count_k" \
        "$token_limit_m" \
        "$token_percent" \
        "$reset")
    else
      # Format as thousands (k)
      token_display=$(printf "%b📊 %dk/%dk (%s%%)%b" \
        "$token_color" \
        "$((token_count / 1000))" \
        "$((TOKEN_LIMIT / 1000))" \
        "$token_percent" \
        "$reset")
    fi

    # Conversation duration
    conversation_duration_ms=''${conversation_duration_ms:-0}
    conversation_hours=$(echo "scale=2; $conversation_duration_ms / 3600000" | bc 2>/dev/null || echo "0.00")
    duration_display=$(printf "\033[1;35m⏱️ %.2fh\033[0m" "$conversation_hours")

    # Message count
    msg_display=$(printf "\033[1;35m💬 %d msgs\033[0m" "$message_count")

    # ========================================
    # Output single line
    # ========================================
    echo -e "''${model_display} | ''${token_display} | ''${duration_display} | ''${msg_display}"
  '';
}

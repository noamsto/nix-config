{
  pkgs,
  lib,
  ...
}:
pkgs.writeShellApplication {
  name = "claude-statusline";

  runtimeInputs = with pkgs; [
    jq
    bc
    starship
    coreutils
  ];

  excludeShellChecks = ["SC2155"];

  text = ''
    #!/usr/bin/env bash
    # Claude Code Statusline
    # Shows: Model | Tokens | Conversation Duration | Messages
    # Only displays reliable data from input JSON and transcript

    # Read Claude Code session data from stdin
    input=$(cat)

    # Exit gracefully if no input (e.g., during home-manager activation)
    if [[ -z "$input" ]] || ! echo "$input" | jq empty 2>/dev/null; then
      # Return a simple starship prompt if available, otherwise minimal output
      if command -v starship &> /dev/null; then
        starship prompt | head -n1 | sed 's/\x1b\[J//'
      else
        echo "Claude Code"
      fi
      exit 0
    fi

    # ========================================
    # Extract basic info from stdin
    # ========================================
    model=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
    model_id=$(echo "$input" | jq -r '.model.id // ""')
    transcript_path=$(echo "$input" | jq -r '.transcript_path // ""')
    session_id=$(echo "$input" | jq -r '.session_id // ""')
    conversation_duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')

    # Detect context window size based on model
    TOKEN_LIMIT=200000  # Default for standard models
    if [[ "$model" == *"[1m]"* ]] || [[ "$model" == *"[1M]"* ]] || [[ "$model_id" == *"1m"* ]]; then
      TOKEN_LIMIT=1000000  # 1M context window
    elif [[ "$model_id" == *"opus"* ]]; then
      TOKEN_LIMIT=200000   # Opus has 200k
    elif [[ "$model_id" == *"haiku"* ]]; then
      TOKEN_LIMIT=200000   # Haiku has 200k
    fi

    # ========================================
    # Extract token and message counts from transcript
    # ========================================
    token_count=0
    message_count=0

    if [[ -f "$transcript_path" && -r "$transcript_path" && -n "$session_id" ]]; then
      # Count message entries for current session only
      message_count=$(jq -s --arg sid "$session_id" '[.[] | select(.sessionId == $sid)] | length' "$transcript_path" 2>/dev/null || echo "0")

      # Get LAST assistant message's token usage (represents current active context window)
      token_count=$(jq -s --arg sid "$session_id" '
        [.[] |
          select(.sessionId == $sid and .type == "assistant" and .message.usage)] |
        if length > 0 then
          .[-1].message.usage |
          ((.cache_creation_input_tokens // 0) +
           (.cache_read_input_tokens // 0) +
           (.input_tokens // 0) +
           (.output_tokens // 0))
        else
          0
        end
      ' "$transcript_path" 2>/dev/null || echo "0")

      # Fallback: estimate from content length if no usage data
      token_count=''${token_count:-0}
      if [[ "$token_count" -eq 0 && -n "$session_id" ]]; then
        total_chars=$(jq -s --arg sid "$session_id" '[.[] | select(.sessionId == $sid and .message.content) | (.message.content | if type == "array" then map(select(.type == "text") | .text) | join("") else . end | tostring | length)] | add // 0' "$transcript_path" 2>/dev/null || echo "0")
        total_chars=''${total_chars:-0}
        token_count=$(echo "$total_chars / 4" | bc 2>/dev/null || echo "0")
      fi
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

    # Get starship prompt (first line only, strip control sequences)
    starship_line=$(starship prompt | head -n1 | sed 's/\x1b\[J//')

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
    duration_display=$(printf "\033[1;35m⏱️  %.2fh\033[0m" "$conversation_hours")

    # Message count
    msg_display=$(printf "\033[1;35m💬 %d msgs\033[0m" "$message_count")

    # ========================================
    # Output single line
    # ========================================
    echo -e "''${starship_line} ''${model_display} | ''${token_display} | ''${duration_display} | ''${msg_display}"
  '';
}

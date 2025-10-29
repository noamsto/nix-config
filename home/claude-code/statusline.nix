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

  text = ''
    #!/usr/bin/env bash
    # Claude Code Comprehensive Statusline
    # Shows: Model | Costs (session, request, daily) | Tokens (count, %, remaining) | Messages

    # Configuration
    CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/claude-code"
    DAILY_COST_FILE="$CACHE_DIR/daily-cost.json"
    LAST_SESSION_FILE="$CACHE_DIR/last-session.json"

    # Ensure cache directory exists
    mkdir -p "$CACHE_DIR" 2>/dev/null || true

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
    session_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
    transcript_path=$(echo "$input" | jq -r '.transcript_path // ""')
    session_id=$(echo "$input" | jq -r '.session_id // ""')

    # Detect context window size based on model
    # Check for extended context indicator in display name (e.g., "Sonnet 4.5 [1M]")
    TOKEN_LIMIT=200000  # Default for standard models
    if [[ "$model" == *"[1m]"* ]] || [[ "$model" == *"[1M]"* ]] || [[ "$model_id" == *"1m"* ]]; then
      TOKEN_LIMIT=1000000  # 1M context window
    elif [[ "$model_id" == *"opus"* ]]; then
      TOKEN_LIMIT=200000   # Opus has 200k
    elif [[ "$model_id" == *"haiku"* ]]; then
      TOKEN_LIMIT=200000   # Haiku has 200k
    fi

    # ========================================
    # Calculate per-request cost (delta tracking with session awareness)
    # ========================================
    last_cost=0
    last_session_id=""

    # Load previous session data
    if [[ -f "$LAST_SESSION_FILE" ]] && [[ -s "$LAST_SESSION_FILE" ]]; then
      last_session_id=$(jq -r '.session_id // ""' "$LAST_SESSION_FILE" 2>/dev/null || echo "")
      last_cost=$(jq -r '.cost // 0' "$LAST_SESSION_FILE" 2>/dev/null || echo "0")
    fi

    # Ensure costs are valid numbers
    session_cost=''${session_cost:-0}
    last_cost=''${last_cost:-0}

    # If session changed, reset last_cost to avoid negative delta
    if [[ "$session_id" != "$last_session_id" ]]; then
      last_cost=0
    fi

    request_cost=$(echo "$session_cost - $last_cost" | bc -l 2>/dev/null || echo "0")

    # Save current session state
    jq -n \
      --arg sid "$session_id" \
      --arg cost "$session_cost" \
      '{session_id: $sid, cost: ($cost | tonumber)}' \
      > "$LAST_SESSION_FILE" 2>/dev/null || true

    # ========================================
    # Track daily costs
    # ========================================
    today=$(date +%Y-%m-%d)
    daily_total=0

    if [[ -f "$DAILY_COST_FILE" ]] && [[ -s "$DAILY_COST_FILE" ]]; then
      # Only parse if file exists and is not empty
      if stored_date=$(jq -r '.date // ""' "$DAILY_COST_FILE" 2>/dev/null) && [[ "$stored_date" == "$today" ]]; then
        daily_total=$(jq -r '.total // 0' "$DAILY_COST_FILE" 2>/dev/null || echo "0")
      fi
    fi

    # Update daily total (with safe defaults)
    # Only add positive request costs (ignore negative = new session started)
    daily_total=''${daily_total:-0}
    request_cost=''${request_cost:-0}

    # Only add to daily total if request cost is positive
    if (( $(echo "$request_cost > 0" | bc -l 2>/dev/null || echo "0") )); then
      daily_total=$(echo "$daily_total + $request_cost" | bc -l 2>/dev/null || echo "$daily_total")
    fi

    jq -n \
      --arg date "$today" \
      --arg total "$daily_total" \
      '{date: $date, total: ($total | tonumber)}' \
      > "$DAILY_COST_FILE" 2>/dev/null || true

    # ========================================
    # Extract token and message counts from transcript
    # ========================================
    token_count=0
    message_count=0

    if [[ -f "$transcript_path" && -r "$transcript_path" && -n "$session_id" ]]; then
      # Count message entries for current session only
      message_count=$(jq -s --arg sid "$session_id" '[.[] | select(.sessionId == $sid)] | length' "$transcript_path" 2>/dev/null || echo "0")

      # Get LAST assistant message's token usage (represents current active context window)
      # Don't sum all messages - that's historical total, not current context size
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

      # Fallback: estimate from content length if no usage data (current session only)
      token_count=''${token_count:-0}
      if [[ "$token_count" -eq 0 && -n "$session_id" ]]; then
        total_chars=$(jq -s --arg sid "$session_id" '[.[] | select(.sessionId == $sid and .message.content) | (.message.content | if type == "array" then map(select(.type == "text") | .text) | join("") else . end | tostring | length)] | add // 0' "$transcript_path" 2>/dev/null || echo "0")
        total_chars=''${total_chars:-0}
        token_count=$(echo "$total_chars / 4" | bc 2>/dev/null || echo "0")
      fi
    fi

    # Ensure message_count has a safe default
    message_count=''${message_count:-0}

    # Calculate token metrics with safe defaults
    token_count=''${token_count:-0}
    token_percent=$(echo "scale=1; ($token_count * 100) / $TOKEN_LIMIT" | bc 2>/dev/null || echo "0.0")
    token_remaining=$((TOKEN_LIMIT - token_count))

    # ========================================
    # Color coding based on thresholds
    # ========================================
    # Token colors (with safe comparison)
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

    # Cost info (ensure all costs are numbers)
    session_cost=''${session_cost:-0}
    request_cost=''${request_cost:-0}
    daily_total=''${daily_total:-0}

    # Build cost display - always show all values for consistency
    # Request cost gets 4 decimal places for precision, others get 2
    cost_display=$(printf "💰 \$%.2f (req: \$%.4f) (today: \$%.2f)" \
      "$session_cost" "$request_cost" "$daily_total" 2>/dev/null || echo "💰 \$0.00 (req: \$0.0000) (today: \$0.00)")

    # Token info with color coding
    # Format token counts: use "M" for millions (1M+), "k" for thousands
    if [[ "$TOKEN_LIMIT" -ge 1000000 ]]; then
      # Format as millions (M)
      token_count_display=$(echo "scale=1; $token_count / 1000000" | bc 2>/dev/null || echo "0")
      token_limit_display=$(echo "scale=0; $TOKEN_LIMIT / 1000000" | bc 2>/dev/null || echo "1")
      token_remaining_display=$(echo "scale=0; $token_remaining / 1000000" | bc 2>/dev/null || echo "0")

      # Remove trailing .0 for whole numbers
      token_count_display="''${token_count_display%.0}"

      token_display=$(printf "%b📊 %sM/%sM (%s%%, %sM left)%b" \
        "$token_color" \
        "$token_count_display" \
        "$token_limit_display" \
        "$token_percent" \
        "$token_remaining_display" \
        "$reset")
    else
      # Format as thousands (k)
      token_display=$(printf "%b📊 %dk/%dk (%s%%, %dk left)%b" \
        "$token_color" \
        "$((token_count / 1000))" \
        "$((TOKEN_LIMIT / 1000))" \
        "$token_percent" \
        "$((token_remaining / 1000))" \
        "$reset")
    fi

    # Message count
    msg_display=$(printf "\033[1;35m💬 %d msgs\033[0m" "$message_count")

    # ========================================
    # Output single line
    # ========================================
    echo -e "''${starship_line} ''${model_display} | ''${cost_display} | ''${token_display} | ''${msg_display}"
  '';
}

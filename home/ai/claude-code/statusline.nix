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
    curl
    findutils
  ];

  excludeShellChecks = ["SC2155"];

  text = ''
    #!/usr/bin/env bash
    # Claude Code Enhanced Statusline
    # Shows: Model | Org | Tokens | Weekly Usage | Session Duration | Messages

    # Configuration
    CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}/claude-code"
    ORG_INFO_CACHE="$CACHE_DIR/org-info.json"
    WEEKLY_USAGE_CACHE="$CACHE_DIR/weekly-usage.json"
    WEEKLY_LIMIT_HOURS=70  # Default for team plan (50-95h range), user-configurable

    # Weekly reset configuration (customize based on your account)
    # Default: Thursday at 12:00 in your timezone
    WEEKLY_RESET_DAY=4       # 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday, 7=Sunday
    WEEKLY_RESET_HOUR=12     # Hour in 24h format (local time)
    WEEKLY_RESET_MINUTE=0    # Minute

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
    transcript_path=$(echo "$input" | jq -r '.transcript_path // ""')
    session_id=$(echo "$input" | jq -r '.session_id // ""')
    session_duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')

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
    # Get organization name (with caching)
    # ========================================
    get_org_name() {
      local org_name=""

      # Check cache (1 hour TTL)
      if [[ -f "$ORG_INFO_CACHE" ]]; then
        local cache_age=$(($(date +%s) - $(stat -c %Y "$ORG_INFO_CACHE" 2>/dev/null || echo 0)))
        if [[ $cache_age -lt 3600 ]]; then
          org_name=$(jq -r '.name // ""' "$ORG_INFO_CACHE" 2>/dev/null || echo "")
          echo "$org_name"
          return 0
        fi
      fi

      # Try to get org info from API (fail silently)
      # Note: This requires the API key Claude Code uses
      # We'll try to detect it from Claude's config
      local api_key=""
      if [[ -f "$HOME/.config/claude/settings.json" ]]; then
        api_key=$(jq -r '.apiKey // ""' "$HOME/.config/claude/settings.json" 2>/dev/null || echo "")
      fi

      if [[ -n "$api_key" ]]; then
        org_name=$(curl -s -f \
          -H "anthropic-version: 2023-06-01" \
          -H "x-api-key: $api_key" \
          "https://api.anthropic.com/v1/organizations/me" 2>/dev/null \
          | jq -r '.name // ""' 2>/dev/null || echo "")

        # Cache the result
        if [[ -n "$org_name" ]]; then
          jq -n --arg name "$org_name" '{name: $name}' > "$ORG_INFO_CACHE" 2>/dev/null || true
        fi
      fi

      echo "$org_name"
    }

    # ========================================
    # Calculate weekly usage (with caching)
    # ========================================
    get_weekly_usage_hours() {
      # Check cache (5 min TTL)
      if [[ -f "$WEEKLY_USAGE_CACHE" ]]; then
        local cache_age=$(($(date +%s) - $(stat -c %Y "$WEEKLY_USAGE_CACHE" 2>/dev/null || echo 0)))
        if [[ $cache_age -lt 300 ]]; then
          jq -r '.hours // 0' "$WEEKLY_USAGE_CACHE" 2>/dev/null || echo "0"
          return 0
        fi
      fi

      # Calculate the most recent reset time based on configured day/hour
      local now=$(date +%s)
      local current_day=$(date +%u)  # 1=Monday, 7=Sunday
      local days_since_reset=$(( (current_day - WEEKLY_RESET_DAY + 7) % 7 ))

      # Calculate reset timestamp
      local reset_today=$(date -d "today $WEEKLY_RESET_HOUR:$WEEKLY_RESET_MINUTE:00" +%s)
      local week_start=$((reset_today - (days_since_reset * 86400)))

      # If we haven't reached today's reset time yet and reset day is today, use last week's reset
      if [[ $current_day -eq $WEEKLY_RESET_DAY ]] && [[ $now -lt $reset_today ]]; then
        week_start=$((week_start - (7 * 86400)))
      fi

      local total_ms=0
      local claude_projects_dir="$HOME/.claude/projects"

      # Find all conversation JSON files and sum durations for this week
      if [[ -d "$claude_projects_dir" ]]; then
        while IFS= read -r -d "" file; do
          # Extract creation timestamp and duration from conversation file
          local file_time=$(stat -c %Y "$file" 2>/dev/null || echo 0)

          # Only process files from this week
          if [[ $file_time -ge $week_start ]]; then
            # Try to get duration from file (if it has cost.total_duration_ms)
            local duration=$(jq -r '.cost.total_duration_ms // 0' "$file" 2>/dev/null || echo "0")
            total_ms=$((total_ms + duration))
          fi
        done < <(find "$claude_projects_dir" -name "*.json" -type f -print0 2>/dev/null)
      fi

      # Convert ms to hours
      local hours=$(echo "scale=1; $total_ms / 3600000" | bc 2>/dev/null || echo "0")

      # Cache the result
      jq -n --arg hours "$hours" '{hours: ($hours | tonumber)}' > "$WEEKLY_USAGE_CACHE" 2>/dev/null || true

      echo "$hours"
    }

    # ========================================
    # Calculate next weekly reset time
    # ========================================
    get_next_reset() {
      local now=$(date +%s)
      local current_day=$(date +%u)  # 1=Monday, 7=Sunday

      # Calculate next reset time
      local reset_today=$(date -d "today $WEEKLY_RESET_HOUR:$WEEKLY_RESET_MINUTE:00" +%s)

      local next_reset
      if [[ $current_day -eq $WEEKLY_RESET_DAY ]] && [[ $now -lt $reset_today ]]; then
        # Reset is today and hasn't happened yet
        next_reset=$reset_today
      else
        # Calculate days until next reset day
        local days_until=$(( (WEEKLY_RESET_DAY - current_day + 7) % 7 ))
        if [[ $days_until -eq 0 ]]; then
          days_until=7  # Next week same day
        fi
        next_reset=$((reset_today + (days_until * 86400)))
      fi

      local seconds_until=$((next_reset - now))
      local days=$((seconds_until / 86400))
      local hours=$(((seconds_until % 86400) / 3600))

      # Format as human-readable
      if [[ $days -gt 0 ]]; then
        echo "''${days}d ''${hours}h"
      else
        echo "''${hours}h"
      fi
    }

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

    # Organization info (optional)
    org_name=$(get_org_name)
    if [[ -n "$org_name" ]]; then
      org_display=$(printf " \033[1;36m🏢 %s\033[0m" "$org_name")
    else
      org_display=""
    fi

    # Session duration
    session_duration_ms=''${session_duration_ms:-0}
    session_hours=$(echo "scale=2; $session_duration_ms / 3600000" | bc 2>/dev/null || echo "0.00")
    session_display=$(printf "\033[1;35m⏱️  %.2fh session\033[0m" "$session_hours")

    # Weekly usage
    weekly_used=$(get_weekly_usage_hours)
    weekly_percent_used=$(echo "scale=0; ($weekly_used * 100) / $WEEKLY_LIMIT_HOURS" | bc 2>/dev/null || echo "0")
    weekly_percent_left=$((100 - weekly_percent_used))

    # Color code weekly usage (based on how much is LEFT)
    if [[ "$weekly_percent_left" -le 10 ]]; then
      weekly_color="\033[1;31m"  # Red (≤10% left)
    elif [[ "$weekly_percent_left" -le 25 ]]; then
      weekly_color="\033[1;33m"  # Yellow (≤25% left)
    else
      weekly_color="\033[1;32m"  # Green (>25% left)
    fi

    next_reset=$(get_next_reset)
    weekly_display=$(printf "%b⏰ %.1fh/%dh weekly (%d%% left, resets in %s)%b" \
      "$weekly_color" "$weekly_used" "$WEEKLY_LIMIT_HOURS" "$weekly_percent_left" "$next_reset" "$reset")

    # Token info with color coding (compact format)
    # Format token counts: use "k" for better readability even with 1M contexts
    if [[ "$TOKEN_LIMIT" -ge 1000000 ]]; then
      # For 1M contexts: show as "200k/1M (20%)" for clarity
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

    # Message count
    msg_display=$(printf "\033[1;35m💬 %d msgs\033[0m" "$message_count")

    # ========================================
    # Output single line
    # ========================================
    echo -e "''${starship_line} ''${model_display}''${org_display} | ''${token_display} | ''${weekly_display} | ''${session_display} | ''${msg_display}"
  '';
}

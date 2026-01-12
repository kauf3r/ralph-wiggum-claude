#!/bin/bash
# Ralph Wiggum for Claude Code: Stream Parser
#
# Parses Claude Code stream-json output in real-time.
# Unlike the cursor version, Claude provides EXACT token counts!
#
# Usage:
#   claude -p --output-format stream-json "..." | ./stream-parser.sh /path/to/workspace
#
# Outputs to stdout:
#   - ROTATE when threshold hit (180k tokens)
#   - WARN when approaching limit (150k tokens)
#   - GUTTER when stuck pattern detected
#   - COMPLETE when agent outputs <ralph>COMPLETE</ralph>

set -euo pipefail

WORKSPACE="${1:-.}"
RALPH_DIR="$WORKSPACE/.ralph"

mkdir -p "$RALPH_DIR"

# Thresholds (Claude has 200k context window)
WARN_THRESHOLD=150000
ROTATE_THRESHOLD=180000

# Tracking state - Claude gives us exact counts!
# We track the LATEST reported usage (not cumulative) since Claude reports per-turn
CURRENT_INPUT_TOKENS=0
CURRENT_OUTPUT_TOKENS=0
TOOL_CALLS=0
WARN_SENT=0

# For context window, we care about input tokens (what's in context)
# Output tokens don't count against context window

# Gutter detection temp files (macOS bash 3.x compat)
FAILURES_FILE=$(mktemp)
WRITES_FILE=$(mktemp)
trap "rm -f $FAILURES_FILE $WRITES_FILE" EXIT

get_health_emoji() {
  local tokens=$1
  local pct=$((tokens * 100 / ROTATE_THRESHOLD))

  if [[ $pct -lt 60 ]]; then
    echo "🟢"
  elif [[ $pct -lt 80 ]]; then
    echo "🟡"
  else
    echo "🔴"
  fi
}

log_activity() {
  local message="$1"
  local timestamp=$(date '+%H:%M:%S')
  # For context window, input tokens are what matters
  local emoji=$(get_health_emoji $CURRENT_INPUT_TOKENS)

  echo "[$timestamp] $emoji $message" >> "$RALPH_DIR/activity.log"
}

log_error() {
  local message="$1"
  local timestamp=$(date '+%H:%M:%S')

  echo "[$timestamp] $message" >> "$RALPH_DIR/errors.log"
}

log_token_status() {
  # Context window is determined by input tokens
  local context_tokens=$CURRENT_INPUT_TOKENS
  local pct=$((context_tokens * 100 / ROTATE_THRESHOLD))
  local emoji=$(get_health_emoji $context_tokens)
  local timestamp=$(date '+%H:%M:%S')

  local status_msg="CONTEXT: $context_tokens / $ROTATE_THRESHOLD ($pct%)"

  if [[ $pct -ge 90 ]]; then
    status_msg="$status_msg - rotation imminent"
  elif [[ $pct -ge 75 ]]; then
    status_msg="$status_msg - approaching limit"
  fi

  echo "[$timestamp] $emoji $status_msg [in:$CURRENT_INPUT_TOKENS out:$CURRENT_OUTPUT_TOKENS]" >> "$RALPH_DIR/activity.log"
}

check_thresholds() {
  # Context window is determined by input tokens
  local context_tokens=$CURRENT_INPUT_TOKENS

  # Check rotation threshold
  if [[ $context_tokens -ge $ROTATE_THRESHOLD ]]; then
    log_activity "ROTATE: Context threshold reached ($context_tokens >= $ROTATE_THRESHOLD)"
    echo "ROTATE" 2>/dev/null || true
    return
  fi

  # Check warning threshold
  if [[ $context_tokens -ge $WARN_THRESHOLD ]] && [[ $WARN_SENT -eq 0 ]]; then
    log_activity "WARN: Approaching context limit ($context_tokens >= $WARN_THRESHOLD)"
    WARN_SENT=1
    echo "WARN" 2>/dev/null || true
  fi
}

track_shell_failure() {
  local cmd="$1"
  local exit_code="$2"

  if [[ $exit_code -ne 0 ]]; then
    local count
    count=$(grep -c "^${cmd}$" "$FAILURES_FILE" 2>/dev/null) || count=0
    count=$((count + 1))
    echo "$cmd" >> "$FAILURES_FILE"

    log_error "SHELL FAIL: $cmd -> exit $exit_code (attempt $count)"

    if [[ $count -ge 3 ]]; then
      log_error "GUTTER: same command failed ${count}x"
      echo "GUTTER" 2>/dev/null || true
    fi
  fi
}

track_file_write() {
  local path="$1"
  local now=$(date +%s)

  echo "$now:$path" >> "$WRITES_FILE"

  local cutoff=$((now - 600))
  local count=$(awk -F: -v cutoff="$cutoff" -v path="$path" '
    $1 >= cutoff && $2 == path { count++ }
    END { print count+0 }
  ' "$WRITES_FILE")

  if [[ $count -ge 5 ]]; then
    log_error "THRASHING: $path written ${count}x in 10 min"
    echo "GUTTER" 2>/dev/null || true
  fi
}

process_line() {
  local line="$1"

  [[ -z "$line" ]] && return

  local type=$(echo "$line" | jq -r '.type // empty' 2>/dev/null) || return
  local subtype=$(echo "$line" | jq -r '.subtype // empty' 2>/dev/null) || true

  case "$type" in
    "system")
      if [[ "$subtype" == "init" ]]; then
        local model=$(echo "$line" | jq -r '.model // "unknown"' 2>/dev/null) || model="unknown"
        local version=$(echo "$line" | jq -r '.claude_code_version // "unknown"' 2>/dev/null) || version="unknown"
        log_activity "SESSION START: model=$model claude_code=$version"
      fi
      ;;

    "assistant")
      # Extract text and check for sigils
      local text=$(echo "$line" | jq -r '.message.content[0].text // empty' 2>/dev/null) || text=""

      if [[ -n "$text" ]]; then
        # Check for completion sigil
        if [[ "$text" == *"<ralph>COMPLETE</ralph>"* ]]; then
          log_activity "Agent signaled COMPLETE"
          echo "COMPLETE" 2>/dev/null || true
        fi

        # Check for gutter sigil
        if [[ "$text" == *"<ralph>GUTTER</ralph>"* ]]; then
          log_activity "Agent signaled GUTTER (stuck)"
          echo "GUTTER" 2>/dev/null || true
        fi
      fi

      # Extract token usage from assistant message
      # Claude reports: input_tokens (new) + cache_read (from cache) = total context
      local input_tokens=$(echo "$line" | jq -r '.message.usage.input_tokens // 0' 2>/dev/null) || input_tokens=0
      local output_tokens=$(echo "$line" | jq -r '.message.usage.output_tokens // 0' 2>/dev/null) || output_tokens=0
      local cache_read=$(echo "$line" | jq -r '.message.usage.cache_read_input_tokens // 0' 2>/dev/null) || cache_read=0

      # REPLACE (not accumulate) - each message reports current context state
      if [[ $input_tokens -gt 0 ]] || [[ $cache_read -gt 0 ]]; then
        CURRENT_INPUT_TOKENS=$((input_tokens + cache_read))
      fi
      if [[ $output_tokens -gt 0 ]]; then
        CURRENT_OUTPUT_TOKENS=$output_tokens
      fi
      ;;

    "tool_use")
      TOOL_CALLS=$((TOOL_CALLS + 1))

      local tool_name=$(echo "$line" | jq -r '.name // "unknown"' 2>/dev/null) || tool_name="unknown"
      local tool_input=$(echo "$line" | jq -r '.input // empty' 2>/dev/null) || tool_input=""

      case "$tool_name" in
        "Read")
          local path=$(echo "$tool_input" | jq -r '.file_path // "unknown"' 2>/dev/null) || path="unknown"
          log_activity "READ $path"
          ;;
        "Write"|"Edit")
          local path=$(echo "$tool_input" | jq -r '.file_path // "unknown"' 2>/dev/null) || path="unknown"
          log_activity "WRITE $path"
          track_file_write "$path"
          ;;
        "Bash")
          local cmd=$(echo "$tool_input" | jq -r '.command // "unknown"' 2>/dev/null) || cmd="unknown"
          # Truncate long commands for logging
          if [[ ${#cmd} -gt 80 ]]; then
            cmd="${cmd:0:77}..."
          fi
          log_activity "BASH: $cmd"
          ;;
        *)
          log_activity "TOOL: $tool_name"
          ;;
      esac
      ;;

    "tool_result")
      # Check for Bash failures
      local is_error=$(echo "$line" | jq -r '.is_error // false' 2>/dev/null) || is_error="false"

      if [[ "$is_error" == "true" ]]; then
        local content=$(echo "$line" | jq -r '.content // ""' 2>/dev/null) || content=""
        log_error "TOOL ERROR: ${content:0:200}"
        track_shell_failure "tool_call" "1"
      fi

      check_thresholds
      ;;

    "result")
      # Final result - extract duration
      local duration=$(echo "$line" | jq -r '.duration_ms // 0' 2>/dev/null) || duration=0

      log_activity "SESSION END: ${duration}ms"
      log_token_status
      ;;
  esac
}

# Main loop
main() {
  echo "" >> "$RALPH_DIR/activity.log"
  echo "═══════════════════════════════════════════════════════════════" >> "$RALPH_DIR/activity.log"
  echo "Ralph Session Started: $(date)" >> "$RALPH_DIR/activity.log"
  echo "═══════════════════════════════════════════════════════════════" >> "$RALPH_DIR/activity.log"

  local last_token_log=$(date +%s)

  while IFS= read -r line; do
    process_line "$line"

    local now=$(date +%s)
    if [[ $((now - last_token_log)) -ge 30 ]]; then
      log_token_status
      last_token_log=$now
    fi
  done

  log_token_status
}

main

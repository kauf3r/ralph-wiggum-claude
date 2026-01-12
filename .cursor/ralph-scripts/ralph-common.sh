#!/bin/bash
# Ralph Wiggum for Claude Code: Common utilities and loop logic
#
# Adapted from ralph-wiggum-cursor for Claude Code CLI
# Key differences:
# - Uses `claude` CLI instead of `cursor-agent`
# - Leverages Claude's exact token counts (no estimation needed)
# - Compatible with Warp terminal features

# =============================================================================
# CONFIGURATION
# =============================================================================

# Token thresholds (Claude Code tracks exact usage)
WARN_THRESHOLD="${WARN_THRESHOLD:-150000}"      # 150k tokens (Claude has 200k context)
ROTATE_THRESHOLD="${ROTATE_THRESHOLD:-180000}"  # 180k tokens - leave room for safety

# Iteration limits
MAX_ITERATIONS="${MAX_ITERATIONS:-20}"

# Model selection
DEFAULT_MODEL="sonnet"  # Options: sonnet, opus, haiku
MODEL="${RALPH_MODEL:-$DEFAULT_MODEL}"

# Feature flags
USE_BRANCH="${USE_BRANCH:-}"
OPEN_PR="${OPEN_PR:-false}"
SKIP_CONFIRM="${SKIP_CONFIRM:-false}"

# =============================================================================
# BASIC HELPERS
# =============================================================================

# Cross-platform sed -i
sedi() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

get_ralph_dir() {
  local workspace="${1:-.}"
  echo "$workspace/.ralph"
}

get_iteration() {
  local workspace="${1:-.}"
  local state_file="$workspace/.ralph/.iteration"

  if [[ -f "$state_file" ]]; then
    cat "$state_file"
  else
    echo "0"
  fi
}

set_iteration() {
  local workspace="${1:-.}"
  local iteration="$2"
  local ralph_dir="$workspace/.ralph"

  mkdir -p "$ralph_dir"
  echo "$iteration" > "$ralph_dir/.iteration"
}

increment_iteration() {
  local workspace="${1:-.}"
  local current=$(get_iteration "$workspace")
  local next=$((current + 1))
  set_iteration "$workspace" "$next"
  echo "$next"
}

get_health_emoji() {
  local tokens="$1"
  local pct=$((tokens * 100 / ROTATE_THRESHOLD))

  if [[ $pct -lt 60 ]]; then
    echo "🟢"
  elif [[ $pct -lt 80 ]]; then
    echo "🟡"
  else
    echo "🔴"
  fi
}

# =============================================================================
# LOGGING
# =============================================================================

log_activity() {
  local workspace="${1:-.}"
  local message="$2"
  local ralph_dir="$workspace/.ralph"
  local timestamp=$(date '+%H:%M:%S')

  mkdir -p "$ralph_dir"
  echo "[$timestamp] $message" >> "$ralph_dir/activity.log"
}

log_error() {
  local workspace="${1:-.}"
  local message="$2"
  local ralph_dir="$workspace/.ralph"
  local timestamp=$(date '+%H:%M:%S')

  mkdir -p "$ralph_dir"
  echo "[$timestamp] $message" >> "$ralph_dir/errors.log"
}

log_progress() {
  local workspace="$1"
  local message="$2"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local progress_file="$workspace/.ralph/progress.md"

  echo "" >> "$progress_file"
  echo "### $timestamp" >> "$progress_file"
  echo "$message" >> "$progress_file"
}

# =============================================================================
# INITIALIZATION
# =============================================================================

init_ralph_dir() {
  local workspace="$1"
  local ralph_dir="$workspace/.ralph"

  mkdir -p "$ralph_dir"

  # Initialize progress.md
  if [[ ! -f "$ralph_dir/progress.md" ]]; then
    cat > "$ralph_dir/progress.md" << 'EOF'
# Progress Log

> Updated by the agent after significant work.

---

## Session History

EOF
  fi

  # Initialize guardrails.md (Signs)
  if [[ ! -f "$ralph_dir/guardrails.md" ]]; then
    cat > "$ralph_dir/guardrails.md" << 'EOF'
# Ralph Guardrails (Signs)

> Lessons learned from past failures. READ THESE BEFORE ACTING.

## Core Signs

### Sign: Read Before Writing
- **Trigger**: Before modifying any file
- **Instruction**: Always read the existing file first
- **Added after**: Core principle

### Sign: Test After Changes
- **Trigger**: After any code change
- **Instruction**: Run tests to verify nothing broke
- **Added after**: Core principle

### Sign: Commit Checkpoints
- **Trigger**: Before risky changes
- **Instruction**: Commit current working state first
- **Added after**: Core principle

---

## Learned Signs

EOF
  fi

  # Initialize errors.log
  if [[ ! -f "$ralph_dir/errors.log" ]]; then
    cat > "$ralph_dir/errors.log" << 'EOF'
# Error Log

> Failures detected by stream-parser. Use to update guardrails.

EOF
  fi

  # Initialize activity.log
  if [[ ! -f "$ralph_dir/activity.log" ]]; then
    cat > "$ralph_dir/activity.log" << 'EOF'
# Activity Log

> Real-time tool call logging from stream-parser.

EOF
  fi
}

# =============================================================================
# TASK MANAGEMENT
# =============================================================================

check_task_complete() {
  local workspace="$1"
  local task_file="$workspace/RALPH_TASK.md"

  if [[ ! -f "$task_file" ]]; then
    echo "NO_TASK_FILE"
    return
  fi

  local unchecked
  unchecked=$(grep -cE '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+\[ \]' "$task_file" 2>/dev/null) || unchecked=0

  if [[ "$unchecked" -eq 0 ]]; then
    echo "COMPLETE"
  else
    echo "INCOMPLETE:$unchecked"
  fi
}

count_criteria() {
  local workspace="${1:-.}"
  local task_file="$workspace/RALPH_TASK.md"

  if [[ ! -f "$task_file" ]]; then
    echo "0:0"
    return
  fi

  local total done_count
  total=$(grep -cE '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+\[(x| )\]' "$task_file" 2>/dev/null) || total=0
  done_count=$(grep -cE '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+\[x\]' "$task_file" 2>/dev/null) || done_count=0

  echo "$done_count:$total"
}

# =============================================================================
# PROMPT BUILDING
# =============================================================================

build_prompt() {
  local workspace="$1"
  local iteration="$2"

  cat << EOF
# Ralph Iteration $iteration

You are an autonomous development agent using the Ralph methodology with Claude Code.

## FIRST: Read State Files

Before doing anything:
1. Read \`RALPH_TASK.md\` - your task and completion criteria
2. Read \`.ralph/guardrails.md\` - lessons from past failures (FOLLOW THESE)
3. Read \`.ralph/progress.md\` - what's been accomplished
4. Read \`.ralph/errors.log\` - recent failures to avoid

## Working Directory (Critical)

You are already in a git repository. Work HERE, not in a subdirectory:
- Do NOT run \`git init\` - the repo already exists
- Do NOT run scaffolding commands that create nested directories
- All code should live at the repo root or in subdirectories you create manually

## Git Protocol (Critical)

Commit early and often - your commits ARE your memory:

1. After completing each criterion:
   \`git add -A && git commit -m 'ralph: implement [specific thing]'\`
2. After any significant code change: commit with descriptive message
3. Before any risky refactor: commit current state as checkpoint
4. Push after every 2-3 commits: \`git push\`

## Task Execution

1. Work on the next unchecked criterion in RALPH_TASK.md (look for \`[ ]\`)
2. Run tests after changes (check RALPH_TASK.md for test_command)
3. **Mark completed criteria**: Edit RALPH_TASK.md and change \`[ ]\` to \`[x]\`
4. Update \`.ralph/progress.md\` with what you accomplished
5. When ALL criteria show \`[x]\`: output \`<ralph>COMPLETE</ralph>\`
6. If stuck 3+ times on same issue: output \`<ralph>GUTTER</ralph>\`

## Learning from Failures

When something fails:
1. Check \`.ralph/errors.log\` for failure history
2. Figure out the root cause
3. Add a Sign to \`.ralph/guardrails.md\` using this format:

\`\`\`
### Sign: [Descriptive Name]
- **Trigger**: When this situation occurs
- **Instruction**: What to do instead
- **Added after**: Iteration $iteration - what happened
\`\`\`

## Context Rotation Warning

You may receive a warning that context is running low. When you see it:
1. Finish your current file edit
2. Commit and push your changes
3. Update .ralph/progress.md with what you accomplished and what's next
4. You will be rotated to a fresh agent that continues your work

Begin by reading the state files.
EOF
}

# =============================================================================
# SPINNER (Warp-compatible)
# =============================================================================

spinner() {
  local workspace="$1"
  local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
  local i=0
  while true; do
    # Use \r for in-place update (works in Warp)
    printf "\r  🐛 Claude working... %s  (tail -f %s/.ralph/activity.log)" "${spin:i++%${#spin}:1}" "$workspace" >&2
    sleep 0.1
  done
}

# =============================================================================
# ITERATION RUNNER
# =============================================================================

run_iteration() {
  local workspace="$1"
  local iteration="$2"
  local session_id="${3:-}"
  local script_dir="${4:-$(dirname "${BASH_SOURCE[0]}")}"

  local prompt=$(build_prompt "$workspace" "$iteration")
  local fifo="$workspace/.ralph/.parser_fifo"

  rm -f "$fifo"
  mkfifo "$fifo"

  echo "" >&2
  echo "═══════════════════════════════════════════════════════════════════" >&2
  echo "🐛 Ralph Iteration $iteration" >&2
  echo "═══════════════════════════════════════════════════════════════════" >&2
  echo "" >&2
  echo "Workspace: $workspace" >&2
  echo "Model:     $MODEL" >&2
  echo "Monitor:   tail -f $workspace/.ralph/activity.log" >&2
  echo "" >&2

  log_progress "$workspace" "**Session $iteration started** (model: $MODEL)"

  cd "$workspace"

  # Start spinner
  spinner "$workspace" &
  local spinner_pid=$!

  # Build Claude command
  local claude_cmd="claude -p --output-format stream-json --model $MODEL"

  # Add resume flag if continuing session
  if [[ -n "$session_id" ]]; then
    echo "Resuming session: $session_id" >&2
    claude_cmd="$claude_cmd --resume $session_id"
  fi

  # Run Claude with stream parsing
  (
    echo "$prompt" | eval "$claude_cmd" 2>&1 | "$script_dir/stream-parser.sh" "$workspace" > "$fifo"
  ) &
  local agent_pid=$!

  # Read signals from parser
  local signal=""
  while IFS= read -r line; do
    case "$line" in
      "ROTATE")
        printf "\r\033[K" >&2
        echo "🔄 Context rotation triggered - stopping agent..." >&2
        kill $agent_pid 2>/dev/null || true
        signal="ROTATE"
        break
        ;;
      "WARN")
        printf "\r\033[K" >&2
        echo "⚠️  Context warning - agent should wrap up soon..." >&2
        ;;
      "GUTTER")
        printf "\r\033[K" >&2
        echo "🚨 Gutter detected - agent may be stuck..." >&2
        signal="GUTTER"
        ;;
      "COMPLETE")
        printf "\r\033[K" >&2
        echo "✅ Agent signaled completion!" >&2
        signal="COMPLETE"
        ;;
    esac
  done < "$fifo"

  wait $agent_pid 2>/dev/null || true

  kill $spinner_pid 2>/dev/null || true
  wait $spinner_pid 2>/dev/null || true
  printf "\r\033[K" >&2

  rm -f "$fifo"

  echo "$signal"
}

# =============================================================================
# MAIN LOOP
# =============================================================================

run_ralph_loop() {
  local workspace="$1"
  local script_dir="${2:-$(dirname "${BASH_SOURCE[0]}")}"

  cd "$workspace"
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    echo "📦 Committing uncommitted changes..."
    git add -A
    git commit -m "ralph: initial commit before loop" || true
  fi

  if [[ -n "$USE_BRANCH" ]]; then
    echo "🌿 Creating branch: $USE_BRANCH"
    git checkout -b "$USE_BRANCH" 2>/dev/null || git checkout "$USE_BRANCH"
  fi

  echo ""
  echo "🚀 Starting Ralph loop with Claude Code..."
  echo ""

  local iteration=1
  local session_id=""

  while [[ $iteration -le $MAX_ITERATIONS ]]; do
    local signal
    signal=$(run_iteration "$workspace" "$iteration" "$session_id" "$script_dir")

    local task_status
    task_status=$(check_task_complete "$workspace")

    if [[ "$task_status" == "COMPLETE" ]]; then
      log_progress "$workspace" "**Session $iteration ended** - ✅ TASK COMPLETE"
      echo ""
      echo "═══════════════════════════════════════════════════════════════════"
      echo "🎉 RALPH COMPLETE! All criteria satisfied."
      echo "═══════════════════════════════════════════════════════════════════"
      echo ""
      echo "Completed in $iteration iteration(s)."

      if [[ "$OPEN_PR" == "true" ]] && [[ -n "$USE_BRANCH" ]]; then
        echo ""
        echo "📝 Opening pull request..."
        git push -u origin "$USE_BRANCH" 2>/dev/null || git push
        if command -v gh &> /dev/null; then
          gh pr create --fill || echo "⚠️  Could not create PR automatically."
        fi
      fi

      return 0
    fi

    case "$signal" in
      "COMPLETE")
        if [[ "$task_status" == "COMPLETE" ]]; then
          log_progress "$workspace" "**Session $iteration ended** - ✅ TASK COMPLETE"
          echo ""
          echo "🎉 RALPH COMPLETE!"
          return 0
        else
          log_progress "$workspace" "**Session $iteration ended** - Agent signaled complete but criteria remain"
          echo "⚠️  Agent signaled completion but unchecked criteria remain. Continuing..."
          iteration=$((iteration + 1))
        fi
        ;;
      "ROTATE")
        log_progress "$workspace" "**Session $iteration ended** - 🔄 Context rotation"
        echo ""
        echo "🔄 Rotating to fresh context..."
        iteration=$((iteration + 1))
        session_id=""
        ;;
      "GUTTER")
        log_progress "$workspace" "**Session $iteration ended** - 🚨 GUTTER"
        echo ""
        echo "🚨 Gutter detected. Check .ralph/errors.log for details."
        return 1
        ;;
      *)
        if [[ "$task_status" == INCOMPLETE:* ]]; then
          local remaining_count=${task_status#INCOMPLETE:}
          log_progress "$workspace" "**Session $iteration ended** - $remaining_count criteria remaining"
          echo "📋 $remaining_count criteria remaining. Starting next iteration..."
          iteration=$((iteration + 1))
        fi
        ;;
    esac

    sleep 2
  done

  log_progress "$workspace" "**Loop ended** - ⚠️ Max iterations reached"
  echo "⚠️  Max iterations ($MAX_ITERATIONS) reached."
  return 1
}

# =============================================================================
# PREREQUISITES
# =============================================================================

check_prerequisites() {
  local workspace="$1"
  local task_file="$workspace/RALPH_TASK.md"

  if [[ ! -f "$task_file" ]]; then
    echo "❌ No RALPH_TASK.md found in $workspace"
    echo ""
    echo "Create a task file first. See templates/RALPH_TASK.template.md"
    return 1
  fi

  # Check for Claude CLI
  if ! command -v claude &> /dev/null; then
    echo "❌ Claude Code CLI not found"
    echo ""
    echo "Install via: npm install -g @anthropic-ai/claude-code"
    return 1
  fi

  if ! git -C "$workspace" rev-parse --git-dir > /dev/null 2>&1; then
    echo "❌ Not a git repository"
    return 1
  fi

  return 0
}

# =============================================================================
# DISPLAY
# =============================================================================

show_banner() {
  echo "═══════════════════════════════════════════════════════════════════"
  echo "🐛 Ralph Wiggum for Claude Code"
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
  echo "  \"That's the beauty of Ralph - the technique is deterministically"
  echo "   bad in an undeterministic world.\""
  echo ""
  echo "═══════════════════════════════════════════════════════════════════"
  echo ""
}

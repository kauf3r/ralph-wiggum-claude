#!/bin/bash
# Ralph Wiggum for Claude Code: The Loop
#
# Main entry point for running Ralph with Claude Code CLI.
# Adapted from ralph-wiggum-cursor for use with Warp terminal.
#
# Usage:
#   ./ralph-loop.sh                              # Current directory
#   ./ralph-loop.sh /path/to/project             # Specific project
#   ./ralph-loop.sh -n 50 -m opus                # Custom iterations and model
#   ./ralph-loop.sh --branch feature/foo --pr   # Create branch and PR
#
# Flags:
#   -n, --iterations N     Max iterations (default: 20)
#   -m, --model MODEL      Model to use: sonnet, opus, haiku (default: sonnet)
#   --branch NAME          Create and work on a new branch
#   --pr                   Open PR when complete (requires --branch)
#   -y, --yes              Skip confirmation prompt
#   -h, --help             Show this help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
source "$SCRIPT_DIR/ralph-common.sh"

# =============================================================================
# FLAG PARSING
# =============================================================================

show_help() {
  cat << 'EOF'
Ralph Wiggum for Claude Code

An autonomous development loop using Claude Code CLI with deliberate
context management. State persists in git and .ralph/ files.

USAGE:
  ./ralph-loop.sh [options] [workspace]

OPTIONS:
  -n, --iterations N     Max iterations (default: 20)
  -m, --model MODEL      Model: sonnet, opus, haiku (default: sonnet)
  --branch NAME          Create and work on a new branch
  --pr                   Open PR when complete (requires --branch)
  -y, --yes              Skip confirmation prompt
  -h, --help             Show this help

EXAMPLES:
  ./ralph-loop.sh                                    # Start in current dir
  ./ralph-loop.sh -n 50                              # 50 iterations max
  ./ralph-loop.sh -m opus                            # Use Opus model
  ./ralph-loop.sh --branch feature/api --pr -y      # Scripted PR workflow

ENVIRONMENT:
  RALPH_MODEL            Override default model (same as -m flag)
  WARN_THRESHOLD         Tokens before warning (default: 150000)
  ROTATE_THRESHOLD       Tokens before rotation (default: 180000)

WARP TIPS:
  - Use Warp's command blocks to see each iteration clearly
  - Run `tail -f .ralph/activity.log` in a split pane
  - Use Warp workflows to save common ralph-loop invocations

For the full Ralph philosophy, see: https://ghuntley.com/ralph/
EOF
}

# Parse command line arguments
WORKSPACE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--iterations)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    -m|--model)
      MODEL="$2"
      shift 2
      ;;
    --branch)
      USE_BRANCH="$2"
      shift 2
      ;;
    --pr)
      OPEN_PR=true
      shift
      ;;
    -y|--yes)
      SKIP_CONFIRM=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    -*)
      echo "Unknown option: $1"
      echo "Use -h for help."
      exit 1
      ;;
    *)
      WORKSPACE="$1"
      shift
      ;;
  esac
done

# =============================================================================
# MAIN
# =============================================================================

main() {
  # Resolve workspace
  if [[ -z "$WORKSPACE" ]]; then
    WORKSPACE="$(pwd)"
  elif [[ "$WORKSPACE" == "." ]]; then
    WORKSPACE="$(pwd)"
  else
    WORKSPACE="$(cd "$WORKSPACE" && pwd)"
  fi

  local task_file="$WORKSPACE/RALPH_TASK.md"

  show_banner

  if ! check_prerequisites "$WORKSPACE"; then
    exit 1
  fi

  if [[ "$OPEN_PR" == "true" ]] && [[ -z "$USE_BRANCH" ]]; then
    echo "❌ --pr requires --branch"
    exit 1
  fi

  init_ralph_dir "$WORKSPACE"

  echo "Workspace: $WORKSPACE"
  echo "Task:      $task_file"
  echo ""

  echo "📋 Task Summary:"
  echo "─────────────────────────────────────────────────────────────────"
  head -30 "$task_file"
  echo "─────────────────────────────────────────────────────────────────"
  echo ""

  local total_criteria done_criteria remaining
  total_criteria=$(grep -cE '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+\[(x| )\]' "$task_file" 2>/dev/null) || total_criteria=0
  done_criteria=$(grep -cE '^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+\[x\]' "$task_file" 2>/dev/null) || done_criteria=0
  remaining=$((total_criteria - done_criteria))

  echo "Progress: $done_criteria / $total_criteria criteria complete ($remaining remaining)"
  echo "Model:    $MODEL"
  echo "Max iter: $MAX_ITERATIONS"
  [[ -n "$USE_BRANCH" ]] && echo "Branch:   $USE_BRANCH"
  [[ "$OPEN_PR" == "true" ]] && echo "Open PR:  Yes"
  echo ""

  if [[ "$remaining" -eq 0 ]] && [[ "$total_criteria" -gt 0 ]]; then
    echo "🎉 Task already complete! All criteria are checked."
    exit 0
  fi

  if [[ "$SKIP_CONFIRM" != "true" ]]; then
    echo "This will run Claude Code locally to work on this task."
    echo "The agent will be rotated when context fills up (~180k tokens)."
    echo ""
    echo "📺 Monitor progress: tail -f $WORKSPACE/.ralph/activity.log"
    echo ""
    read -p "Start Ralph loop? [y/N] " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Aborted."
      exit 0
    fi
  fi

  run_ralph_loop "$WORKSPACE" "$SCRIPT_DIR"
  exit $?
}

main

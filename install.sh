#!/bin/bash
# Ralph Wiggum for Claude Code - Installer
#
# Installs Ralph scripts into your project directory.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/kauf3r/ralph-wiggum-claude/main/install.sh | bash
#
# Or:
#   ./install.sh [target-directory]

set -euo pipefail

TARGET="${1:-.}"

echo "🐛 Installing Ralph Wiggum for Claude Code..."
echo ""

# Create directories
mkdir -p "$TARGET/.cursor/ralph-scripts"
mkdir -p "$TARGET/.ralph"

# Download scripts
REPO_URL="https://raw.githubusercontent.com/kauf3r/ralph-wiggum-claude/main"

if command -v curl &> /dev/null; then
  curl -fsSL "$REPO_URL/scripts/ralph-common.sh" -o "$TARGET/.cursor/ralph-scripts/ralph-common.sh"
  curl -fsSL "$REPO_URL/scripts/ralph-loop.sh" -o "$TARGET/.cursor/ralph-scripts/ralph-loop.sh"
  curl -fsSL "$REPO_URL/scripts/stream-parser.sh" -o "$TARGET/.cursor/ralph-scripts/stream-parser.sh"
  curl -fsSL "$REPO_URL/templates/RALPH_TASK.template.md" -o "$TARGET/RALPH_TASK.md"
elif command -v wget &> /dev/null; then
  wget -q "$REPO_URL/scripts/ralph-common.sh" -O "$TARGET/.cursor/ralph-scripts/ralph-common.sh"
  wget -q "$REPO_URL/scripts/ralph-loop.sh" -O "$TARGET/.cursor/ralph-scripts/ralph-loop.sh"
  wget -q "$REPO_URL/scripts/stream-parser.sh" -O "$TARGET/.cursor/ralph-scripts/stream-parser.sh"
  wget -q "$REPO_URL/templates/RALPH_TASK.template.md" -O "$TARGET/RALPH_TASK.md"
else
  echo "❌ Neither curl nor wget found. Please install one."
  exit 1
fi

# Make scripts executable
chmod +x "$TARGET/.cursor/ralph-scripts/"*.sh

# Initialize .ralph directory
if [[ ! -f "$TARGET/.ralph/progress.md" ]]; then
  cat > "$TARGET/.ralph/progress.md" << 'EOF'
# Progress Log

> Updated by the agent after significant work.

---

## Session History

EOF
fi

if [[ ! -f "$TARGET/.ralph/guardrails.md" ]]; then
  cat > "$TARGET/.ralph/guardrails.md" << 'EOF'
# Ralph Guardrails (Signs)

> Lessons learned from past failures. READ THESE BEFORE ACTING.

## Core Signs

### Sign: Read Before Writing
- **Trigger**: Before modifying any file
- **Instruction**: Always read the existing file first

### Sign: Test After Changes
- **Trigger**: After any code change
- **Instruction**: Run tests to verify nothing broke

### Sign: Commit Checkpoints
- **Trigger**: Before risky changes
- **Instruction**: Commit current working state first

---

## Learned Signs

EOF
fi

echo "✅ Ralph installed successfully!"
echo ""
echo "Files created:"
echo "  $TARGET/.cursor/ralph-scripts/ralph-loop.sh    # Main script"
echo "  $TARGET/.cursor/ralph-scripts/ralph-common.sh  # Shared functions"
echo "  $TARGET/.cursor/ralph-scripts/stream-parser.sh # Token tracking"
echo "  $TARGET/RALPH_TASK.md                          # Your task file"
echo "  $TARGET/.ralph/                                # State directory"
echo ""
echo "Next steps:"
echo "  1. Edit RALPH_TASK.md with your task and success criteria"
echo "  2. Run: ./.cursor/ralph-scripts/ralph-loop.sh"
echo ""
echo "For Warp users:"
echo "  - Use split panes: one for ralph-loop, one for tail -f .ralph/activity.log"
echo "  - Save as a Warp workflow for quick access"
echo ""

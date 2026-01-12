# Ralph Wiggum for Claude Code

An adaptation of [Geoffrey Huntley's Ralph Wiggum technique](https://ghuntley.com/ralph/) for **Claude Code CLI**, optimized for use with **Warp terminal**.

> "That's the beauty of Ralph - the technique is deterministically bad in an undeterministic world."

## What is Ralph?

Ralph is a technique for autonomous AI development that treats LLM context like memory:

```bash
while :; do cat PROMPT.md | claude ; done
```

The same prompt is fed repeatedly to Claude Code. Progress persists in **files and git**, not in the LLM's context window. When context fills up, you get a fresh agent with fresh context.

### Key Differences from Original

| Feature | cursor-agent version | This Claude Code version |
|---------|---------------------|-------------------------|
| CLI | `cursor-agent` | `claude` |
| Token tracking | Estimated from bytes | **Exact counts from API** |
| Context limit | 80k tokens | 180k tokens (Claude's 200k window) |
| Cost tracking | None | **Actual USD cost from API** |
| Terminal | Any | Optimized for **Warp** |

## Quick Start

### 1. Install

```bash
cd your-project
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/ralph-wiggum-claude/main/install.sh | bash
```

Or clone and copy:
```bash
git clone https://github.com/YOUR_USERNAME/ralph-wiggum-claude.git
cp -r ralph-wiggum-claude/scripts your-project/.cursor/ralph-scripts
cp ralph-wiggum-claude/templates/RALPH_TASK.template.md your-project/RALPH_TASK.md
```

### 2. Define Your Task

Edit `RALPH_TASK.md`:

```markdown
---
task: Build a REST API
test_command: "npm test"
---

# Task: REST API

Build a REST API with user management.

## Success Criteria

1. [ ] GET /health returns 200
2. [ ] POST /users creates a user
3. [ ] GET /users/:id returns user
4. [ ] All tests pass
```

### 3. Start the Loop

```bash
./.cursor/ralph-scripts/ralph-loop.sh
```

### 4. Monitor (Warp Pro Tip)

In Warp, split your terminal:
- **Left pane**: Ralph loop running
- **Right pane**: `tail -f .ralph/activity.log`

## How It Works

```
Iteration 1                    Iteration 2                    Iteration N
┌──────────────────┐          ┌──────────────────┐          ┌──────────────────┐
│ Fresh context    │          │ Fresh context    │          │ Fresh context    │
│       │          │          │       │          │          │       │          │
│       ▼          │          │       ▼          │          │       ▼          │
│ Read RALPH_TASK  │          │ Read RALPH_TASK  │          │ Read RALPH_TASK  │
│ Read guardrails  │──────────│ Read guardrails  │──────────│ Read guardrails  │
│ Read progress    │  (state  │ Read progress    │  (state  │ Read progress    │
│       │          │  in git) │       │          │  in git) │       │          │
│       ▼          │          │       ▼          │          │       ▼          │
│ Work on criteria │          │ Work on criteria │          │ Work on criteria │
│ Commit to git    │          │ Commit to git    │          │ Commit to git    │
│       │          │          │       │          │          │       │          │
│       ▼          │          │       ▼          │          │       ▼          │
│ 180k tokens      │          │ 180k tokens      │          │ All [x] done!    │
│ ROTATE ──────────┼──────────┼──────────────────┼──────────┼──► COMPLETE      │
└──────────────────┘          └──────────────────┘          └──────────────────┘
```

Each iteration:
1. Reads task and state from files (not from previous context)
2. Works on unchecked criteria
3. Commits progress to git
4. Updates `.ralph/progress.md` and `.ralph/guardrails.md`
5. Rotates when context approaches limit

## Commands

```bash
# Basic usage
./ralph-loop.sh

# With options
./ralph-loop.sh -n 50                    # Max 50 iterations
./ralph-loop.sh -m opus                  # Use Opus model
./ralph-loop.sh --branch feature/x --pr  # Create branch and PR
./ralph-loop.sh -y                       # Skip confirmation
```

## File Structure

```
your-project/
├── .cursor/ralph-scripts/      # Ralph scripts
│   ├── ralph-loop.sh           # Main entry point
│   ├── ralph-common.sh         # Shared functions
│   └── stream-parser.sh        # Token/cost tracking
├── .ralph/                     # State files
│   ├── progress.md             # What's been done
│   ├── guardrails.md           # Lessons learned (Signs)
│   ├── activity.log            # Tool call log
│   └── errors.log              # Failure log
└── RALPH_TASK.md               # Your task definition
```

## Warp Integration Tips

### Save as Warp Workflow

Create a Warp workflow for quick access:

```yaml
name: Ralph Loop
command: ./.cursor/ralph-scripts/ralph-loop.sh
```

### Split Panes Setup

1. Start ralph-loop in main pane
2. `Cmd+D` to split vertically
3. `tail -f .ralph/activity.log` in right pane

### Use Warp AI for Debugging

If Ralph gets stuck, use Warp AI to analyze:
- `.ralph/errors.log` - What failed
- `.ralph/guardrails.md` - What it learned
- `git log --oneline` - What it accomplished

## Context Health Indicators

The activity log shows context health:

| Emoji | Status | Token % |
|-------|--------|---------|
| 🟢 | Healthy | < 60% |
| 🟡 | Warning | 60-80% |
| 🔴 | Critical | > 80% |

Example:
```
[12:34:56] 🟢 READ src/index.ts
[12:40:22] 🟡 TOKENS: 135,000 / 180,000 (75%) - approaching limit
[12:45:33] 🔴 ROTATE: Token threshold reached
```

## The Learning Loop (Signs)

When something fails, Claude adds a "Sign" to `.ralph/guardrails.md`:

```markdown
### Sign: Check imports before adding
- **Trigger**: Adding a new import statement
- **Instruction**: First check if import already exists
- **Added after**: Iteration 3 - duplicate import caused build failure
```

Future iterations read guardrails first and follow them.

## When to Use Ralph

**Good for:**
- Well-defined tasks with clear success criteria
- Tasks requiring iteration (e.g., getting tests to pass)
- Greenfield projects where you can walk away
- Tasks with automatic verification

**Not good for:**
- Tasks requiring human judgment
- One-shot operations
- Unclear success criteria
- Production debugging

## Credits

- **Original technique**: [Geoffrey Huntley](https://ghuntley.com/ralph/)
- **Cursor port**: [Agrim Singh](https://github.com/agrimsingh/ralph-wiggum-cursor)
- **Claude Code adaptation**: This repo

## License

MIT

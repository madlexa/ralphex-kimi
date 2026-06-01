# ralphex-kimi

Kimi CLI wrapper for [ralphex](https://github.com/umputun/ralphex) — use Kimi Code CLI instead of Claude Code for autonomous plan execution.

## What is this?

[ralphex](https://github.com/umputun/ralphex) is an autonomous AI-driven plan execution tool. By default it uses Claude Code, but it supports any CLI that produces compatible `stream-json` output via a wrapper script.

This wrapper translates Kimi CLI's `--print --output-format stream-json` output into Claude-compatible stream-json events, allowing Kimi to drive ralphex task execution and review phases.

## Prerequisites

- [ralphex](https://github.com/umputun/ralphex) installed
- [Kimi CLI](https://github.com/MoonshotAI/kimi-cli) installed and authenticated (`kimi login`)
- `jq` installed (`brew install jq`)

## Quick Start

### Install in your project

```bash
cd /path/to/your-project

# Initialize ralphex if this is a new project
ralphex --init

# Clone this repo
git clone https://github.com/madlexa/ralphex-kimi.git /tmp/ralphex-kimi

# Switch to Kimi
bash /tmp/ralphex-kimi/install.sh kimi

# Commit the generated .ralphex config and wrapper so ralphex sees a clean worktree
git add .ralphex && git commit -m "Configure ralphex Kimi executor"

# Done! Now use ralphex as usual
ralphex docs/plans/your-plan.md
```

### One-liner install (without cloning)

```bash
cd /path/to/your-project

# Download both files to a temp directory and run installer
mkdir -p /tmp/ralphex-kimi
curl -sL https://raw.githubusercontent.com/madlexa/ralphex-kimi/main/kimi-as-claude.sh -o /tmp/ralphex-kimi/kimi-as-claude.sh
curl -sL https://raw.githubusercontent.com/madlexa/ralphex-kimi/main/install.sh -o /tmp/ralphex-kimi/install.sh
bash /tmp/ralphex-kimi/install.sh kimi
```

### Switch back to Claude Code

```bash
bash /tmp/ralphex-kimi/install.sh original
```

## Manual Installation

If you prefer to set things up manually:

1. Copy `kimi-as-claude.sh` to `.ralphex/scripts/` in your project:
   ```bash
   cp kimi-as-claude.sh /path/to/your-project/.ralphex/scripts/
   chmod +x /path/to/your-project/.ralphex/scripts/kimi-as-claude.sh
   ```

2. Update `.ralphex/config`:
   ```ini
   claude_command = .ralphex/scripts/kimi-as-claude.sh
   claude_args =
   ```

## Model Selection

Set the `KIMI_MODEL` environment variable to choose a specific model:

```bash
export KIMI_MODEL=kimi-k2.5
```

Or use the `--model` flag (passed through from ralphex's `--task-model`):

```bash
ralphex --task-model=kimi-k2.5 docs/plans/feature.md
```

## Verbose Mode

Set `KIMI_VERBOSE=1` to include Kimi's thinking blocks in the output:

```bash
export KIMI_VERBOSE=1
```

## How It Works

1. ralphex passes the task/review prompt to `kimi-as-claude.sh` via stdin
2. The wrapper runs `kimi --print --output-format stream-json --yolo` with the prompt
3. Kimi executes autonomously (tools are auto-approved via `--yolo`)
4. The wrapper translates Kimi's JSONL output to Claude-compatible `stream-json`:
   - Array content: `{"role":"assistant","content":[{"type":"text","text":"..."}]}` → `{"type":"content_block_delta","delta":{"type":"text_delta","text":"..."}}`
   - String content: `{"role":"assistant","content":"..."}` → `{"type":"content_block_delta","delta":{"type":"text_delta","text":"..."}}`
5. ralphex receives the translated stream and processes it normally

## Error Handling

If Kimi fails (e.g., invalid model, rate limit), the wrapper:
- Preserves Kimi's stderr (excluding harmless "To resume this session" lines)
- Propagates Kimi's exit code to ralphex
- Does **not** emit a fake success `result` event

This allows ralphex to retry or report the error correctly.

## Why Kimi?

- **No Anthropic Agent SDK billing** — Kimi uses its own subscription/API
- **Different reasoning style** — Kimi K2.5 often catches issues Claude misses
- **Large context window** — up to 262k tokens
- **Native tool use** — shell, file read/write, search

## License

MIT

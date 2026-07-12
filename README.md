# Bash Agent

A minimal AI agent loop written entirely in bash — under 60 lines. It calls LLMs via OpenRouter, runs tools (bash, read, write, edit), and can import skills from the [pi agent skills](https://github.com/earendil-works/pi-coding-agent) library.

## Files

| File | Lines | Purpose |
|------|-------|---------|
| `agent.sh` | 56 | Main agent loop — REPL, LLM calls, tool execution |
| `skills.sh` | 58 | Skill importer — lists and loads pi agent skills |

## Quick Start

```bash
cd /Users/kane/workspaces/bash-agent
source ./skills.sh           # list available skills
source ./skills.sh clean-code  # import a skill
./agent.sh                   # start the agent loop
```

You need at least one API key set in your environment (see [Environment variables](#environment-variables) below).

## Usage

### `agent.sh`

An interactive REPL that:

1. Reads your input
2. Sends it (with conversation history) to an LLM via OpenRouter
3. If the LLM returns tool calls, executes them and feeds results back
4. Repeats until the LLM returns a text response

**Environment variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `PROVIDER` | _(auto-detect)_ | Force a provider: `openrouter`, `deepseek`, `openai`, or `anthropic` |
| `MODEL` | _(per provider, see below)_ | Model ID (e.g. `gpt-4o`, `deepseek-v4-flash`, `claude-sonnet-4-20250514`) |
| `SYSTEM_PROMPT` | `You are a helpful assistant in a bash environment.` | System prompt |
| `OPENROUTER_API_KEY` | — | API key for OpenRouter |
| `DEEPSEEK_API_KEY` | — | API key for DeepSeek |
| `OPENAI_API_KEY` | — | API key for OpenAI |
| `ANTHROPIC_API_KEY` | — | API key for Anthropic |

**Provider auto-detection**: If `PROVIDER` is not set, the agent checks which API keys are available and picks the first match in this order: OpenRouter → DeepSeek → OpenAI → Anthropic. If you have multiple keys, set `PROVIDER` explicitly to choose one.

**Default models per provider**:

| Provider | Default Model |
|----------|---------------|
| OpenRouter | `openrouter/free` |
| DeepSeek | `deepseek-v4-flash` |
| OpenAI | `gpt-4o` |
| Anthropic | `claude-sonnet-4-20250514` |

All providers are accessed via OpenAI-compatible chat completions endpoints. Anthropic is routed through its [`/v1/openai/chat/completions`](https://docs.anthropic.com/en/api/openai-compatible) proxy so the request format is identical across all four.

**Tool calls** — the LLM can use these tools:

- `bash` — run any bash command
- `read` — read a file
- `write` — write content to a file (overwrites)
- `edit` — replace exact text in a file

Type `exit` to quit.

### `skills.sh`

Import pi agent skills into your bash agent session. Must be sourced (not executed) so the environment persists.

```bash
source ./skills.sh                    # list all skills
source ./skills.sh clean-code         # import one skill
source ./skills.sh kanban-board tdd   # import multiple
source ./skills.sh --help             # usage
```

When a skill is imported:

- Its **SKILL.md** metadata is read (exports `$BASH_AGENT_SKILL`)
- Any **bash scripts** in `scripts/` are sourced (functions become available)
- The agent can then reference the skill in its system prompt or use its functions

## Architecture

```
┌─────────────────────────────────────┐
│         agent.sh (REPL loop)        │
│                                     │
│  > your input                       │
│       ↓                             │
│  ┌─────────────────────────┐        │
│  │  LLM (OpenRouter /       │        │
│  │  DeepSeek / OpenAI /     │        │
│  │  Anthropic)              │        │
│  │  ← text or tool calls   │        │
│  └─────────┬───────────────┘        │
│            ↓                        │
│  tool calls → run_tool() → result   │
│  result → history → back to LLM     │
│                                     │
│  skills.sh ← loaded before start    │
└─────────────────────────────────────┘
```

## Requirements

- `bash 4+` (for `mapfile` support)
- `curl` — API calls
- `jq` — JSON manipulation
- At least one API key: `OPENROUTER_API_KEY`, `DEEPSEEK_API_KEY`, `OPENAI_API_KEY`, or `ANTHROPIC_API_KEY`

## License

MIT

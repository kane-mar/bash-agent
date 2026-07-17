# Bash Agent

A minimal AI agent loop written entirely in bash (~76 lines). It calls LLMs via OpenRouter, DeepSeek, or OpenAI, runs tools (bash, read, write, edit), and can import skills from the [pi agent skills](https://github.com/earendil-works/pi-coding-agent) library.

## Files

| File | Lines | Purpose |
|------|-------|---------|
| `agent.sh` | 76 | Main agent loop — bootstrap, config, tool runner, REPL |
| `skills.sh` | 63 | Skill importer — lists and loads pi agent skills |

## Installation

### Prerequisites

- **bash 3+** (for `pipefail` support)
- **curl** — API calls
- **jq** — JSON manipulation (install via `brew install jq` or `apt install jq`)
- **An API key** from one of the supported providers

### Install

```bash
git clone git@github.com:kane-mar/bash-agent.git
cd bash-agent

# Copy and edit your API key
cp .env.example .env
```

### Set your API key

Set at least one of these environment variables in `.env` or your shell profile:

```bash
# Option A: OpenRouter (recommended — access many models)
export OPENROUTER_API_KEY="sk-or-v1-..."

# Option B: DeepSeek
export DEEPSEEK_API_KEY="sk-..."

# Option C: OpenAI
export OPENAI_API_KEY="sk-..."
```

> **Tip:** If you have multiple keys, set `PROVIDER=openai` (or `deepseek` / `openrouter`) to pick which one to use. If unset, the agent auto-detects in order: OpenRouter → DeepSeek → OpenAI.

### Run

```bash
./agent.sh
```

You'll see a prompt like:

```
=== Agent [provider:openrouter model:openrouter/free skills:none] ===

>
```

### Try it out

```bash
> what files are in this directory?
```

The LLM will use its tools to explore, and you'll see tool calls and results stream back:

```
  ◆ bash {"command":"ls -la"}
total 32
...
```

Type `exit` to quit.

## Skills

Skills extend the agent with specialized capabilities from the [pi agent skills](https://github.com/earendil-works/pi-coding-agent) library. Install the skills library separately, then:

```bash
source ./skills.sh                 # list available skills
source ./skills.sh clean-code      # import a skill
./agent.sh                         # start the agent with the skill loaded
```

When a skill is imported, its instructions are automatically injected into the system prompt so the LLM knows how to use it.

## Usage

### `agent.sh`

An interactive REPL that:

1. Reads your input
2. Sends it (with conversation history) to an LLM
3. If the LLM returns tool calls, executes them and feeds results back
4. Repeats until the LLM returns a text response

**Environment variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `PROVIDER` | _(auto-detect)_ | Force a provider: `openrouter`, `deepseek`, or `openai` |
| `MODEL` | _(per provider, see below)_ | Model ID (e.g. `gpt-4o`, `deepseek-v4-flash`) |
| `SYSTEM_PROMPT` | `You are a coding agent... Work inside \$PWD. Be direct and thorough.` | System prompt |
| `OPENROUTER_API_KEY` | — | API key for OpenRouter |
| `DEEPSEEK_API_KEY` | — | API key for DeepSeek |
| `OPENAI_API_KEY` | — | API key for OpenAI |

**Default models per provider**:

| Provider | Default Model |
|----------|---------------|
| OpenRouter | `openrouter/free` |
| DeepSeek | `deepseek-v4-flash` |
| OpenAI | `gpt-4o` |

All providers are accessed via OpenAI-compatible chat completions endpoints.

**Tool calls** — the LLM can use these tools:

- `bash` — run any bash command
- `read` — read a file
- `write` — write content to a file (overwrites)
- `edit` — replace exact text in a file

Type `exit` to quit.

### `skills.sh`

Import pi agent skills. Must be sourced (not executed) so the environment persists.

```bash
source ./skills.sh                    # list all skills
source ./skills.sh clean-code         # import one skill
source ./skills.sh kanban-board tdd   # import multiple
source ./skills.sh --help             # usage
```

## Requirements

- `bash 3+` (for `pipefail` support)
- `curl` — API calls
- `jq` — JSON manipulation
- At least one API key: `OPENROUTER_API_KEY`, `DEEPSEEK_API_KEY`, or `OPENAI_API_KEY`

## Architecture

```
┌─────────────────────────────────────┐
│         agent.sh (REPL loop)        │
│                                     │
│  > your input                       │
│       ↓                             │
│  ┌─────────────────────────┐        │
│  │  LLM (OpenRouter /       │        │
│  │  DeepSeek / OpenAI)      │        │
│  │  ← text or tool calls   │        │
│  └─────────┬───────────────┘        │
│            ↓                        │
│  tool calls → run() → result        │
│  result → history → back to LLM     │
│                                     │
│  skills.sh ← loaded before start    │
└─────────────────────────────────────┘
```

### Phases

`agent.sh` runs in six sequential phases:

1. **Bootstrap** — loads `.env`, auto-detects provider from available API keys
2. **Config** — builds `SYSTEM_PROMPT` (base + optional skill injection) and `TOOLS` JSON
3. **Banner** — prints the agent startup line
4. **Tool runner** — `run()` dispatches `bash`, `read`, `write`, `edit`
5. **REPL loop** — reads input, calls LLM, executes tool calls, manages history
6. **Exit** — `exit` or `Ctrl+D` quits

## License

MIT

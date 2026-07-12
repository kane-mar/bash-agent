# Bash Agent

A minimal AI agent loop written entirely in bash (~84 lines). It calls LLMs via OpenRouter, DeepSeek, or OpenAI, runs tools (bash, read, write, edit), and can import skills from the [pi agent skills](https://github.com/earendil-works/pi-coding-agent) library.

## Files

| File | Lines | Purpose |
|------|-------|---------|
| `agent.sh` | 84 | Main agent loop — REPL, LLM calls, tool execution |
| `skills.sh` | 58 | Skill importer — lists and loads pi agent skills |

## Getting Started

### Prerequisites

- **bash 4+** (for `mapfile` support)
- **curl** — API calls
- **jq** — JSON manipulation
- **An API key** from one of the supported providers

### 1. Set your API key

Set at least one of these environment variables:

```bash
# Option A: OpenRouter (recommended — access many models)
export OPENROUTER_API_KEY="sk-or-v1-..."

# Option B: DeepSeek
export DEEPSEEK_API_KEY="sk-..."

# Option C: OpenAI
export OPENAI_API_KEY="sk-..."
```

> **Tip:** If you have multiple keys, set `PROVIDER=openai` (or `deepseek` / `openrouter`) to pick which one to use.

### 2. Clone and run

```bash
git clone git@github.com:kane-mar/bash-agent.git
cd bash-agent

# Start the agent
./agent.sh
```

You'll see a prompt like:

```
=== Agent [provider:openrouter model:openrouter/free skills:none] ===

>
```

### 3. Try it out

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

### Optional: Import skills

Skills extend the agent with specialized capabilities. They come from the [pi agent skills](https://github.com/earendil-works/pi-coding-agent) library and must be installed separately. Once available:

```bash
source ./skills.sh                 # list available skills
source ./skills.sh clean-code      # import a skill
./agent.sh                         # start the agent with the skill loaded
```

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
| `SYSTEM_PROMPT` | `You are a helpful assistant in a bash environment.` | System prompt |
| `OPENROUTER_API_KEY` | — | API key for OpenRouter |
| `DEEPSEEK_API_KEY` | — | API key for DeepSeek |
| `OPENAI_API_KEY` | — | API key for OpenAI |

**Provider auto-detection**: If `PROVIDER` is not set, the agent checks which API keys are available and picks the first match in this order: OpenRouter → DeepSeek → OpenAI. If you have multiple keys, set `PROVIDER` explicitly to choose one.

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
│  │  DeepSeek / OpenAI)      │        │
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
- At least one API key: `OPENROUTER_API_KEY`, `DEEPSEEK_API_KEY`, or `OPENAI_API_KEY`

## License

MIT
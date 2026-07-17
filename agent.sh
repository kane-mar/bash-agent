#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail
[ -f ".env" ] && source .env 2>/dev/null || true
if [ -z "${PROVIDER:-}" ]; then
    if [ -n "${OPENROUTER_API_KEY:-}" ]; then PROVIDER=openrouter
    elif [ -n "${DEEPSEEK_API_KEY:-}" ]; then PROVIDER=deepseek
    elif [ -n "${OPENAI_API_KEY:-}" ]; then PROVIDER=openai
    else echo "Set one of: OPENROUTER_API_KEY, DEEPSEEK_API_KEY, OPENAI_API_KEY" >&2; exit 1
    fi
fi
case "$PROVIDER" in
    openrouter) API_BASE="https://openrouter.ai/api/v1/chat/completions"; API_KEY="$OPENROUTER_API_KEY"; MODEL="${MODEL:-openrouter/free}" ;;
    deepseek)   API_BASE="https://api.deepseek.com/v1/chat/completions"; API_KEY="$DEEPSEEK_API_KEY"; MODEL="${MODEL:-deepseek-v4-flash}" ;;
    openai)     API_BASE="https://api.openai.com/v1/chat/completions"; API_KEY="$OPENAI_API_KEY"; MODEL="${MODEL:-gpt-4o}" ;;
    *) echo "Unknown PROVIDER: $PROVIDER (openrouter|deepseek|openai)" >&2; exit 1 ;;
esac
[ -z "$API_KEY" ] && { echo "Missing API key for $PROVIDER" >&2; exit 1; }
readonly W="$PWD"

# Build system prompt (base + optional skill injection)
S="${SYSTEM_PROMPT:-You are a coding agent in a bash environment with tools: bash, read, write, edit. Work inside $W. Be direct and thorough.}"
if [ -n "${BASH_AGENT_SKILL:-}" ]; then
    f="${SKILLS_DIR:-$HOME/.pi/agent/skills}/$BASH_AGENT_SKILL"
    if [ -f "$f/SKILL.md" ]; then f="$f/SKILL.md"; elif [ -f "$f.md" ]; then f="$f.md"; else unset f; fi
    if [ -n "${f:-}" ]; then
        body=$(awk 'BEGIN{n=0} /^---$/{n++;next} n>=1{print}' "$f")
        [ -n "$body" ] && S="$S"$'\n---\n## Loaded skill: '"$BASH_AGENT_SKILL"$'\n\n'"$body"
    fi
fi
readonly S

# Build tool definitions
T=$(jq -n -c '[
    {"type":"function","function":{"name":"bash","parameters":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}}},
    {"type":"function","function":{"name":"read","parameters":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}}},
    {"type":"function","function":{"name":"write","parameters":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}}},
    {"type":"function","function":{"name":"edit","parameters":{"type":"object","properties":{"path":{"type":"string"},"old_text":{"type":"string"},"new_text":{"type":"string"}},"required":["path","old_text","new_text"]}}}
]')
readonly T

echo "=== Agent [provider:$PROVIDER model:$MODEL skills:${BASH_AGENT_SKILL:-none}] ==="

# Tool runner
run() {
    local cmd="$1" a="$2"
    case "$cmd" in
        bash) local c; c=$(jq -r '.command // empty' <<<"$a" 2>/dev/null); [ -n "$c" ] || return 0; (cd "$W" && eval "$c") 2>&1 || true ;;
        read) local p; p=$(jq -r '.path // empty' <<<"$a" 2>/dev/null); local r; r="$(cd "$(dirname "$p")" 2>/dev/null && pwd)/$(basename "$p")"; case "$r" in "$W"/*|"$W");; *) echo "  error: path outside workspace"; return 1;; esac; [ -f "$p" ] && cat "$p" || { echo "  error: file not found: $p"; return 1; } ;;
        write) local p c; p=$(jq -r '.path // empty' <<<"$a" 2>/dev/null); c=$(jq -r '.content // empty' <<<"$a" 2>/dev/null); local r; r="$(cd "$(dirname "$p")" 2>/dev/null && pwd)/$(basename "$p")"; case "$r" in "$W"/*|"$W");; *) echo "  error: path outside workspace"; return 1;; esac; mkdir -p "$(dirname "$p")" && printf '%s' "$c" > "$p" ;;
        edit) local p o n; p=$(jq -r '.path // empty' <<<"$a" 2>/dev/null); o=$(jq -r '.old_text // empty' <<<"$a" 2>/dev/null); n=$(jq -r '.new_text // empty' <<<"$a" 2>/dev/null); local r; r="$(cd "$(dirname "$p")" 2>/dev/null && pwd)/$(basename "$p")"; case "$r" in "$W"/*|"$W");; *) echo "  error: path outside workspace"; return 1;; esac; [ -f "$p" ] || { echo "  error: file not found: $p"; return 1; }; sed -i '' "s/$(printf '%s' "$o" | sed 's/[\/&]/\\&/g')/$(printf '%s' "$n" | sed 's/[\/&]/\\&/g')/g" "$p" ;;
    esac
}

# REPL loop
H='[]'
while true; do
    printf "\n> " && read -r i || exit 0; [ -n "$i" ] || continue; [ "$i" = "exit" ] && exit 0
    H=$(echo "$H" | jq -c --arg c "$i" '.+[{"role":"user","content":$c}]')
    for ((r=0; r<10; r++)); do
        body=$(jq -n --arg m "$MODEL" --arg s "$S" --argjson t "$T" --argjson h "$H" '{model:$m,messages:([{role:"system",content:$s}]+$h),tools:$t,temperature:0.3,max_tokens:2000}')
        resp=$(curl -fsS "$API_BASE" -H "Content-Type: application/json" -H "Authorization: Bearer $API_KEY" -d "$body" 2>&1) || { echo "  error: API request failed: $resp"; exit 1; }
        choice=$(echo "$resp" | jq -c '.choices[0].message // empty')
        [ -z "$choice" ] && { echo "  error: API returned empty response"; exit 1; }
        if echo "$choice" | jq -e '.tool_calls' >/dev/null 2>&1; then
            H=$(echo "$H" | jq -c --argjson m "$choice" '.+[$m]')
            while IFS= read -r tc; do
                name=$(echo "$tc"|jq -r '.function.name'); id=$(echo "$tc"|jq -r '.id'); args=$(echo "$tc"|jq -r '.function.arguments')
                if ! echo "$args"|jq -e . >/dev/null 2>&1; then echo "  error: malformed arguments: $args"; H=$(echo "$H"|jq -c --arg id "$id" --arg err "malformed arguments: $args" '.+[{"role":"tool","tool_call_id":$id,"content":$err}]'); continue; fi
                printf "  ◆ %s %s\n" "$name" "$(echo "$args"|jq -c '.')"
                result=$(run "$name" "$args") || true; echo "$result"|head -5
                H=$(echo "$H"|jq -c --arg id "$id" --argjson content "$(echo "$result"|head -1000|jq -Rs '.')" '.+[{"role":"tool","tool_call_id":$id,"content":$content}]')
            done < <(echo "$choice"|jq -c '.tool_calls[]')
        else echo "$choice"|jq -r '.content // ""'; H=$(echo "$H"|jq -c --argjson m "$choice" '.+[$m]'); break
        fi
    done
done

#!/usr/bin/env bash
set -euo pipefail
export JQ_COLORS="1;30:0;37:0;37:0;37:0;32:1;37:1;37"

# ---- Select provider ----
if [ -z "${PROVIDER:-}" ]; then
    if [ -n "${OPENROUTER_API_KEY:-}" ]; then PROVIDER=openrouter
    elif [ -n "${DEEPSEEK_API_KEY:-}" ]; then PROVIDER=deepseek
    elif [ -n "${OPENAI_API_KEY:-}" ]; then PROVIDER=openai
    else echo "Set one of: OPENROUTER_API_KEY, DEEPSEEK_API_KEY, OPENAI_API_KEY" >&2; exit 1
    fi
fi

# ---- Provider endpoints ----
case "$PROVIDER" in
    openrouter) API_BASE="https://openrouter.ai/api/v1/chat/completions"; API_KEY="$OPENROUTER_API_KEY"; MODEL="${MODEL:-openrouter/free}" ;;
    deepseek)   API_BASE="https://api.deepseek.com/v1/chat/completions"; API_KEY="$DEEPSEEK_API_KEY"; MODEL="${MODEL:-deepseek-v4-flash}" ;;
    openai)     API_BASE="https://api.openai.com/v1/chat/completions"; API_KEY="$OPENAI_API_KEY"; MODEL="${MODEL:-gpt-4o}" ;;
    *) echo "Unknown PROVIDER: $PROVIDER (openrouter|deepseek|openai)" >&2; exit 1 ;;
esac
[ -z "$API_KEY" ] && { echo "Missing API key for $PROVIDER" >&2; exit 1; }

# ---- Prompt & tools ----
SYSTEM_PROMPT="${SYSTEM_PROMPT:-You are a coding agent in a bash environment. You are helpful, direct, proactive, and comprehensive. You have access to tools (bash, read, write, edit) to accomplish tasks. When given a task, think through the approach, execute the necessary commands, verify results, and report back clearly. Be concise but thorough. Proactively anticipate what information or steps might be needed next and offer them. Never leave a task partially done — always see it through to completion or explain what remains.}"
TOOLS='[{"type":"function","function":{"name":"bash","parameters":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}}},{"type":"function","function":{"name":"read","parameters":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}}},{"type":"function","function":{"name":"write","parameters":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}}},{"type":"function","function":{"name":"edit","parameters":{"type":"object","properties":{"path":{"type":"string"},"old_text":{"type":"string"},"new_text":{"type":"string"}},"required":["path","old_text","new_text"]}}}]'

# ---- Tool runner ----
run_tool() {
    local cmd="$1" args="$2"
    case "$cmd" in
        bash)
            local c; c=$(jq -r '.command // empty' <<<"$args") || return
            [ -n "$c" ] && eval "$c" 2>&1 || true ;;
        read)
            local p; p=$(jq -r '.path // empty' <<<"$args") || return
            [ -f "$p" ] && cat "$p" || { echo "file not found: $p"; return 1; } ;;
        write)
            local p c; p=$(jq -r '.path // empty' <<<"$args"); c=$(jq -r '.content // empty' <<<"$args") || return
            mkdir -p "$(dirname "$p")" && printf '%s' "$c" > "$p" ;;
        edit)
            local p o n; p=$(jq -r '.path // empty' <<<"$args"); o=$(jq -r '.old_text // empty' <<<"$args"); n=$(jq -r '.new_text // empty' <<<"$args") || return
            [ -f "$p" ] || { echo "file not found: $p"; return 1; }
            sed -i '' "s/$(printf '%s' "$o" | sed 's/[\/&]/\\&/g')/$(printf '%s' "$n" | sed 's/[\/&]/\\&/g')/g" "$p" ;;
    esac
}

echo "=== Agent [provider:$PROVIDER model:$MODEL skills:${BASH_AGENT_SKILL:-none}] ==="

# ---- REPL loop ----
HIST='[]'
while true; do
    printf "\n> " && read -r input || exit 0
    [ -n "$input" ] || continue; [ "$input" = "exit" ] && exit 0
    HIST=$(echo "$HIST" | jq -c --arg c "$input" '.+[{"role":"user","content":$c}]')

    for ((r=0; r<10; r++)); do
        body=$(jq -n --arg m "$MODEL" --arg s "$SYSTEM_PROMPT" --argjson t "$TOOLS" --argjson h "$HIST" '{model:$m,messages:([{role:"system",content:$s}]+$h),tools:$t,temperature:0.3,max_tokens:2000}')
        resp=$(curl -fsS "$API_BASE" -H "Content-Type: application/json" -H "Authorization: Bearer $API_KEY" -d "$body" 2>&1) || { echo "  ✗ API error: $resp"; exit 1; }
        choice=$(echo "$resp" | jq -c '.choices[0].message // empty')
        [ -z "$choice" ] && { echo "  ✗ $(echo "$resp"|jq -c '.error//.')"; exit 1; }

        if echo "$choice" | jq -e '.tool_calls' >/dev/null 2>&1; then
            HIST=$(echo "$HIST" | jq -c --argjson m "$choice" '.+[$m]')
            while IFS= read -r tc; do
                name=$(echo "$tc"|jq -r '.function.name')
                id=$(echo "$tc"|jq -r '.id')
                args=$(echo "$tc"|jq -r '.function.arguments')
                if ! echo "$args"|jq -e . >/dev/null 2>&1; then
                    echo "  ✗ Malformed arguments: $args"
                    HIST=$(echo "$HIST"|jq -c --arg id "$id" --arg err "malformed arguments: $args" '.+[{"role":"tool","tool_call_id":$id,"content":$err}]')
                    continue
                fi
                printf "  ◆ %s %s\n" "$name" "$(echo "$args"|jq -c '.')"
                result=$(run_tool "$name" "$args") || true
                echo "$result"|head -5
                HIST=$(echo "$HIST"|jq -c --arg id "$id" --argjson content "$(echo "$result"|head -1000|jq -Rs '.')" '.+[{"role":"tool","tool_call_id":$id,"content":$content}]')
            done < <(echo "$choice"|jq -c '.tool_calls[]')
        else
            echo "$choice"|jq -r '.content // ""'
            HIST=$(echo "$HIST"|jq -c --argjson m "$choice" '.+[$m]')
            break
        fi
    done
done

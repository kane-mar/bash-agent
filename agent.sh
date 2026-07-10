#!/usr/bin/env bash
set -euo pipefail

MODEL="${MODEL:-openrouter/free}"
SYSTEM_PROMPT="${SYSTEM_PROMPT:-You are a coding agent in a bash environment. You are helpful, direct, proactive, and comprehensive. You have access to tools (bash, read, write, edit) to accomplish tasks. When given a task, think through the approach, execute the necessary commands, verify results, and report back clearly. Be concise but thorough. Proactively anticipate what information or steps might be needed next and offer them. Never leave a task partially done — always see it through to completion or explain what remains.}"
export JQ_COLORS="1;30:0;37:0;37:0;37:0;32:1;37:1;37"

TOOLS='[{"type":"function","function":{"name":"bash","parameters":{"type":"object","properties":{"command":{"type":"string"}},"required":["command"]}}},{"type":"function","function":{"name":"read","parameters":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}}},{"type":"function","function":{"name":"write","parameters":{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}}},{"type":"function","function":{"name":"edit","parameters":{"type":"object","properties":{"path":{"type":"string"},"old_text":{"type":"string"},"new_text":{"type":"string"}},"required":["path","old_text","new_text"]}}}]'

run_tool() {
    local cmd="$1" args="$2"
    local path content command old_text new_text
    case "$cmd" in
        bash)
            command=$(jq -r '.command // empty' <<<"$args" 2>/dev/null) || return
            [ -n "$command" ] || { echo "error: empty command"; return 1; }
            eval "$command" 2>&1 || true;;
        read)
            path=$(jq -r '.path // empty' <<<"$args" 2>/dev/null) || return
            [ -n "$path" ] || { echo "error: empty path"; return 1; }
            [ -f "$path" ] || { echo "error: file not found: $path"; return 1; }
            cat "$path" 2>&1 || true;;
        write)
            path=$(jq -r '.path // empty' <<<"$args" 2>/dev/null) || return
            content=$(jq -r '.content // empty' <<<"$args" 2>/dev/null) || return
            [ -n "$path" ] || { echo "error: empty path"; return 1; }
            mkdir -p "$(dirname "$path")"
            printf '%s' "$content" > "$path";;
        edit)
            path=$(jq -r '.path // empty' <<<"$args" 2>/dev/null) || return
            old_text=$(jq -r '.old_text // empty' <<<"$args" 2>/dev/null) || return
            new_text=$(jq -r '.new_text // empty' <<<"$args" 2>/dev/null) || return
            [ -n "$path" ] || { echo "error: empty path"; return 1; }
            [ -n "$old_text" ] || { echo "error: empty old_text"; return 1; }
            [ -f "$path" ] || { echo "error: file not found: $path"; return 1; }
            escaped_old=$(printf '%s' "$old_text" | sed 's/[\/&]/\\&/g')
            escaped_new=$(printf '%s' "$new_text" | sed 's/[\/&]/\\&/g')
            sed -i '' "s/$escaped_old/$escaped_new/g" "$path";;
    esac
}

echo "=== Agent [model:$MODEL skills:${BASH_AGENT_SKILL:-none}] ==="

HIST='[]'
while true; do
    printf "\n> " && read -r input || exit 0
    [ -n "$input" ] || continue; [ "$input" = "exit" ] && exit 0
    HIST=$(echo "$HIST" | jq -c --arg c "$input" '.+[{"role":"user","content":$c}]')

    for ((r=0; r<10; r++)); do
        body=$(jq -n --arg m "$MODEL" --arg s "$SYSTEM_PROMPT" --argjson t "$TOOLS" --argjson h "$HIST" '{model:$m,messages:([{role:"system",content:$s}]+$h),tools:$t,temperature:0.3,max_tokens:2000}')
        resp=$(curl -fsS https://openrouter.ai/api/v1/chat/completions -H "Content-Type: application/json" -H "Authorization: Bearer $OPENROUTER_API_KEY" -d "$body" 2>&1) || { echo "  ✗ API error: $resp"; exit 1; }
        choice=$(echo "$resp" | jq -c '.choices[0].message // empty')
        finish=$(echo "$resp" | jq -r '.choices[0].finish_reason // "stop"')
        if [ -z "$choice" ]; then echo "  ✗ Unexpected response: $(echo "$resp" | jq -c '.error // .')"; exit 1; fi

        if echo "$choice" | jq -e '.tool_calls' >/dev/null 2>&1; then
            HIST=$(echo "$HIST" | jq -c --argjson m "$choice" '.+[$m]')
            while IFS= read -r tc; do
                name=$(echo "$tc" | jq -r '.function.name'); id=$(echo "$tc" | jq -r '.id')
                args=$(echo "$tc" | jq -r '.function.arguments')
                # Validate args is valid JSON before using it
                if ! echo "$args" | jq -e . >/dev/null 2>&1; then
                    echo "  ✗ Malformed arguments from model: $args"
                    HIST=$(echo "$HIST" | jq -c --arg id "$id" --arg err "malformed arguments: $args" '.+[{"role":"tool","tool_call_id":$id,"content":$err}]')
                    continue
                fi
                printf "  ◆ %s %s\n" "$name" "$(echo "$args" | jq -c '.')"
                result=$(run_tool "$name" "$args") || true
                echo "$result" | head -5
                encoded=$(echo "$result" | head -1000 | jq -Rs '.')
                tr=$(jq -n --arg id "$id" --argjson content "$encoded" '{role:"tool",tool_call_id:$id,content:$content}')
                HIST=$(echo "$HIST" | jq -c --argjson tr "$tr" '.+[$tr]')
            done < <(echo "$choice" | jq -c '.tool_calls[]')
        else
            echo "$choice" | jq -r '.content // ""'
            HIST=$(echo "$HIST" | jq -c --argjson m "$choice" '.+[$m]')
            break
        fi
    done
done

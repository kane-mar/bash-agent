# skills.sh — Import pi agent skills into your bash agent
# Usage: source ./skills.sh [skill_name ...]
#        source ./skills.sh              # list available skills
#        source ./skills.sh clean-code   # import clean-code skill

SKILLS_DIR="${SKILLS_DIR:-$HOME/.pi/agent/skills}"

# List all available skills
bash_agent_list_skills() {
    echo "Available skills:"
    for skill in "$SKILLS_DIR"/*/SKILL.md "$SKILLS_DIR"/*.md; do
        [ -f "$skill" ] || continue
        dir=$(dirname "$skill" 2>/dev/null); name=$(basename "$dir" 2>/dev/null || basename "$skill" .md); [ "$name" = "skills" ] && name="llm-council"
        desc=$(grep '^description:' "$skill" 2>/dev/null | head -1 | sed 's/description: "*//;s/"$//')
        [ -n "$desc" ] || desc="(no description)"
        printf "  %-25s %s\n" "$name" "$desc"
    done
}

# Import a specific skill
bash_agent_import_skill() {
    local name="$1"
    # Find the skill file
    local skill_file
    if [ -f "$SKILLS_DIR/$name/SKILL.md" ]; then
        skill_file="$SKILLS_DIR/$name/SKILL.md"
    elif [ -f "$SKILLS_DIR/$name.md" ]; then
        skill_file="$SKILLS_DIR/$name.md"
    else
        echo "Error: skill '$name' not found" >&2
        return 1
    fi

    # Source scripts if they exist (silently skip scripts meant for direct invocation)
    if [ -d "$SKILLS_DIR/$name/scripts" ]; then
        for script in "$SKILLS_DIR/$name/scripts"/*.sh; do
            [ -f "$script" ] && source "$script" 2>/dev/null || true
        done
    fi

    # Export the metadata as environment variables
    BASH_AGENT_SKILL="$name"
    export BASH_AGENT_SKILL SKILLS_DIR
    echo "imported skill: $name"
}

# --- Main ---
if [ $# -eq 0 ]; then
    bash_agent_list_skills
elif [ "$1" = "--help" ]; then
    echo "Usage: source ./skills.sh [skill_name ...]"
    echo "       source ./skills.sh              # list available skills"
    echo "       source ./skills.sh clean-code   # import clean-code"
else
    for skill in "$@"; do
        bash_agent_import_skill "$skill" || break
    done
fi

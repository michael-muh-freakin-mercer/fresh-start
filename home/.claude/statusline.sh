#!/usr/bin/env bash
# Claude Code statusline: model · folder · git branch · context used · ponytail mode.
input=$(cat)

# Keep one sample of the input so the field names can be checked later.
sample="$HOME/.cache/claude-statusline-sample.json"
[ -f "$sample" ] || printf '%s' "$input" > "$sample" 2>/dev/null

model=$(jq -r '.model.display_name // .model.id // "claude"' <<<"$input")
dir=$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input")
ctx=$(jq -r '.context_window.used_percentage // empty' <<<"$input")

out="\033[38;5;111m${model}\033[0m"
[ -n "$dir" ] && out+=" · \033[38;5;150m$(basename "$dir")\033[0m"

branch=$(git -C "${dir:-.}" branch --show-current 2>/dev/null)
[ -n "$branch" ] && out+=" · \033[38;5;180m ${branch}\033[0m"

[ -n "$ctx" ] && out+=" · ctx $(printf '%.0f' "$ctx")%"

ponytail=$("$HOME/.claude/ponytail-statusline.sh" 2>/dev/null)
[ -n "$ponytail" ] && out+=" ${ponytail}"

printf '%b' "$out"

# Node comes from mise (activated by Omarchy's rc), so no hardcoded node path here.
# Omarchy environment (OMARCHY_PATH + PATH), needed even for non-interactive shells
[[ -r /usr/share/omarchy/default/bash/env-bootstrap ]] && source /usr/share/omarchy/default/bash/env-bootstrap

# If not running interactively, don't do anything else (leave this above the rc source)
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
# (don't mess with these directly, just overwrite them here!)
source "$OMARCHY_PATH/default/bash/rc"

# Add your own exports, aliases, and functions here.
#
# Make an alias for invoking commands you use constantly
# alias p='python'
#
alias tb='cd ~/projects/active/trading-bot && claude --strict-mcp-config --mcp-config .mcp.json'

# API keys live in ~/.secrets/env (KEY=value lines, chmod 600), never in this file.
if [[ -r $HOME/.secrets/env ]]; then set -a; source "$HOME/.secrets/env"; set +a; fi

if [[ -z ${BASH_EXECUTION_STRING:-} ]] && command -v fastfetch &>/dev/null; then
  fastfetch
fi

export PATH="$HOME/.local/bin:$PATH"

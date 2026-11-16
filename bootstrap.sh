#!/usr/bin/env bash
# bootstrap.sh: set up a fresh Omarchy install the way Michael likes it.
#
#   ./bootstrap.sh            normal run (asks before each optional step)
#   ./bootstrap.sh --dry-run  show what would happen, change nothing
#   ./bootstrap.sh --yes      say yes to every optional step
#
# Safe to re-run: it skips anything already done and never deletes files.
# Existing files that would be replaced are renamed to <file>.bak-<timestamp>.

# shellcheck disable=SC2088  # "~" in messages is display text
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
ASSUME_YES=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -y | --yes) ASSUME_YES=1 ;;
    -h | --help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)"; exit 1 ;;
  esac
done

bold=$'\e[1m'; green=$'\e[32m'; yellow=$'\e[33m'; reset=$'\e[0m'
step() { printf '\n%s==> %s%s\n' "$bold" "$*" "$reset"; }
ok()   { printf '  %s✓%s %s\n' "$green" "$reset" "$*"; }
note() { printf '  %s!%s %s\n' "$yellow" "$reset" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
run() {
  if ((DRY_RUN)); then printf '  [dry-run] %s\n' "$*"; else "$@"; fi
}
ask() {
  ((ASSUME_YES)) && return 0
  [[ -t 0 ]] || return 1
  local reply
  read -r -p "  $1 [y/N] " reply
  [[ $reply =~ ^[Yy] ]]
}
read_list() { grep -vE '^[[:space:]]*(#|$)' "$1" | awk '{print $1}'; }

if [[ $EUID -eq 0 ]]; then
  echo "Run this as your normal user, not with sudo. It will ask for your password when needed."
  exit 1
fi
if ! have pacman && ((!DRY_RUN)); then
  echo "This script is for Omarchy / Arch Linux (pacman not found)."
  exit 1
fi

((DRY_RUN)) && note "Dry run: nothing will be changed."

# ---------------------------------------------------------------------------
step "1/9 Packages"
mapfile -t official < <(read_list "$DOTFILES/packages/pacman.txt")
mapfile -t aur < <(read_list "$DOTFILES/packages/aur.txt")

missing=()
for p in "${official[@]}" "${aur[@]}"; do
  if have pacman && pacman -Qi "$p" >/dev/null 2>&1; then continue; fi
  missing+=("$p")
done

if ((${#missing[@]} == 0)); then
  ok "All packages already installed"
elif have yay; then
  run yay -S --needed --noconfirm "${missing[@]}"
  ok "Installed: ${missing[*]}"
else
  note "yay not found, so installing official packages only. Install yay, then re-run for: ${aur[*]}"
  run sudo pacman -S --needed --noconfirm "${official[@]}"
fi

# ---------------------------------------------------------------------------
step "2/9 Folders"
dirs=(
  "$HOME/projects/active"
  "$HOME/projects/archive"
  "$HOME/projects/sandbox"
  "$HOME/projects/shared/ai"
  "$HOME/projects/shared/scripts"
  "$HOME/business/ideas"
  "$HOME/business/archive"
  "$HOME/vault"
  "$HOME/.secrets"
  "$HOME/.local/bin"
)
for d in "${dirs[@]}"; do
  if [[ -d $d ]]; then continue; fi
  run mkdir -p "$d"
  ok "Created ${d/#"$HOME"/\~}"
done
run chmod 700 "$HOME/.secrets" "$HOME/vault"
ok "~/.secrets and ~/vault are private (chmod 700)"

link() { # link <target> <link-path>
  local target=$1 dest=$2
  if [[ -L $dest && $(readlink "$dest") == "$target" ]]; then return 0; fi
  if [[ -e $dest || -L $dest ]]; then
    run mv "$dest" "$dest.bak-$(date +%s)"
    note "Backed up existing ${dest/#"$HOME"/\~}"
  fi
  run mkdir -p "$(dirname "$dest")"
  run ln -s "$target" "$dest"
  ok "Linked ${dest/#"$HOME"/\~}"
}

link "$DOTFILES/templates" "$HOME/projects/shared/templates"

# ---------------------------------------------------------------------------
step "3/9 Commands (new-project, bench-project, ...)"
for f in "$DOTFILES"/bin/*; do
  [[ -f $f ]] || continue
  link "$f" "$HOME/.local/bin/$(basename "$f")"
done
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ok "~/.local/bin is on your PATH" ;;
  *) note "Add this to ~/.bashrc so the commands work:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# ---------------------------------------------------------------------------
step "4/9 Dotfiles (everything in ~/dotfiles/home gets linked into ~)"
count=0
while IFS= read -r -d '' src; do
  rel=${src#"$DOTFILES/home/"}
  [[ $rel == README.md || $(basename "$rel") == .gitkeep ]] && continue
  link "$src" "$HOME/$rel"
  count=$((count + 1))
done < <(find "$DOTFILES/home" \( -type f -o -type l \) -print0)
ok "$count config file(s) in place"

# ---------------------------------------------------------------------------
step "5/9 Desktop extras (bar plugins, lid sleep, saved data)"
# Third-party bar plugins live in their own repos; shell.json expects them.
clone_plugin() { # clone_plugin <dir name> <url>
  local dir="$HOME/.config/omarchy/plugins/$1"
  if [[ -d $dir ]]; then return 0; fi
  run git clone --quiet "$2" "$dir"
  ok "Cloned bar plugin $1"
}
clone_plugin io.github.tyrichards.workspaces-jap https://github.com/TyRichards/omarchy-workspaces-jap.git
clone_plugin io.github.sirjul1337.lock-explorer https://github.com/SirJul1337/omarchy-lock-explorer.git
clone_plugin agx.screen-time https://github.com/ax1g/quickshell-screentime-plugin.git
clone_plugin omaplug https://github.com/fross100/omaplug
clone_plugin atsokolas.daily https://github.com/atsokolas/omarchy-daily-plugin.git

# Saved data: copied once, never linked (apps rewrite these files constantly).
while IFS= read -r -d '' src; do
  dest="$HOME/${src#"$DOTFILES/seed/"}"
  [[ -e $dest ]] && continue
  run install -D -m 644 "$src" "$dest"
  ok "Restored ${dest/#"$HOME"/\~}"
done < <(find "$DOTFILES/seed" -type f -print0)

# System files under /etc: lid closed = suspend, then hibernate after 90 min.
pending=()
while IFS= read -r -d '' src; do
  dest="/${src#"$DOTFILES/system/"}"
  cmp -s "$src" "$dest" 2>/dev/null || pending+=("$src")
done < <(find "$DOTFILES/system" -type f -print0)
if ((${#pending[@]} == 0)); then
  ok "System files already in place"
elif ask "Install ${#pending[@]} file(s) into /etc (lid sleep -> hibernate)? Needs your password"; then
  for src in "${pending[@]}"; do
    run sudo install -D -m 644 "$src" "/${src#"$DOTFILES/system/"}"
  done
  ok "System files installed (take effect after a reboot)"
else
  note "Later: re-run bootstrap.sh to install the /etc files"
fi

have omarchy && run omarchy restart shell >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
step "6/9 Git"
if [[ -z $(git config --global user.name || true) ]]; then
  if [[ -t 0 ]] && ((!ASSUME_YES)); then
    read -r -p "  Name for your commits: " gname
    read -r -p "  Email for your commits (tip: use your GitHub noreply address): " gemail
    run git config --global user.name "$gname"
    run git config --global user.email "$gemail"
  else
    note "Git name/email not set. Run: git config --global user.name \"Your Name\""
  fi
else
  ok "Git identity: $(git config --global user.name)"
fi
# Defaults only; the tracked ~/.config/git/config wins when it sets these.
git config --global init.defaultBranch >/dev/null || run git config --global init.defaultBranch main
git config --global pull.rebase >/dev/null || run git config --global pull.rebase false

if have gh; then
  if gh auth status >/dev/null 2>&1; then
    ok "Logged in to GitHub"
  elif ask "Log in to GitHub now? (it can create an SSH key for you)"; then
    run gh auth login --hostname github.com --git-protocol ssh --web
  else
    note "Later: gh auth login"
  fi
fi

# ---------------------------------------------------------------------------
step "7/9 Your repos"
if have gh && gh auth status >/dev/null 2>&1; then
  if ask "Clone all your GitHub repos into ~/projects/archive?"; then
    run "$DOTFILES/bin/clone-repos"
  fi
else
  note "Skipped (not logged in to GitHub). Later: clone-repos"
fi

# ---------------------------------------------------------------------------
step "8/9 AI tools"
if have claude; then
  ok "Claude Code installed"
elif ask "Install Claude Code?"; then
  run bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
fi

if have hermes; then
  ok "Hermes installed"
elif ask "Install Hermes Agent?"; then
  run bash -c 'curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash'
fi

if have crush; then ok "Crush installed"; else note "Crush not found (it installs from packages/aur.txt)"; fi

if have mise; then
  if ask "Install Node (LTS) and Python with mise?"; then
    run mise use --global node@lts python@latest
  fi
else
  note "mise not found. Use Omarchy menu > Install > Development, or: yay -S mise"
fi

# ---------------------------------------------------------------------------
step "9/9 Done. Finish these by hand:"
cat <<'EOF'
  [ ] Copy your .kdbx from the USB into ~/vault and open it in KeePassXC
  [ ] Set up a backup for ~/vault (Syncthing or a USB copy). Never sync ~/.secrets
  [ ] Chromium profiles: Personal, Dev (and Business if needed)
  [ ] KeePassXC browser extension in each profile
  [ ] OpenRouter: one key per tool with a spending cap, auto top-up OFF
  [ ] Run `hermes setup` and `crush`, give each its own OpenRouter key
  [ ] Run `claude` and sign in with your Claude account
  [ ] Put API keys in ~/.secrets/env (KEY=value lines, chmod 600); ~/.bashrc loads it
  [ ] Re-enter the agents widget's API keys in its panel (they're never in git)
  [ ] Hibernation: `omarchy hibernation setup`, reboot, test once with `systemctl hibernate`
  [ ] Hermes gateway: let Hermes re-create its own service (don't copy the old one)
  [ ] Move the repos you're actively working on: unbench-project <name>
EOF

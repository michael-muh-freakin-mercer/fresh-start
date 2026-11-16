#!/usr/bin/env bash
# collect.sh: gather everything worth keeping before you wipe the laptop.
#
#   ./collect.sh <usb-folder>                          back up this system
#   ./collect.sh <usb-folder> --fedora-home <path>     ...and the Fedora home too
#   ./collect.sh <usb-folder> --report-only            just write the report, copy nothing
#
# Example:
#   ./collect.sh /run/media/$USER/BACKUP --fedora-home /mnt/fedora/michael
#
# What it makes on the USB (in laptop-backup-<date>/):
#   REPORT.md   what needs your attention: unpushed repos, .env files, running
#               services, big files, browser extensions, manual steps
#   raw/        unsorted copy of each home folder (caches and secrets left out)
#   secrets/    ONE encrypted file per system: SSH keys, .env files, browser
#               profiles, shell history, tokens. You pick the password.
#   browsers/   bookmarks (importable HTML) and extension lists
#   lists/      installed packages, repo status, folder sizes
#
# Close Firefox and Chromium first so their files aren't changing mid-copy.
# Getting at the Fedora home (it's read-only, nothing is changed):
#   lsblk -f                                        find the Fedora partition
#   sudo mkdir -p /mnt/fedora
#   sudo mount -o ro,subvol=home /dev/<partition> /mnt/fedora   (btrfs, Fedora's default)
#   sudo mount -o ro /dev/<partition> /mnt/fedora               (ext4: home is /mnt/fedora/home)
#   Encrypted? First: sudo cryptsetup open /dev/<partition> fedora, then use /dev/mapper/fedora

# shellcheck disable=SC2088  # "~" in messages is display text
set -euo pipefail

bold=$'\e[1m'; green=$'\e[32m'; yellow=$'\e[33m'; red=$'\e[31m'; reset=$'\e[0m'
step() { printf '\n%s==> %s%s\n' "$bold" "$*" "$reset"; }
ok()   { printf '  %s✓%s %s\n' "$green" "$reset" "$*"; }
note() { printf '  %s!%s %s\n' "$yellow" "$reset" "$*"; }
die()  { printf '%sError:%s %s\n' "$red" "$reset" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
ask() {
  [[ -t 0 ]] || return 1
  local reply
  read -r -p "  $1 [y/N] " reply
  [[ $reply =~ ^[Yy] ]]
}
human() { numfmt --to=iec --suffix=B "$1" 2>/dev/null || echo "$1 bytes"; }

# --- arguments --------------------------------------------------------------
DEST_ROOT="" FEDORA_HOME="" REPORT_ONLY=0
while (($#)); do
  case "$1" in
    --fedora-home) [[ $# -ge 2 ]] || die "--fedora-home needs a path"; FEDORA_HOME=$2; shift 2 ;;
    --report-only) REPORT_ONLY=1; shift ;;
    -h | --help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) die "Unknown option: $1 (try --help)" ;;
    *) [[ -z $DEST_ROOT ]] || die "Only one destination folder, please"; DEST_ROOT=$1; shift ;;
  esac
done

[[ -n $DEST_ROOT ]] || { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[[ $EUID -ne 0 ]] || die "Run this as your normal user, not with sudo."
[[ -d $DEST_ROOT ]] || die "Not a folder: $DEST_ROOT. Plug in the USB and use its path, e.g. /run/media/$USER/<name>"
DEST_ROOT=$(cd "$DEST_ROOT" && pwd)
if [[ -n $FEDORA_HOME ]]; then
  [[ -d $FEDORA_HOME ]] || die "Fedora home not found: $FEDORA_HOME (see --help for how to mount it)"
  FEDORA_HOME=$(cd "$FEDORA_HOME" && pwd)
fi
have rsync || die "rsync is missing: sudo pacman -S rsync"
have jq || note "jq is missing (sudo pacman -S jq): browser bookmarks and extensions will be skipped"
have gpg || die "gpg is missing: sudo pacman -S gnupg"

OUT="$DEST_ROOT/laptop-backup-$(date +%F)"
REPORT="$OUT/REPORT.md"
mkdir -p "$OUT"/{raw,secrets,browsers,lists}

# --- what to leave out of the raw copy --------------------------------------
# Caches and rebuildable stuff:
JUNK=(
  .cache node_modules .npm .pnpm-store .yarn/cache .bun/install/cache
  /.cargo/registry /.rustup /go/pkg /.local/share/Trash /.local/share/Steam
  .venv venv __pycache__ .next .nuxt .turbo .parcel-cache
  /.var/app/*/cache
  /.ollama/models /.android/avd /.android/cache /.dotnet /.bun/install
  /.vscode/extensions /.cursor/extensions /.local/share/Steam
)
# Secret or private stuff: goes into the encrypted bundle instead.
# Note ~/secrets (no dot) is included: plain-text keys must not land in raw/.
SECRET_PATHS=(
  .ssh .gnupg .secrets .config/gh .local/share/keyrings .password-store
  .aws .docker/config.json .netrc .npmrc .pypirc .git-credentials
  .claude/.credentials.json .config/openrouter .hermes/.env
  .bash_history .zsh_history .local/share/fish/fish_history
  .python_history .node_repl_history .lesshst .sqlite_history
  .mozilla .var/app/org.mozilla.firefox
  .config/mozilla  # newer Firefox keeps its profile here, not in ~/.mozilla
  .config/1Password .config/Bitwarden .var/app/com.bitwarden.desktop
  .config/chromium .config/google-chrome .config/BraveSoftware
  .var/app/org.chromium.Chromium .var/app/com.google.Chrome
  secrets secure .relayvault
  # Loose key and password files found on this laptop
  .ollama/id_ed25519 .emulator_console_auth_token mc-admin-password.txt
  .local/share/gnome-remote-desktop .local/share/vitest
  # AI tools keep login tokens and API keys in their folders
  .codex .gemini .copilot .cursor .happy .openclaw .hermes .paperclip
  .minimax .pi .ori .crush .config/crush .local/share/crush .claude.json .claude
)
BROWSER_CACHE_EXCLUDES=(
  --exclude='*/Cache' --exclude='*/Code Cache' --exclude='*/GPUCache'
  --exclude='*/Service Worker/CacheStorage' --exclude='*/Service Worker/ScriptCache'
  --exclude='*/cache2' --exclude='*/startupCache' --exclude='*/thumbnails'
  --exclude='*/OfflineCache' --exclude='*/Crashpad' --exclude='*/crashes'
  --exclude='*/ShaderCache' --exclude='*/GrShaderCache' --exclude='*/DawnCache'
  --exclude='*/component_crx_cache' --exclude='*/extensions_crx_cache'
  --exclude='*/node_modules' --exclude='*/.venv' --exclude='*/venv' --exclude='*/__pycache__'
  --exclude='.cursor/extensions'
  # Don't exclude *.log (browsers' leveldb storage keeps its newest data in *.log files)
  # or .git packs (that's where most of a repo's history lives).
)

# find() prune expression for the reports (skips heavy/irrelevant folders)
prune_args() { # prune_args <home>
  printf '%s\0' \( -name node_modules -o -name .cache -o -name .venv -o -name venv \
    -o -path "$1/.local/share" -o -path "$1/.cargo" -o -path "$1/.rustup" \
    -o -path "$1/go/pkg" -o -path "$1/.mozilla" -o -path "$1/.config/mozilla" -o -path "$1/.config/chromium" \
    -o -path "$1/.var" -o -path "$OUT" \) -prune -o
}

redact() { sed -E 's#://[^@/]+@#://***@#'; }

# --- report helpers ---------------------------------------------------------
md() { printf '%s\n' "$*" >>"$REPORT"; }
ATTENTION=()

{
  echo "# Laptop backup report"
  echo
  echo "Made $(date '+%F %H:%M') on $(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo this laptop)."
  echo
  echo "<!-- ATTENTION -->"
} >"$REPORT"

# --- per-home work ----------------------------------------------------------
report_repos() { # report_repos <home> <label>
  local home=$1 label=$2
  local csv="$OUT/lists/$label-repos.tsv" count=0 risky=0
  printf 'path\tremote\tuncommitted\tunpushed\tstashes\tlast_commit\n' >"$csv"
  md "### Git repos ($label)"
  md
  md "| | Repo | Remote | Uncommitted | Unpushed | Stashes | Last commit |"
  md "|---|---|---|---|---|---|---|"
  local args
  mapfile -d '' args < <(prune_args "$home")
  while IFS= read -r -d '' gitdir; do
    local repo=${gitdir%/.git} g=(git -c safe.directory='*' -C "${gitdir%/.git}")
    local remote dirty unpushed stashes last flag=""
    remote=$("${g[@]}" remote get-url origin 2>/dev/null | redact || true)
    [[ -n $remote ]] || remote=$("${g[@]}" remote -v 2>/dev/null | head -1 | awk '{print $2}' | redact || true)
    dirty=$("${g[@]}" status --porcelain 2>/dev/null | wc -l)
    if [[ -n $remote ]]; then
      unpushed=$("${g[@]}" log --branches --not --remotes --oneline 2>/dev/null | wc -l)
    else
      unpushed=$("${g[@]}" rev-list --all --count 2>/dev/null || echo 0)
    fi
    stashes=$("${g[@]}" stash list 2>/dev/null | wc -l)
    last=$("${g[@]}" log -1 --format=%cs 2>/dev/null || echo "none")
    if [[ -z $remote ]] || ((dirty > 0 || unpushed > 0 || stashes > 0)); then
      flag="⚠️"; risky=$((risky + 1))
    fi
    md "| $flag | \`${repo/#"$home"/\~}\` | ${remote:-**none**} | $dirty | $unpushed | $stashes | $last |"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "${remote:-none}" "$dirty" "$unpushed" "$stashes" "$last" >>"$csv"
    count=$((count + 1))
  done < <(find "$home" "${args[@]}" -type d -name .git -print0 2>/dev/null)
  ((count)) || md "| | (no git repos found) | | | | | |"
  md
  md "⚠️ = work that only exists on this laptop. Commit and push it (or copy the folder) before wiping. No remote means it was never on GitHub at all."
  md
  ((risky)) && ATTENTION+=("**$risky repo(s) on $label** have unsaved or unpushed work. See *Git repos ($label)*.")
  ok "$label: $count git repo(s), $risky need attention"
}

find_env_files() { # find_env_files <home>  → NUL-separated paths
  local args
  mapfile -d '' args < <(prune_args "$1")
  find "$1" "${args[@]}" -type f \( -name '.env' -o -name '.env.*' -o -name '*.env' \) \
    ! -name '.env.example' ! -name '.env.sample' -print0 2>/dev/null
}

# Recovery/backup code files can sit anywhere (often ~/Downloads): encrypt, don't copy plain.
# Matches e.g. github-recovery-codes.txt, Mercury_Backup_Codes.pdf, 2fa-code.txt,
# but not turn_recovery_codex.py ("code"/"codes" must end the word).
CODE_FILE_REGEX='.*/[^/]*(recovery|backup|2fa)[-_ ]?codes?([-_. ][^/]*)?'
find_code_files() { # find_code_files <home>  → NUL-separated paths
  local args
  mapfile -d '' args < <(prune_args "$1")
  find "$1" "${args[@]}" -type f -regextype posix-extended -iregex "$CODE_FILE_REGEX" -print0 2>/dev/null
}
in_secret_path() { # in_secret_path <relative path>: already covered by SECRET_PATHS?
  local p
  for p in "${SECRET_PATHS[@]}"; do [[ $1 == "$p" || $1 == "$p"/* ]] && return 0; done
  return 1
}

report_env() { # report_env <home> <label>
  local home=$1 label=$2 n=0
  md "### .env files ($label)"
  md
  while IFS= read -r -d '' f; do
    md "- \`${f/#"$home"/\~}\`"
    n=$((n + 1))
  done < <(find_env_files "$home")
  ((n)) || md "- none found"
  md
  local codes=0
  while IFS= read -r -d '' f; do
    ((codes)) || { md "Recovery / backup code files (encrypted bundle only):"; md; }
    md "- \`${f/#"$home"/\~}\`"
    codes=$((codes + 1))
  done < <(find_code_files "$home")
  ((codes)) && { md; ATTENTION+=("**$codes recovery/backup code file(s) on $label.** Move them into KeePassXC."); }
  if ((n)); then
    md "Contents are in the encrypted bundle, not in \`raw/\`. Move each key into KeePassXC, and revoke any you no longer use."
    md
    ATTENTION+=("**$n .env file(s) on $label** hold API keys. Move them into KeePassXC (they're safe in the encrypted bundle meanwhile).")
  fi
  ok "$label: $n .env file(s)"
}

report_big_files() { # report_big_files <home> <label>
  local home=$1 label=$2 args n=0
  mapfile -d '' args < <(prune_args "$home")
  md "### Files over 500 MB ($label)"
  md
  while IFS=$'\t' read -r size path; do
    md "- $(human "$size") \`${path/#"$home"/\~}\`"
    n=$((n + 1))
  done < <(find "$home" "${args[@]}" -type f -size +500M -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -25)
  ((n)) || md "- none"
  md
  md "Old ISOs, VM disks and downloads are often the bulk of a backup. Delete what you don't need from the USB later."
  md
}

report_sizes() { # report_sizes <home> <label>
  local home=$1 label=$2
  {
    echo "Biggest folders in $label home:"
    du -xsh "$home"/* "$home"/.[!.]* 2>/dev/null | sort -h | tail -25
  } >"$OUT/lists/$label-folder-sizes.txt"
}

chromium_dirs() { # chromium_dirs <home> → "browser<TAB>dir" lines
  local home=$1
  local pairs=(
    "chromium:$home/.config/chromium"
    "chrome:$home/.config/google-chrome"
    "brave:$home/.config/BraveSoftware/Brave-Browser"
    "chromium-flatpak:$home/.var/app/org.chromium.Chromium/config/chromium"
    "chrome-flatpak:$home/.var/app/com.google.Chrome/config/google-chrome"
  )
  local p
  for p in "${pairs[@]}"; do
    [[ -d ${p#*:} ]] && printf '%s\t%s\n' "${p%%:*}" "${p#*:}"
  done
  return 0
}

firefox_dirs() { # firefox_dirs <home>
  local home=$1 d
  for d in "$home/.mozilla/firefox" "$home/.config/mozilla/firefox" \
    "$home/.var/app/org.mozilla.firefox/.mozilla/firefox" "$home/.var/app/org.mozilla.firefox/config/mozilla/firefox"; do
    [[ -d $d ]] && printf '%s\n' "$d"
  done
  return 0
}

bookmarks_html_header() {
  printf '%s\n' '<!DOCTYPE NETSCAPE-Bookmark-file-1>' \
    '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">' \
    "<TITLE>$1</TITLE>" "<H1>$1</H1>" '<DL><p>'
}

report_browsers() { # report_browsers <home> <label>
  local home=$1 label=$2 found=0
  md "### Browsers ($label)"
  md
  have jq || { md "- skipped (jq not installed)"; md; return 0; }

  # Chromium family
  while IFS=$'\t' read -r browser dir; do
    local state="$dir/Local State"
    for prof in "$dir"/*/; do
      prof=${prof%/}
      [[ -f $prof/Bookmarks || -f $prof/Preferences ]] || continue
      local pname pid=${prof##*/} base
      pname=$(jq -r --arg p "$pid" '.profile.info_cache[$p].name // $p' "$state" 2>/dev/null || echo "$pid")
      base="$label-$browser-$(printf '%s' "$pname" | tr -c 'A-Za-z0-9._-' '_')"
      found=1
      md "**$browser, profile \"$pname\"**"
      md
      if [[ -f $prof/Bookmarks ]]; then
        local n
        {
          bookmarks_html_header "$browser $pname bookmarks"
          jq -r '.. | objects | select(.type? == "url") |
            "<DT><A HREF=\"\(.url | @html)\">\(.name | @html)</A>"' "$prof/Bookmarks" 2>/dev/null
          echo '</DL><p>'
        } >"$OUT/browsers/$base-bookmarks.html"
        n=$(grep -c '<DT>' "$OUT/browsers/$base-bookmarks.html" || true)
        md "- $n bookmarks → \`browsers/$base-bookmarks.html\` (import in any browser)"
      fi
      if [[ -d $prof/Extensions ]]; then
        local exts=()
        for m in "$prof"/Extensions/*/*/manifest.json; do
          [[ -f $m ]] || continue
          local name key
          name=$(jq -r '.name // empty' "$m" 2>/dev/null || true)
          if [[ $name == __MSG_*__ ]]; then
            key=${name#__MSG_}; key=${key%__}
            local loc
            for loc in "${m%/manifest.json}"/_locales/{en,en_US}/messages.json; do
              [[ -f $loc ]] || continue
              name=$(jq -r --arg k "$key" 'to_entries[] | select(.key | ascii_downcase == ($k | ascii_downcase)) | .value.message' "$loc" 2>/dev/null | head -1)
              break
            done
          fi
          [[ -n $name ]] && exts+=("$name")
        done
        if ((${#exts[@]})); then
          printf '%s\n' "${exts[@]}" | sort -u >"$OUT/browsers/$base-extensions.txt"
          md "- Extensions: $(sort -u < "$OUT/browsers/$base-extensions.txt" | paste -sd ',' - | sed 's/,/, /g')"
        fi
      fi
      md
    done
  done < <(chromium_dirs "$home")

  # Firefox
  while IFS= read -r ffdir; do
    for prof in "$ffdir"/*/; do
      prof=${prof%/}
      [[ -f $prof/places.sqlite || -f $prof/extensions.json ]] || continue
      local pname=${prof##*/} base
      base="$label-firefox-$(printf '%s' "$pname" | tr -c 'A-Za-z0-9._-' '_')"
      found=1
      md "**firefox, profile \"$pname\"**"
      md
      if [[ -f $prof/places.sqlite ]]; then
        if have sqlite3; then
          local tmp n
          tmp=$(mktemp -d)
          cp "$prof"/places.sqlite* "$tmp/" 2>/dev/null || true
          {
            bookmarks_html_header "Firefox $pname bookmarks"
            sqlite3 -separator $'\t' "$tmp/places.sqlite" \
              "SELECT p.url, COALESCE(b.title, p.title, p.url) FROM moz_bookmarks b JOIN moz_places p ON p.id = b.fk
               WHERE b.type = 1 AND p.url NOT LIKE 'place:%';" 2>/dev/null |
              jq -Rr 'split("\t") | "<DT><A HREF=\"\(.[0] | @html)\">\((.[1] // .[0]) | @html)</A>"'
            echo '</DL><p>'
          } >"$OUT/browsers/$base-bookmarks.html"
          rm -rf "$tmp"
          n=$(grep -c '<DT>' "$OUT/browsers/$base-bookmarks.html" || true)
          md "- $n bookmarks → \`browsers/$base-bookmarks.html\` (import in any browser)"
        else
          md "- Bookmarks: install sqlite (sudo pacman -S sqlite) and re-run, or export from Firefox's Library window"
        fi
      fi
      if [[ -f $prof/extensions.json ]]; then
        jq -r '.addons[]? | select(.type == "extension" and .location == "app-profile") |
          .defaultLocale.name // .id' "$prof/extensions.json" 2>/dev/null | sort -u \
          >"$OUT/browsers/$base-extensions.txt" || true
        [[ -s $OUT/browsers/$base-extensions.txt ]] &&
          md "- Extensions: $(paste -sd ',' "$OUT/browsers/$base-extensions.txt" | sed 's/,/, /g')"
      fi
      md
    done
  done < <(firefox_dirs "$home")

  if ((found)); then
    ATTENTION+=("**Saved passwords in $label browsers** aren't readable by a script. Export each browser's passwords (CSV) and import into KeePassXC, then delete the CSV.")
  else
    md "- no Chromium or Firefox profiles found"
    md
  fi
  ok "$label: browsers checked"
}

copy_raw() { # copy_raw <home> <label>
  local home=$1 label=$2
  local dest="$OUT/raw/$label-home" fstype opts=()
  local excludes=() p
  for p in "${JUNK[@]}"; do excludes+=(--exclude="$p"); done
  for p in "${SECRET_PATHS[@]}"; do excludes+=(--exclude="/$p"); done
  excludes=(--include='.env.example' "${excludes[@]}" --exclude='.env' --exclude='.env.*' --exclude='*.env')
  # Exact paths (rsync patterns are case-sensitive; find -iname isn't)
  while IFS= read -r -d '' p; do excludes+=(--exclude="/${p#"$home"/}"); done < <(find_code_files "$home")
  [[ $OUT == "$home"/* ]] && excludes+=(--exclude="/${OUT#"$home"/}")

  fstype=$(stat -f -c %T "$DEST_ROOT")
  case "$fstype" in
    ext2/ext3 | btrfs | xfs | f2fs | zfs | tmpfs) opts=(-aH) ;;
    *) opts=(-rt --modify-window=2)
       note "USB is $fstype: symlinks and file permissions won't be kept (fine for a backup)" ;;
  esac

  # size check
  local need avail
  need=$(rsync "${opts[@]}" -n --stats "${excludes[@]}" "$home/" "$dest/" 2>/dev/null |
    awk -F': ' '/^Total file size/ {gsub(/[^0-9]/, "", $2); print $2}')
  avail=$(df -B1 --output=avail "$DEST_ROOT" | tail -1 | tr -d ' ')
  ok "$label: about $(human "${need:-0}") to copy, $(human "$avail") free on the USB"
  if [[ -n $need ]] && ((need > avail)); then
    note "Not enough space. Check REPORT.md (big files, folder sizes) and free some up, or use a bigger drive."
    ask "Copy anyway (it will stop when the USB fills up)?" || { note "Skipped raw copy of $label"; return 0; }
  fi

  mkdir -p "$dest"
  set +e
  rsync "${opts[@]}" --info=progress2 "${excludes[@]}" "$home/" "$dest/" 2>>"$OUT/lists/copy-errors.log"
  local rc=$?
  set -e
  case $rc in
    0) ok "$label: copied to raw/$label-home" ;;
    23 | 24) note "$label: copied, but some files were skipped. See lists/copy-errors.log" ;;
    *) note "$label: copy stopped with an error ($rc). See lists/copy-errors.log" ;;
  esac
}

bundle_secrets() { # bundle_secrets <home> <label>
  local home=$1 label=$2 list p
  list=$(mktemp)
  for p in "${SECRET_PATHS[@]}"; do
    [[ -e $home/$p ]] && printf '%s\0' "$p" >>"$list"
  done
  while IFS= read -r -d '' f; do
    printf '%s\0' "${f#"$home"/}" >>"$list"
  done < <(find_env_files "$home")
  while IFS= read -r -d '' f; do
    in_secret_path "${f#"$home"/}" || printf '%s\0' "${f#"$home"/}" >>"$list"
  done < <(find_code_files "$home")

  if [[ ! -s $list ]]; then
    ok "$label: no secrets found to bundle"
    rm -f "$list"
    return 0
  fi

  local outfile="$OUT/secrets/$label-secrets.tgz.gpg"
  echo "  Encrypting $label secrets. Pick a password and save it in KeePassXC."
  set +e
  tar -C "$home" "${BROWSER_CACHE_EXCLUDES[@]}" --ignore-failed-read --null -T "$list" -czf - 2>>"$OUT/lists/copy-errors.log" |
    gpg --symmetric --cipher-algo AES256 --yes -o "$outfile"
  local codes=("${PIPESTATUS[@]}")
  set -e
  rm -f "$list"
  if [[ ${codes[1]} -eq 0 && -s $outfile ]]; then
    ok "$label: secrets encrypted → secrets/$label-secrets.tgz.gpg ($(human "$(stat -c %s "$outfile")"))"
    if [[ ${codes[0]} -ne 0 ]]; then
      note "Some files changed while reading (an open browser?). Fine, but close browsers for a cleaner copy."
    fi
  else
    rm -f "$outfile"
    note "$label: encryption didn't finish, so secrets were NOT saved. Re-run when ready."
    ATTENTION+=("**$label secrets were not saved** (encryption cancelled or failed). Re-run collect.sh.")
  fi
}

process_home() { # process_home <home> <label>
  local home=$1 label=$2
  step "Scanning $label ($home)"
  md
  md "## $label"
  md
  report_repos "$home" "$label"
  report_env "$home" "$label"
  report_browsers "$home" "$label"
  report_big_files "$home" "$label"
  report_sizes "$home" "$label"
}

# --- this system only -------------------------------------------------------
report_system() {
  step "Checking what's installed and running"
  md
  md "## Installed and running (this system)"
  md
  if have pacman; then
    pacman -Qqe >"$OUT/lists/omarchy-packages.txt" 2>/dev/null || true
    pacman -Qqm >"$OUT/lists/omarchy-aur-packages.txt" 2>/dev/null || true
    md "- Packages: \`lists/omarchy-packages.txt\` ($(wc -l <"$OUT/lists/omarchy-packages.txt") explicit), AUR: \`lists/omarchy-aur-packages.txt\`"
  fi
  if have npm; then npm ls -g --depth=0 >"$OUT/lists/npm-global.txt" 2>/dev/null || true; fi
  if have mise; then mise ls >"$OUT/lists/mise.txt" 2>/dev/null || true; fi
  if have flatpak; then flatpak list --app --columns=application >"$OUT/lists/flatpaks.txt" 2>/dev/null || true; fi
  md

  local running=""
  if have systemctl; then
    systemctl --user list-unit-files --state=enabled --no-legend 2>/dev/null >"$OUT/lists/user-services-enabled.txt" || true
    running=$(systemctl --user list-units --type=service,timer --state=running,active --no-legend --plain 2>/dev/null |
      awk '{print $1}' | grep -vE '^(dbus|pipewire|wireplumber|xdg-|at-spi|gvfs|gnome-keyring|p11-kit|app-|dconf|evolution|tracker|obex|ssh-agent|gpg-agent|elephant|walker|hyprpolkit|mako|swayosd|waybar|hypridle|hyprsunset|uwsm|systemd-tmpfiles|grub-|pulse|filter-chain)' || true)
  fi
  md "### Your own services and scheduled jobs"
  md
  md "Anything here might be a bot or server you set up. Stop it and note it in the project's STATUS.md before wiping."
  md
  md '```'
  md "${running:-(no custom user services running)}"
  local cron
  cron=$(crontab -l 2>/dev/null || true)
  [[ -n $cron ]] && { md ""; md "crontab:"; md "$cron"; crontab -l >"$OUT/lists/crontab.txt" 2>/dev/null || true; }
  if have docker && docker ps --format '{{.Names}}  {{.Image}}  {{.Status}}' >/dev/null 2>&1; then
    local d; d=$(docker ps --format '{{.Names}}  {{.Image}}  {{.Status}}')
    [[ -n $d ]] && { md ""; md "docker containers:"; md "$d"; }
  fi
  md '```'
  md
  if [[ -n $running || -n $cron ]]; then
    ATTENTION+=("**Custom services or cron jobs are set up.** Make sure none of them is a live bot. See *Your own services*.")
  fi
  ok "Package lists and services saved"
}

# --- run --------------------------------------------------------------------
if [[ $(df --output=source "$HOME" | tail -1) == $(df --output=source "$DEST_ROOT" | tail -1) ]]; then
  note "$DEST_ROOT is on the same drive as your home folder, not a USB."
  ask "Continue anyway?" || exit 1
fi

pgrep -x -u "$USER" firefox >/dev/null 2>&1 || pgrep -x -u "$USER" chromium >/dev/null 2>&1 &&
  note "A browser is open. Closing it first gives a cleaner copy of its profile."

echo "Backing up to: $OUT"

report_system
process_home "$HOME" omarchy
if [[ -n $FEDORA_HOME ]]; then process_home "$FEDORA_HOME" fedora; fi

if ((!REPORT_ONLY)); then
  step "Encrypting secrets (SSH keys, .env files, browser profiles, history, tokens)"
  bundle_secrets "$HOME" omarchy
  if [[ -n $FEDORA_HOME ]]; then bundle_secrets "$FEDORA_HOME" fedora; fi

  step "Copying files (this can take a while)"
  copy_raw "$HOME" omarchy
  if [[ -n $FEDORA_HOME ]]; then copy_raw "$FEDORA_HOME" fedora; fi
fi

if [[ -z $FEDORA_HOME ]]; then
  ATTENTION+=("**Fedora wasn't included.** Mount its home (see \`collect.sh --help\`) and re-run with \`--fedora-home\`.")
fi
if ((REPORT_ONLY)); then ATTENTION+=("**Report only:** nothing was copied yet. Re-run without \`--report-only\`."); fi

# --- finish the report ------------------------------------------------------
{
  echo
  echo "## Still to do by hand"
  echo
  echo "- [ ] Export saved passwords from every browser and account into KeePassXC, then delete the CSV files"
  echo "- [ ] Save open tabs you care about as bookmarks (tabs aren't captured)"
  echo "- [ ] Check Google Drive / Photos / other cloud accounts are synced"
  echo "- [ ] Fix every ⚠️ repo above (commit + push)"
  echo "- [ ] Open a few files from \`raw/\` and test the secrets bundle (below) before wiping"
  echo
  echo "## Opening the secrets bundle"
  echo
  echo '```'
  echo "mkdir -p ~/restore && gpg -d secrets/omarchy-secrets.tgz.gpg | tar xzf - -C ~/restore"
  echo '```'
  echo
  echo "It holds SSH keys, .env files, browser profiles, shell history and login tokens. Keep the USB somewhere safe."
} >>"$REPORT"

attention_md=$(mktemp)
{
  echo "## Needs your attention"
  echo
  if ((${#ATTENTION[@]})); then
    printf -- '- %s\n' "${ATTENTION[@]}"
  else
    echo "- Nothing flagged. 🎉"
  fi
} >"$attention_md"
sed -i -e "/<!-- ATTENTION -->/{r $attention_md" -e 'd}' "$REPORT"
rm -f "$attention_md"

step "Done"
echo "  Read the report first:  $REPORT"
if ((${#ATTENTION[@]})); then
  echo "  ${#ATTENTION[@]} thing(s) need your attention:"
  printf '   - %s\n' "${ATTENTION[@]}" | sed 's/\*\*//g'
fi

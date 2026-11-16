# dotfiles

My setup for a fresh Omarchy install: configs, folder layout, project and
business templates, and a few helper commands.

## Before a wipe: collect everything

```bash
~/dotfiles/collect.sh /run/media/$USER/<usb> --report-only     # preview
~/dotfiles/collect.sh /run/media/$USER/<usb> --fedora-home /mnt/fedora/<you>
```

It writes `laptop-backup-<date>/` on the USB:

- `REPORT.md`: start here. Repos with unpushed work, `.env` files, custom
  services or cron jobs (bots), big files, browser extensions, what's left to do by hand
- `raw/`: unsorted copy of each home folder, minus caches and secrets
- `secrets/`: one encrypted file per system (SSH keys, `.env` files, browser
  profiles, shell history, tokens). You pick the password; save it in KeePassXC.
- `browsers/`: bookmarks as importable HTML, extension lists
- `lists/`: installed packages, repo status, folder sizes

Close the browsers first. `collect.sh --help` shows how to mount the Fedora
partition read-only. Sort `raw/` into the new layout after the fresh install,
not before.

## Fresh install (4 commands)

```bash
sudo pacman -S --needed github-cli
gh auth login                       # pick SSH, let it make a key
gh repo clone fresh-start ~/dotfiles
~/dotfiles/bootstrap.sh             # add --dry-run first to preview
```

`bootstrap.sh` is safe to re-run. It skips anything already done and never
deletes files. Anything it would replace gets renamed to `*.bak-<timestamp>`.

## What bootstrap does

1. Installs the packages in `packages/` (KeePassXC, gh, gitleaks, Syncthing, Crush...)
2. Creates the folder layout below and locks down `~/.secrets` and `~/vault`
3. Puts the helper commands on your PATH
4. Links every config in `home/` into `~` (desktop, bar, terminal, prompt,
   bashrc, git, Claude Code settings). See [docs/desktop.md](docs/desktop.md)
5. Desktop extras: clones the 5 third-party bar plugins, restores saved data
   from `seed/`, and (asking first) installs the lid/hibernate files from
   `system/` into `/etc`
6. Sets up git and GitHub login
7. Offers to clone all your repos into `~/projects/archive`
8. Offers to install Claude Code, Hermes, and Node/Python via mise
9. Prints the steps left to do by hand

## Folder layout

```
~/dotfiles/            this repo
~/vault/               KeePassXC .kdbx (back this up)
~/.secrets/            plain-text keys, chmod 700 (never sync)
~/projects/
  active/              projects you're working on (each one is a git repo)
  archive/             benched projects
  sandbox/             throwaway experiments
  shared/
    ai/                reusable prompts, skills
    scripts/
    templates/  →      links to ~/dotfiles/templates
~/business/
  <business>/          legal, contracts, finance, clients, brand, ops
  ideas/               one note per idea
  archive/
```

## Commands

| Command | What it does |
| ------- | ------------ |
| `new-project "Name"` | New project in `~/projects/active` from the template, first commit, optional private GitHub repo |
| `bench-project name` | Moves a project to `archive`, but only once everything is committed and pushed |
| `unbench-project name` | Moves it back to `active` |
| `new-business "Name"` | New business folder in `~/business` from the template |
| `clone-repos` | Clones all your GitHub repos into `~/projects/archive` |
| `dot-add ~/.config/x` | Starts tracking a config file in this repo |

## Templates

- `templates/project/`: `STATUS.md` (status, costs, keys, bench checklist),
  `CLAUDE.md` (rules for Claude Code), `.gitignore`, `.env.example`, `docs/`,
  `design/mockups/`, `ai/`, `finances/` (ignored by git). Add `marketing/` only
  if a project needs it.
- `templates/business/`: `STATUS.md`, `legal/`, `contracts/`,
  `finance/{receipts,taxes,<year>}/`, `clients/`, `brand/`, `ops/`

Edit the templates here, commit, and every new project picks up the change.

## Rules

- No secrets in this repo, ever. The `.gitignore` here and the global one in
  `home/.config/git/ignore` block the usual suspects. Run `gitleaks detect`
  before pushing anything you're unsure about.
- One `.kdbx` vault with groups: Personal, Banking, Dev accounts,
  Projects/<name>, Business/<name>.
- Chromium profiles: Personal, Dev, Business. Not one per project.
- One OpenRouter key per tool, each with a spending cap. Auto top-up off.

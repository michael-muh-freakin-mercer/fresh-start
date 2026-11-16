# home/

Everything in this folder mirrors your home directory. `bootstrap.sh` links each
file into the same place under `~`:

```
~/dotfiles/home/.config/git/ignore  →  ~/.config/git/ignore
```

## Keep a new config

```bash
dot-add ~/.config/hypr/bindings.conf
cd ~/dotfiles && git add -A && git commit -m "Track hypr bindings" && git push
```

`dot-add` moves the file in here and leaves a link in its old spot, so the app
keeps working and edits land in the repo.

## Don't put here

- API keys, `.env` files, SSH keys or the `.kdbx` vault
- Anything with passwords in it (check before `git add`)

## Heads-up

If you run an Omarchy reset (`omarchy-refresh-...`) on a file you track, it
writes the default into this repo. Run `git diff` in `~/dotfiles` afterwards and
use `git restore <file>` to get your version back.

Some apps save a file by writing a new copy and renaming it over the old one.
That replaces the link with a plain file, and later changes stop reaching this
repo. If a change doesn't show up in `git status`, check with
`ls -l ~/.config/omarchy/shell.json` (or whichever file it was). If it's no longer
a link, copy it back here and re-run `bootstrap.sh`. The files most likely to
do this are `omarchy/shell.json` and `~/.claude/settings.json`.

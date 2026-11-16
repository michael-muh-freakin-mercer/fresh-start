# Desktop setup

My [Omarchy](https://omarchy.org/) desktop setup (Arch Linux + Hyprland) on a
ThinkPad T480, kept here so I can rebuild it on any machine.

These files live in `home/.config/` in this repo, and `bootstrap.sh` links
them into `~/.config`. (They used to be their own repo, omarchy-config.)

## What's in here

| Path | What it is |
|---|---|
| `omarchy/shell.json` | Bar layout and shell settings (which widgets sit where, idle and lock timing) |
| `omarchy/plugins/michael.*` | My own bar widgets, mostly customized copies of Omarchy's built-in ones (see below) |
| `omarchy/themes/` | Custom theme: `switch-swirl-wallpaper` |
| `omarchy/lock-designs/`, `lock-videos/`, `boot-designs/` | Lock screen and boot screen designs |
| `omarchy/hooks/` | Scripts that run on system events (after boot, after updates, on theme change) |
| `omarchy/extensions/`, `branding/`, `defaults/` | Custom menu entries, About/screensaver text, default coding agent |
| `hypr/` | Hyprland: keybindings, window rules, look and feel |
| `foot/`, `starship.toml` | Terminal and shell prompt |
| `herdr/`, `mise/` | Agent runner and tool-version config |
| `AGENTS.md` | Ground rules for AI assistants editing this setup |

## My bar widgets

| Widget | Based on | What I changed |
|---|---|---|
| `michael.power` | Omarchy power | Battery shown as a number with a thin gauge line, combining both T480 batteries; the line pulses while charging. A CPU temperature readout appears beside it only when the CPU runs warm (75°C+), red at 85°C+ |
| `michael.agents` | Omarchy agents | One atom icon with a ring showing Claude session usage; live agent status and launcher ([details](../home/.config/omarchy/plugins/michael.agents/README.md)) |
| `michael.network` | Omarchy network | Wi-Fi icon in the theme's accent color |
| `michael.indicators` | Omarchy indicators | Stay-awake (coffee cup) icon in the accent color |
| `michael.lock` | Omarchy lock | Custom lock screen with separate password and fingerprint flows |
| `michael.power-menu` | (new) | See-through suspend / shut down / restart overlay |

The copies don't pick up Omarchy's future updates to the originals. To go
back to a stock widget, change its id in `omarchy/shell.json` from
`michael.<name>` to `omarchy.<name>` and run `omarchy restart shell`.

Third-party widgets (workspaces-jap, lock-explorer, screen-time, omaplug,
daily) aren't stored here. They live in their own GitHub repos, and
`bootstrap.sh` clones them.

## Outside ~/.config

| In this repo | Goes to | What it is |
|---|---|---|
| `home/.local/bin/battery-status-combined` | `~/.local/bin` | Both T480 batteries as one number (michael.power reads it) |
| `home/.local/bin/omarchy-agent-usage-*` | `~/.local/bin` | Usage numbers for the agents ring |
| `system/etc/systemd/...` | `/etc/systemd/...` | Lid closed = suspend, then hibernate after 90 min (bootstrap asks for sudo) |
| `seed/.config/omarchy/screen-time/history.json` | copied once | Screen-time history; copied, not linked, because the plugin rewrites it |

Hibernation also needs swap and a resume setting: `omarchy hibernation setup`,
reboot, then test once with `systemctl hibernate`.

## Not in this repo, on purpose

- **API keys** for the agents widget (`omarchy/agents/` is ignored). Re-enter them in the agents panel.
- **Backup copies** (`*.bak`, `*.before-*`). Git history covers that.
- **The Plymouth boot animation.** Its source is its own project (`designDen/plymouth`).
- **Lock screen avatar photo**, which lives in `~/Pictures`.

## Applying changes

| After editing | Run |
|---|---|
| `omarchy/shell.json` | Nothing, it reloads on save |
| A plugin in `omarchy/plugins/` | `omarchy restart shell` |
| `hypr/` | Reloads on save; check with `hyprctl configerrors` |
| Terminal config | `omarchy restart terminal` |

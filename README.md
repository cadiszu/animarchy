# Animarchy

An Omarchy bar plugin for [ani-cli](https://github.com/pystardust/ani-cli): search anime, browse episodes in a grid, stream via mpv, bulk-download, and resume from history — all from a themed popup. No terminal juggling.

## Features

- **Search tab** — type a query, get results inline, pick a title to load its episode grid (8-column, scrollable, filters by episode range)
- **Now playing footer** — shows current title + episode with **Prev / Next** buttons (swaps the stream, kills the old player)
- **Play History tab** — one row per title, newest first, with the last-watched episode pill; click resumes that episode and opens its episode grid, `☰` opens the grid without playing
- **Episode range filter** — e.g. `5-100` narrows the grid; bulk download uses exactly what's shown
- **Bulk download** — "Download all N episodes" button; saves to `<folder>/<Title>/` with mp4 + subtitles (popup stays open so progress/errors stay visible in the floating terminal)
- **Settings (gear icon)** — English dub (falls back to sub when no dub source), Download mode, Skip intro, Next-ep countdown, quality selector, episode range, download folder (type or Browse…)
- **Click-to-install** missing optional tools (ani-skip) from inside the panel
- Long history titles get a scrolling marquee (pauses on hover); everything follows the active Omarchy theme

## Requirements

- [ani-cli](https://github.com/pystardust/ani-cli) (`ani-cli` on AUR)
- `mpv` (default player)
- `python3` ( powers the search/episode resolver)
- Optional: `ani-skip` (Skip intro toggle), `zenity` (folder Browse button), `yt-dlp`/`ffmpeg` (ani-cli downloads)

If `ani-cli` itself is missing, the popup shows an **Install ani-cli** button that installs it via `omarchy pkg aur add ani-cli`.

## Install

```bash
omarchy plugin add https://github.com/cadiszu/animarchy.git --enable --yes
```

This clones the repo to `~/.config/omarchy/plugins/animarchy/` and adds the widget to the bar (right section by default).

> **Bar position:** `--yes` skips Omarchy's interactive prompts and takes the
> manifest default (`right`). To pick left / center / right during install,
> drop `--yes` — the installer will ask which section to place the widget in.

Note the two names, because the CLI treats them differently:

- `omarchy plugin ...` takes the **install directory**, `animarchy`.
- `omarchy bar ...` takes the **plugin id** from the manifest, `io.github.cadiszu.animarchy`.

So reposition the widget with the full id (works any time after install):

```bash
omarchy bar move io.github.cadiszu.animarchy left
omarchy bar move io.github.cadiszu.animarchy center
omarchy bar move io.github.cadiszu.animarchy right
```

## Uninstall

Remove the plugin itself:

```bash
omarchy plugin remove animarchy --yes
```

(`remove` takes the install directory, not the plugin id.)

Remove the companion tools it uses (keeps shared packages like `mpv`, `fzf`, `ffmpeg`, `yt-dlp`, `zenity`, and `python3`, which other software needs):

```bash
omarchy pkg drop ani-cli ani-skip-git
```

Optionally clear the watch history as well:

```bash
rm -rf ~/.local/state/ani-cli
```

## Usage

- **Left-click** the bar icon: open the popup. **Right-click**: resume the last episode (`ani-cli -c`).
- Type in the search field on either tab and press Enter — results always land on the Search tab.
- Click a result → episode grid → click a tile to play (mpv floats, focused).
- Play History rows resume the saved episode and open that title's episode grid, so Prev/Next can step to neighboring episodes; the `☰` button opens the grid without autoplaying.
- The popup stays open while playing so Prev/Next remain one click away.

## Notes

- Search/episode/stream resolution reuses ani-cli's own scraping. `anicli-lib.sh` is a pinned, verbatim copy of lines 1-476 of ani-cli v5.1.0, cut just before the CLI's argument-parsing loop, so the panel can call the scraping helpers directly instead of driving the fzf/mpv TUI. To retarget a newer ani-cli, bump the line count and regenerate:

  ```bash
  head -n 476 /usr/bin/ani-cli > anicli-lib.sh
  ```
- Plays started from the popup are recorded to ani-cli's history file, so Play History stays in sync with terminal use.
- Download mode shells out to `ani-cli -d` in a floating terminal; progress and errors are visible there.

## Legal

This plugin scrapes [allanime](https://allanime.day) through ani-cli to resolve
stream URLs. That is third-party content; you are responsible for complying with
the law and the site's terms where you live.

## License

GPL-3.0 — see [LICENSE](LICENSE).

`anicli-lib.sh` is a verbatim excerpt of [ani-cli](https://github.com/pystardust/ani-cli)
v5.1.0, Copyright (C) the ani-cli contributors, which is GPL-3.0. Vendoring it
makes this plugin a derivative work, so animarchy is distributed under the same
license. The rest of the code (QML panels, `anicli-data`, the helper scripts, and
the icon) was written for this plugin.

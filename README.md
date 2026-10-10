# Animarchy

An Omarchy bar plugin for [ani-cli](https://github.com/pystardust/ani-cli): search anime, browse episodes in a grid, stream via mpv, bulk-download, and resume from history — all from a themed popup. No terminal juggling.

## Features

- **Search tab** — type a query, get results inline, pick a title to load its episode grid (8-column, scrollable, filters by episode range)
- **Now playing footer** — shows current title + episode with **Prev / Next** buttons (swaps the stream, kills the old player)
- **Play History tab** — one row per title, newest first, with the last-watched episode pill; click resumes that episode and opens its episode grid, `☰` opens the grid without playing
- **Episode range filter** — e.g. `5-100` narrows the grid; bulk download uses exactly what's shown
- **Bulk download** — "Download all N episodes" button; saves to `<folder>/<Title>/` with mp4 + subtitles (popup stays open so progress/errors stay visible in the floating terminal)
- **Settings (gear icon)** — English dub (falls back to sub when no dub source), Download mode, Skip intro, Next-ep countdown, quality selector, episode range, download folder (type or Browse…)
- **Click-to-install** missing optional tools (`ani-cli`, `ani-skip`) from inside the panel
- Long history titles get a scrolling marquee (pauses on hover); everything follows the active Omarchy theme

## Requirements

- `mpv` (default player)
- `python3` (powers the search/episode resolver)

Optional, each unlocking a specific feature:

- [ani-cli](https://github.com/pystardust/ani-cli) (`ani-cli` on AUR) — required for **downloads** and **right-click resume**. Search, episode browsing, playback, and Play History run through the scraper vendored in `anicli-lib.sh` and work without it.
- `ani-skip` (`ani-skip-git` on AUR) — the Skip intro toggle
- `zenity` — the download-folder Browse button
- `yt-dlp` / `ffmpeg` — downloads

### One-click install

Open the panel and both optional binaries are probed on the spot (`command -v`). Anything missing shows an **Install** button right there — ani-cli in the main panel, ani-skip under Settings. Each opens a floating terminal running `omarchy pkg aur add <package>`, so pacman output and any `sudo` prompt are visible rather than hidden. After it finishes the panel re-probes for about a minute and the button disappears on its own, so no restart is needed. Right-clicking the bar icon while ani-cli is absent opens the panel directly onto that banner.

> These buttons install packages on your system and may ask for `sudo`. They only ever appear for a package that is actually missing.

## Install

```bash
omarchy plugin add https://github.com/cadiszu/animarchy.git --enable
```

This clones the repo into `~/.config/omarchy/plugins/io.github.cadiszu.animarchy/` and then asks which bar section to use — **left**, **center**, or **right** — with `right` pre-selected.

To move it afterwards:

```bash
omarchy bar move io.github.cadiszu.animarchy left
omarchy bar move io.github.cadiszu.animarchy center
omarchy bar move io.github.cadiszu.animarchy right
```

> The install folder is named after the plugin id, so `omarchy plugin enable`,
> `disable`, `update`, and `remove` all take `io.github.cadiszu.animarchy` too.
>
> Installing from a script, dotfiles bootstrap, or CI — anywhere without a
> terminal to draw the prompts on — needs `--yes` as well, which takes the
> `right` default without asking.

## Uninstall

Remove the plugin itself:

```bash
omarchy plugin remove io.github.cadiszu.animarchy
```

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

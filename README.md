# Animarchy

An Omarchy bar plugin for [ani-cli](https://github.com/pystardust/ani-cli): search anime, browse episodes in a grid, stream via mpv, bulk-download, and resume from history — all from a themed popup. No terminal juggling.

## Features

- **Search tab** — type a query, get results inline, pick a title to load its episode grid (8-column, scrollable, filters by episode range)
- **Now playing footer** — shows current title + episode with **Prev / Next** buttons (swaps the stream, kills the old player)
- **Play History tab** — one row per title, newest first, with the last-watched episode pill; click resumes that episode directly, `☰` opens its episode grid instead
- **Episode range filter** — e.g. `5-100` narrows the grid; bulk download uses exactly what's shown
- **Bulk download** — "Download all N episodes" button; saves to `<folder>/<Title>/` with mp4 + subtitles
- **Settings (gear icon)** — English dub (falls back to sub when no dub source), Download mode, Skip intro, Next-ep countdown, quality selector, episode range, download folder (type or Browse…)
- **Click-to-install** missing optional tools (ani-skip) from inside the panel
- Long history titles get a scrolling marquee (pauses on hover); everything follows the active Omarchy theme

## Requirements

- [ani-cli](https://github.com/pystardust/ani-cli) (`ani-cli` on AUR)
- `mpv` (default player)
- `python3` ( powers the search/episode resolver)
- Optional: `ani-skip` (Skip intro toggle), `zenity` (folder Browse button), `yt-dlp`/`ffmpeg` (ani-cli downloads)

## Install

```bash
omarchy plugin add https://github.com/<you>/animarchy.git --enable --yes
```

This clones the repo to `~/.config/omarchy/plugins/animarchy/` and adds the widget to the bar (right section by default). Move it with:

```bash
omarchy bar move animarchy --section right
```

## Usage

- **Left-click** the bar icon: open the popup. **Right-click**: resume the last episode (`ani-cli -c`).
- Type in the search field on either tab and press Enter — results always land on the Search tab.
- Click a result → episode grid → click a tile to play (mpv floats, focused).
- Play History rows resume the saved episode; the `☰` button opens that title's grid instead.
- The popup stays open while playing so Prev/Next remain one click away.

## Notes

- Search/episode/stream resolution reuses ani-cli's own scraping (`anicli-lib.sh` is extracted from the installed `/usr/bin/ani-cli`), so it tracks upstream behavior.
- Plays started from the popup are recorded to ani-cli's history file, so Play History stays in sync with terminal use.
- Download mode shells out to `ani-cli -d` in a floating terminal; progress and errors are visible there.

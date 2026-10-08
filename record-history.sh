#!/bin/sh
# record-history.sh <ep> <anime-id> <title>
# One row per title: drops any older row for the same anime id, then appends
# the new one. Uses a lock so rapid replays can't interleave two writes.
hist="${ANI_CLI_HIST_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/ani-cli}/ani-hsts"
mkdir -p "$(dirname "$hist")"
touch "$hist"

tmp="${hist}.tmp"
lock="${hist}.lock"
(
  if command -v flock >/dev/null 2>&1; then
    flock 9 || exit 1
  fi
  awk -F'\t' -v id="$2" '$2 != id' "$hist" > "$tmp" 2>/dev/null || cp "$hist" "$tmp" 2>/dev/null || true
  printf "%s\t%s\t%s\n" "$1" "$2" "$3" >> "$tmp"
  mv "$tmp" "$hist"
) 9>"$lock"

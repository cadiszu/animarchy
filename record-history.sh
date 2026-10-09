#!/bin/sh
# record-history.sh <ep> <anime-id> <title>
# One row per title: drops any older row for the same anime id, then appends
# the new one. Uses a lock so rapid replays can't interleave two writes.
hist="${ANI_CLI_HIST_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/ani-cli}/ani-hsts"
mkdir -p "$(dirname "$hist")"
touch "$hist"

tmp="${hist}.tmp"
lock="${hist}.lock"

# Titles come from the provider, not from us, and this file is tab-separated:
# a tab or newline in a title would split the row into extra fields and a
# newline would forge a bogus entry that ani-cli also reads. Flatten both.
ep=$(printf '%s' "$1" | tr '\t\n' '  ')
id=$(printf '%s' "$2" | tr '\t\n' '  ')
title=$(printf '%s' "$3" | tr '\t\n' '  ')

(
  if command -v flock >/dev/null 2>&1; then
    flock 9 || exit 1
  fi
  awk -F'\t' -v id="$id" '$2 != id' "$hist" > "$tmp" 2>/dev/null || cp "$hist" "$tmp" 2>/dev/null || true
  printf "%s\t%s\t%s\n" "$ep" "$id" "$title" >> "$tmp"
  mv "$tmp" "$hist"
) 9>"$lock"

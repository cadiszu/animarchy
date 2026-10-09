#!/bin/sh
# watch-mpv.sh [wait_seconds]
# Blocks until the mpv instance this panel just started has exited.
# Exit 2 = the player is gone (it never started, or it closed) -> the panel
# hides the Now Playing footer. Exit 0 = the watch window elapsed.
#
# Phase 1 must WAIT for launch-mpv.sh to publish a pid. anicli-data resolves
# the stream over the network first, so for the first seconds there is no pid
# at all; treating that as "player exited" hid the footer while the episode
# was still playing. It also skips a stale pid left by a previous episode,
# which launch-mpv.sh is about to kill.

PIDFILE="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/omarchy-anicli-mpv.pid"
WAIT_MAX=${1:-180}
# Safety valve only, kept well above any plausible playback length: if this
# expires while an episode is still running, the footer stops auto-hiding.
WATCH_MAX=43200

# No `ps` (minimal image): fall back to "a pid was published".
alive() {
  if command -v ps >/dev/null 2>&1; then
    ps -p "$1" >/dev/null 2>&1
  else
    [ -n "$1" ]
  fi
}

read_pid() {
  cat "$PIDFILE" 2>/dev/null
}

before=""
[ -f "$PIDFILE" ] && before="$(read_pid)"

# Phase 1: wait for a new, live pid to show up.
pid=""
i=0
while [ "$i" -lt "$WAIT_MAX" ]; do
  cur="$(read_pid)"
  if [ -n "$cur" ] && [ "$cur" != "$before" ] && alive "$cur"; then
    pid="$cur"
    break
  fi
  sleep 1
  i=$((i + 1))
done

# Resolve failed or mpv never started: report the player as gone.
[ -z "$pid" ] && exit 2

# Phase 2: follow the pid. Next/Prev republishes the pidfile, so hop to the
# replacement instead of reporting an exit when the old pid dies.
i=0
while [ "$i" -lt "$WATCH_MAX" ]; do
  if ! alive "$pid"; then
    cur="$(read_pid)"
    if [ -n "$cur" ] && [ "$cur" != "$pid" ] && alive "$cur"; then
      pid="$cur"
    else
      exit 2
    fi
  fi
  sleep 1
  i=$((i + 1))
done
exit 0
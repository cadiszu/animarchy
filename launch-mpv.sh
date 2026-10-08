#!/bin/sh
# launch-mpv.sh <video_link> <referrer> <sub_link> <media_title>
# Replaces any previously running media player started by this plugin,
# so Next/Previous swaps the stream without leaving the old one playing.
PIDFILE="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/omarchy-anicli-mpv.pid"
if [ -f "$PIDFILE" ]; then
  old="$(cat "$PIDFILE" 2>/dev/null)"
  if [ -n "$old" ]; then
    # Only signal the old PID when it is still an mpv process, so a
    # recycled PID belonging to something else is never killed.
    if command -v ps >/dev/null 2>&1; then
      comm="$(ps -p "$old" -o comm= 2>/dev/null)"
      case "$comm" in *mpv*) kill "$old" 2>/dev/null ;; esac
    else
      kill "$old" 2>/dev/null
    fi
  fi
fi
if [ -n "$3" ]; then
  mpv --referrer="$2" --sub-file="$3" --force-media-title="$4" "$1" >/dev/null 2>&1 &
else
  mpv --referrer="$2" --force-media-title="$4" "$1" >/dev/null 2>&1 &
fi
echo $! > "$PIDFILE"

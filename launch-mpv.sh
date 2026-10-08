#!/bin/sh
# launch-mpv.sh <video_link> <referrer> <sub_link> <media_title>
# Replaces any previously running media player started by this plugin,
# so Next/Previous swaps the stream without leaving the old one playing.
PIDFILE="${TMPDIR:-/tmp}/omarchy-anicli-mpv.pid"
if [ -f "$PIDFILE" ]; then
  old="$(cat "$PIDFILE" 2>/dev/null)"
  [ -n "$old" ] && kill "$old" 2>/dev/null
fi
sub_arg=""
[ -n "$3" ] && sub_arg="--sub-file=$3"
mpv --referrer="$2" $sub_arg --force-media-title="$4" "$1" >/dev/null 2>&1 &
echo $! > "$PIDFILE"

#!/usr/bin/env bash
# Records one take with Godot Movie Maker on a private Xvfb display, from inside
# a capture worktree:  tools/promo/shot.sh <name> <display> [director args...]
# Frames land in $PROMO_OUT/shots/<name>/f%08d.png with the game audio in f.wav.
set -Euo pipefail
readonly KIT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly ROOT="$(git -C "$KIT" rev-parse --show-toplevel)"
readonly PROMO_OUT="${PROMO_OUT:-/tmp/opencode/pc-promo}"
readonly FPS=30
name="$1"; display="$2"; shift 2
out="$PROMO_OUT/shots/$name"
rm -rf "$out"; mkdir -p "$out"
# Each take gets its own save so parallel takes never share state.
export XDG_DATA_HOME="$PROMO_OUT/data/$name"
rm -rf "$XDG_DATA_HOME"; mkdir -p "$XDG_DATA_HOME"
godot --path "$ROOT" --headless --script res://tools/create_media_save.gd >/dev/null 2>&1
start=$(date +%s)
timeout 3000 xvfb-run -n "$display" -s "-screen 0 2560x1440x24" \
	godot --path "$ROOT" --audio-driver Dummy --write-movie "$out/f.png" --fixed-fps "$FPS" -- "$@" > "$out/log.txt" 2>&1
echo "$name exit $? in $(( $(date +%s) - start ))s, $(ls "$out" | grep -c png) frames"
grep -E "PROMO start|SCRIPT ERROR" "$out/log.txt" | head -5

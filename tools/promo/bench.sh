#!/usr/bin/env bash
# Headless driving benchmark (~20 s per 30 s race, no rendering). Prints race
# progress, position, drift/boost seconds and hard hits for the player's car:
#   tools/promo/bench.sh <name> --theme=kitchen --seed=274524 --boss=1 --b-hold=0.15
# Run several with different args in parallel to tune the boss driver.
set -Euo pipefail
readonly KIT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly ROOT="$(git -C "$KIT" rev-parse --show-toplevel)"
readonly PROMO_OUT="${PROMO_OUT:-/tmp/opencode/pc-promo}"
name="$1"; shift
export XDG_DATA_HOME="$PROMO_OUT/data/bench-$name"
rm -rf "$XDG_DATA_HOME"; mkdir -p "$XDG_DATA_HOME"
godot --path "$ROOT" --headless --script res://tools/create_media_save.gd >/dev/null 2>&1
timeout 900 godot --path "$ROOT" --headless --fixed-fps 60 --audio-driver Dummy -- \
	--promo-shot=race --seconds=31 --metrics=1 --m-every=10 "$@" > "$PROMO_OUT/bench-$name.log" 2>&1
grep "PROMO m" "$PROMO_OUT/bench-$name.log" | tail -n 1 | sed "s/^/$name /"

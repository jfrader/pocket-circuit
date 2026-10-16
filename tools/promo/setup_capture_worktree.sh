#!/usr/bin/env bash
# Creates a throwaway detached worktree for promo capture:
#   tools/promo/setup_capture_worktree.sh <dest> [ref=origin/dev]
# It registers the promo director autoload and a 2560x1440 window there (never in
# your checkout), syncs the Gamestruments addon (no music without it) and imports.
set -Eeuo pipefail
readonly KIT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly REPO="$(git -C "$KIT" rev-parse --show-toplevel)"
readonly DEST="${1:?usage: setup_capture_worktree.sh <dest> [ref]}"
readonly REF="${2:-origin/dev}"
readonly CAPTURE_WIDTH=2560
readonly CAPTURE_HEIGHT=1440

git -C "$REPO" fetch -q origin
git -C "$REPO" worktree add --detach "$DEST" "$REF"
# Use this kit even when the ref predates it.
rm -rf "$DEST/tools/promo"
cp -r "$KIT" "$DEST/tools/promo"
sed -i \
	-e 's|^App="\*res://scripts/autoload/app.gd"|&\nPromoDirector="*res://tools/promo/promo_director.gd"|' \
	-e "s|^window/size/viewport_height=720|&\nwindow/size/window_width_override=$CAPTURE_WIDTH\nwindow/size/window_height_override=$CAPTURE_HEIGHT|" \
	"$DEST/project.godot"
grep -q PromoDirector "$DEST/project.godot" || { echo "Could not register the PromoDirector autoload" >&2; exit 1; }
GAMESTRUMENTS_ADDON_DIR="$DEST/vendor/gamestruments" "$DEST/tools/sync_gamestruments.sh"
godot --path "$DEST" --headless --editor --import --quit >/dev/null 2>&1
echo "Capture worktree ready: $DEST"
echo "Remove it afterwards with: git -C $REPO worktree remove --force $DEST"

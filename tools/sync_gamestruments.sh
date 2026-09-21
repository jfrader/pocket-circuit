#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/addons/gamestruments"
BIN="$DEST/bin"
mkdir -p "$BIN"

if [[ -n "${GAMESTRUMENTS_ADDON_DIR:-}" ]]; then
	if [[ ! -f "$GAMESTRUMENTS_ADDON_DIR/gamestruments.gdextension" ]]; then
		echo "ERROR: GAMESTRUMENTS_ADDON_DIR set but no gamestruments.gdextension found at $GAMESTRUMENTS_ADDON_DIR" >&2
		echo "Set GAMESTRUMENTS_ADDON_DIR to a directory containing a packaged addon (gamestruments.gdextension + bin/ lib or sibling lib)." >&2
		exit 1
	fi
	cp -f "$GAMESTRUMENTS_ADDON_DIR/gamestruments.gdextension" "$DEST/gamestruments.gdextension"
	if [[ -f "$GAMESTRUMENTS_ADDON_DIR/bin/libgamestruments_godot.so" ]]; then
		cp -f "$GAMESTRUMENTS_ADDON_DIR/bin/libgamestruments_godot.so" "$BIN/libgamestruments_godot.so"
	elif [[ -f "$GAMESTRUMENTS_ADDON_DIR/libgamestruments_godot.so" ]]; then
		cp -f "$GAMESTRUMENTS_ADDON_DIR/libgamestruments_godot.so" "$BIN/libgamestruments_godot.so"
	else
		echo "ERROR: GAMESTRUMENTS_ADDON_DIR set but no libgamestruments_godot.so found (looked in bin/ and alongside)." >&2
		exit 1
	fi
	echo "Synced packaged Gamestruments addon from $GAMESTRUMENTS_ADDON_DIR into $DEST"
else
	SOURCE="${GAMESTRUMENTS_ROOT:-$HOME/Workspace/gamestruments}"
	if [[ ! -d "$SOURCE" || ! -f "$SOURCE/Cargo.toml" ]]; then
		echo "ERROR: Gamestruments source not found at $SOURCE" >&2
		echo "Set GAMESTRUMENTS_ROOT=/path/to/gamestruments or GAMESTRUMENTS_ADDON_DIR=/path/to/packaged-addon" >&2
		echo "Or run from a checkout that has the source at ~/Workspace/gamestruments" >&2
		exit 1
	fi
	cargo build -p gamestruments-godot --release --manifest-path "$SOURCE/Cargo.toml"
	cp -f "$SOURCE/crates/godot/gamestruments.gdextension" "$DEST/gamestruments.gdextension"
	cp -f "$SOURCE/target/release/libgamestruments_godot.so" "$BIN/libgamestruments_godot.so"
	echo "Synced Gamestruments GDExtension (release) into $DEST"
fi

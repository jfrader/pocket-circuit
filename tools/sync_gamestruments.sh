#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${GAMESTRUMENTS_ROOT:-$HOME/Workspace/gamestruments-GURI-480}"
DEST="$ROOT/addons/gamestruments"
BIN="$DEST/bin"
mkdir -p "$BIN"
cargo build -p gamestruments-godot --manifest-path "$SOURCE/Cargo.toml"
cp "$SOURCE/crates/godot/gamestruments.gdextension" "$DEST/gamestruments.gdextension"
cp "$SOURCE/target/debug/libgamestruments_godot.so" "$BIN/libgamestruments_godot.so"
echo "Synced Gamestruments GDExtension into $DEST"

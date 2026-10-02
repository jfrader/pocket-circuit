#!/usr/bin/env bash
set -euo pipefail
command -v cmp >/dev/null 2>&1 || { printf 'cmp is required to safely sync Gamestruments.\n' >&2; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/addons/gamestruments"
BIN="$DEST/bin"
mkdir -p "$BIN"

sync_file() (
	local source="$1" destination="$2"
	if [[ -e "$destination" || -L "$destination" ]]; then
		if cmp -s -- "$source" "$destination"; then
			return 0
		else
			local status=$?
			if (( status != 1 )); then
				printf 'ERROR: cannot compare %s and %s\n' "$source" "$destination" >&2
				return "$status"
			fi
		fi
	fi
	# Replacing the inode keeps an already-loaded native library mapped safely.
	# An in-place copy truncates that mapping, even when its contents are identical.
	local staged
	staged="$(mktemp "$destination.tmp.XXXXXX")"
	trap 'rm -f -- "$staged"' EXIT
	cp --preserve=mode -- "$source" "$staged"
	mv -f -- "$staged" "$destination"
)

packaged_library() {
	local directory="$1" filename="$2" candidate
	for candidate in "$directory/bin/$filename" "$directory/$filename"; do
		if [[ -f "$candidate" ]]; then
			printf '%s\n' "$candidate"
			return 0
		fi
	done
	printf 'ERROR: packaged Gamestruments addon has no %s (looked in bin/ and alongside).\n' "$filename" >&2
	return 1
}

windows_library=""
if [[ -n "${GAMESTRUMENTS_ADDON_DIR:-}" ]]; then
	if [[ ! -f "$GAMESTRUMENTS_ADDON_DIR/gamestruments.gdextension" ]]; then
		echo "ERROR: GAMESTRUMENTS_ADDON_DIR set but no gamestruments.gdextension found at $GAMESTRUMENTS_ADDON_DIR" >&2
		echo "Set GAMESTRUMENTS_ADDON_DIR to a packaged addon containing gamestruments.gdextension plus Linux and Windows libraries in bin/ or alongside." >&2
		exit 1
	fi
	descriptor="$GAMESTRUMENTS_ADDON_DIR/gamestruments.gdextension"
	linux_library="$(packaged_library "$GAMESTRUMENTS_ADDON_DIR" libgamestruments_godot.so)"
	windows_library="$(packaged_library "$GAMESTRUMENTS_ADDON_DIR" gamestruments_godot.dll)"
	message="Synced packaged Gamestruments addon from $GAMESTRUMENTS_ADDON_DIR into $DEST"
else
	SOURCE="${GAMESTRUMENTS_ROOT:-$HOME/Workspace/gamestruments}"
	if [[ ! -d "$SOURCE" || ! -f "$SOURCE/Cargo.toml" ]]; then
		echo "ERROR: Gamestruments source not found at $SOURCE" >&2
		echo "Set GAMESTRUMENTS_ROOT=/path/to/gamestruments or GAMESTRUMENTS_ADDON_DIR=/path/to/packaged-addon" >&2
		echo "Or run from a checkout that has the source at ~/Workspace/gamestruments" >&2
		exit 1
	fi
	# Build from the source directory so gamestruments' pinned rust-toolchain.toml applies.
	( cd "$SOURCE" && cargo build -p gamestruments-godot --release )
	descriptor="$SOURCE/crates/godot/gamestruments.gdextension"
	linux_library="$SOURCE/target/release/libgamestruments_godot.so"
	message="Synced Gamestruments GDExtension (release) into $DEST"
fi

sync_file "$descriptor" "$DEST/gamestruments.gdextension"
sync_file "$linux_library" "$BIN/libgamestruments_godot.so"
if [[ -n "$windows_library" ]]; then
	sync_file "$windows_library" "$BIN/gamestruments_godot.dll"
fi
printf '%s\n' "$message"

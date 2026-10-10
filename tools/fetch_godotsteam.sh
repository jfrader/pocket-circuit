#!/usr/bin/env bash
# Installs the pinned GodotSteam GDExtension into addons/godotsteam/ for the
# platforms the game ships (Linux x86_64, Windows x64). The addon is not
# committed; without it the game runs with Steam off.
set -euo pipefail
VERSION="4.22.1"
URL="https://codeberg.org/godotsteam/godotsteam/releases/download/v${VERSION}-gde/godotsteam-${VERSION}-gdextension-plugin-4.4.zip"
SHA256="2b12b3499434c50da16104a0d22b725aee15cc5cd41223c1cea825bae59bfa8f"
KEEP=(godotsteam.gdextension license.md linux64 win64)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/addons/godotsteam"
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

curl -fsSL -o "$WORK/plugin.zip" "$URL"
printf '%s  %s\n' "$SHA256" "$WORK/plugin.zip" | sha256sum --check --quiet
unzip -q "$WORK/plugin.zip" -d "$WORK/plugin"
rm -rf -- "$DEST"
mkdir -p "$DEST"
for entry in "${KEEP[@]}"; do
	cp -R -- "$WORK/plugin/addons/godotsteam/$entry" "$DEST/"
done
printf 'GodotSteam %s installed in %s\n' "$VERSION" "$DEST"

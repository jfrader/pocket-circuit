# Gamestruments

Runtime music is the merged Gamestruments library (Rust GDExtension), pinned at
14944e69818e8fd6203f690f3267d86b2a9a7310 (PR #1).

The release build is now shipped in the repo (no longer gitignored):

- `addons/gamestruments/bin/libgamestruments_godot.so`
  SHA256: 88ce94eb3d0a6453faf1cceb8b49969cef5ea3ceb2bbb6d6fedb8db77023de12
- `addons/gamestruments/gamestruments.gdextension` (linux.* -> res:// path)

`AudioDirector` uses `GamestrumentsPlayer` when the class is loaded from the
GDExtension, otherwise it falls back to the WAV loops so tests stay green.

## Bumping the pin

When advancing the Gamestruments pin (new SHA in gamestruments repo):

1. In the Gamestruments checkout at the target commit:
   ```bash
   cargo build -p gamestruments-godot --release
   ```
2. In this repo (or with env var):
   ```bash
   GAMESTRUMENTS_ROOT=/path/to/gamestruments ./tools/sync_gamestruments.sh
   ```
3. Update this README with the new commit SHA (short 14944e6) and the fresh
   binary SHA256 from the script output.
4. Commit the updated .so + .gdextension + README + sync script.
5. Re-run headless import + tests to verify.

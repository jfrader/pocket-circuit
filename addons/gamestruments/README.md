# Gamestruments

Runtime music is the merged Gamestruments library (Rust GDExtension), pinned at
d2e34742c8d92cb5f5417b43d7fe1049cbbc996c (PR #2, lab-voice parity).

The release build is now shipped in the repo (no longer gitignored):

- `addons/gamestruments/bin/libgamestruments_godot.so`
  SHA256: 92c7996ee6507defa8b5f592e84d63b5e785a039447be5b0c605ea8c119c0e91
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
3. Update this README with the new commit SHA (short d2e3474) and the fresh
   binary SHA256 from the script output.
4. Commit the updated .so + .gdextension + README + sync script.
5. Re-run headless import + tests to verify.

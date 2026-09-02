# Gamestruments (local)

Runtime music is a Rust GDExtension. It is not committed as a 100MB debug
`.so`. Sync it from the Gamestruments worktree:

```bash
./tools/sync_gamestruments.sh
```

Then restart the Godot editor. `AudioDirector` uses `GamestrumentsPlayer` when
the class exists, otherwise it falls back to the WAV loops so tests stay green.

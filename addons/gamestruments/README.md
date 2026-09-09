# Gamestruments (local)

Runtime music is a Rust GDExtension. It is not committed as a 100MB debug
`.so`. Sync it from the Gamestruments worktree:

```bash
./tools/sync_gamestruments.sh
```

Then restart the Godot editor. `AudioDirector` uses `GamestrumentsPlayer` when
the class exists. A clean checkout and the current release pipeline use the
packaged WAV music when this local extension is absent. The test verifies that
fallback explicitly; it does not report a successful native-extension test.

Shipping an extension-enabled variant additionally requires release libraries
and verification for both Linux and Windows. A local debug `.so` is not that
release artifact.

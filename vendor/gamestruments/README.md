# Gamestruments v1.1.0

The native libraries in this directory are the packaged release build of
Gamestruments v1.1.0, built from the `v1.1.0` tag (commit
`b5e79b2bf3acc3d77648e355a08d024ce021d167`) by the release workflow:

https://github.com/jfrader/gamestruments/actions/runs/36916839091

It adds, over 1.0.5-rc1, the engine's shared `LivePlayer` (the end-of-blend and
section-loop glitch fix), the Suspense match phases and Trance style, and the
documented quit-without-leak recipe. Pocket Circuit vendors it so its release
gate stays credential-free and can load the addon without a Gamestruments
source checkout.

Vendored binaries, taken from the release's Godot 4 kit archive
(`gamestruments-1.1.0-godot4.zip`, sha256
`c4c32368ca99faf49e9b83f5da7f63214564037b545c49e47c5177043ac9b78d`):

- Linux x86_64 `bin/libgamestruments_godot.so` — sha256
  `af0ef6c9f8015242466528e4512b995f90ab63989da6b72ce29baa7c41979716`
- Windows x86_64 `bin/gamestruments_godot.dll` — sha256
  `5c76eb949df8e28b6552f586e916f0d09018242a51074bfd7d4c390d6dac6da8`

The kit's `gamestruments.gdextension` and `LICENSE.md` are byte-identical to
the previous pin and unchanged.

Replace this vendored copy with a credentialed release fetch when a suitable
credential exists. Use a fine-grained GitHub PAT with `Contents: read` access
to `jfrader/gamestruments`.

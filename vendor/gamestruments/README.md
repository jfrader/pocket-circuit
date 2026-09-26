# Gamestruments v1.0.5-rc1 (release candidate)

The native libraries in this directory are the packaged release-candidate build
of Gamestruments v1.0.5-rc1 (generator `1.11.0`), built from `main` at commit
`0f9ce7afb8e7ff1c82f9a0b10aab5e5441ef6bf2` by the Gamestruments release
workflow:

https://github.com/jfrader/gamestruments/actions/runs/36264857992

This is a release candidate, not a published or tagged release. It carries the
re-voiced garage intro and Ignition build, the seed-change and section-cue
crossfade holds, and the state-change supersede fix. Pocket Circuit vendors it
so its release gate stays credential-free and can load the addon without a
Gamestruments source checkout.

Vendored binaries, taken from the workflow's native Linux and Windows
artifacts:

- Linux x86_64 `bin/libgamestruments_godot.so` — sha256
  `2c5aa76fffebc891870e41ed423e63ba37373d869b435728ce9127b3e7844636`
- Windows x86_64 `bin/gamestruments_godot.dll` — sha256
  `9414e2cedb22c8b58619e9dba4d12ed34ad20a5b749fb03b873eba8b519c4ac5`

The candidate Godot 4 kit archive
(`gamestruments-1.0.5-rc1-godot4.zip`, sha256
`62ceb1818577b1e7056fb9ca570d9760d78f0a6a47c6d6077ca150a34f2263de`) supplies the
`gamestruments.gdextension` and `LICENSE.md` committed beside these libraries;
both are byte-identical to the previous pin and unchanged.

Replace this vendored copy with a credentialed release fetch when a suitable
credential exists. Use a fine-grained GitHub PAT with `Contents: read` access
to `jfrader/gamestruments`.

# Gamestruments v1.0.5-rc1 (release candidate)

The native libraries in this directory are the packaged release-candidate build
of Gamestruments v1.0.5-rc1 (generator `1.11.0`), built for Gamestruments PR #93
at commit `8a320a054bef51dec83d31cf1e35dc84dacbe64b` by the release workflow:

https://github.com/jfrader/gamestruments/actions/runs/36280187796

This is a release candidate, not a published or tagged release. It carries the
re-voiced garage intro and Ignition build, the seed-change and section-cue
crossfade holds, the state-change supersede fix, and atomic
`generate(seed, opening_section)` handoffs. Pocket Circuit vendors it so its
release gate stays credential-free and can load the addon without a Gamestruments
source checkout.

Vendored binaries, taken from the workflow's native Linux and Windows
artifacts:

- Linux x86_64 `bin/libgamestruments_godot.so` — sha256
  `6596200dd2342579d44f0540c56adfab3cb9925fdc6a19ca15c50a8c3397de85`
- Windows x86_64 `bin/gamestruments_godot.dll` — sha256
  `7777ea7d808719e3152316848d98a167263774d12d0ab031d0488494d9158a9c`

The candidate Godot 4 kit archive
(`gamestruments-1.0.5-rc1-godot4.zip`, sha256
`62ceb1818577b1e7056fb9ca570d9760d78f0a6a47c6d6077ca150a34f2263de`) supplies the
`gamestruments.gdextension` and `LICENSE.md` committed beside these libraries;
both are byte-identical to the previous pin and unchanged.

Replace this vendored copy with a credentialed release fetch when a suitable
credential exists. Use a fine-grained GitHub PAT with `Contents: read` access
to `jfrader/gamestruments`.

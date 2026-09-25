# Gamestruments v1.0.4

The native libraries in this directory are the packaged release build of the
Gamestruments v1.0.4 crate built from `main` (commit `54ea745`), including the
engine-owned score handoff and the section-cue percussion crossfade. Pocket
Circuit vendors them so its release gate stays credential-free and can load the
addon without a Gamestruments source checkout.

Replace this vendored copy with a credentialed release fetch when a suitable
credential exists. Use a fine-grained GitHub PAT with `Contents: read` access
to `jfrader/gamestruments`.

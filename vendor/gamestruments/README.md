# Gamestruments v1.0.4

The native libraries in this directory are the packaged release build of the
Gamestruments v1.0.4 crate built from `main` (commit `c1ea1ca`), including the
engine-owned score handoff, the section-cue percussion crossfade, the
hold-until-the-incoming-matches handoff (GURI-1217), and the garage/ignition
re-voice (GURI-1240). Pocket Circuit vendors them so its release gate stays
credential-free and can load the addon without a Gamestruments source checkout.

The Linux `libgamestruments_godot.so` was rebuilt locally from `c1ea1ca`
(sha256 `60f04c5868144abb2edafbf497fa5ab49a03afca29ffd90c9938909f076febf7`).
The Windows `gamestruments_godot.dll` is still the previous packaged build; it
needs the Gamestruments release workflow (which builds the MSVC DLL) to be
re-run and fetched before a Windows release.

Replace this vendored copy with a credentialed release fetch when a suitable
credential exists. Use a fine-grained GitHub PAT with `Contents: read` access
to `jfrader/gamestruments`.

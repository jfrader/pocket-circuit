# Pocket Circuit audio sources

Music and sound effects are generated at runtime by the first-party
Gamestruments engine; the game ships no recorded music. `engine_loop.ogg` in
this directory is the original project asset used for the local-player engine
note, synthesized from mathematical waveforms and deterministic noise.

Review renders of effects and engine voices are produced by
`tools/render_sfx_audio.gd` and `tools/render_engine_audio.gd` into a temporary
directory for listening only; they are not shipped.

The one-shot review effects are edited from Kenney Interface Sounds 1.0, Impact
Sounds 1.0, and Sci-Fi Sounds 1.0. Those packs are released under Creative
Commons Zero (CC0). The preserved source notices are in
`LICENSE-KENNEY-CC0.txt`; exact file-level provenance is in
`ASSET_PROVENANCE.md`.

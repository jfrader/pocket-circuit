# Pocket Circuit audio sources

Music, engine voices and sound effects are generated at runtime by first-party
project code and the Gamestruments engine; the game ships no recorded music.
The only recorded audio shipped is `engine_loop.ogg`, a fallback edited from
Kenney Sci-Fi Sounds 1.0's `engineCircular_000.ogg` (CC0), resampled to 48 kHz
mono OGG Vorbis.

Review renders of effects and engine voices are produced by
`tools/render_sfx_audio.gd` and `tools/render_engine_audio.gd` into a temporary
directory for listening only; they are not shipped.

Kenney Sci-Fi Sounds is released under Creative Commons Zero (CC0). The
preserved source notice is in
`LICENSE-KENNEY-CC0.txt`; exact file-level provenance is in
`ASSET_PROVENANCE.md`.

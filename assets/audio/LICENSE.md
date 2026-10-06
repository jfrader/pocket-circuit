# Pocket Circuit audio sources

Every shipped sound is generated at runtime by first-party project code and the
Gamestruments engine: music scores, engine voices, engine loops and all sound
effects. No recorded or third-party audio material is distributed with the game.

Review renders of effects and engine voices are produced by
`tools/render_sfx_audio.gd` and `tools/render_engine_audio.gd` into a temporary
directory for listening only; they are not shipped.

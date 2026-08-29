# Pocket Circuit Asset Provenance

This document covers the content shipped in Pocket Circuit 1.0.0. It records
production methods for release review and the Steam pre-generated-content
disclosure. It is not a substitute for `THIRD_PARTY_NOTICES.md`.

## Ownership and source material

Pocket Circuit's story, characters, vehicles, tracks, user interface, graphics,
music, and branding are original project material produced for Gurisitos Games.
The current review build also contains edited CC0 sound effects from Kenney.
It contains no third-party source images, characters, vehicle or track designs,
logos, branding, or borrowed melodies.

The deterministic portrait and car generators are adapted from the first-party
Gurisitos Games Procedural 2D project at revision
`f8eb03805f3fcc30fec56553033ad01988ef7857`. The vendored source, catalogs,
local compatibility edits, and MIT terms are shipped with the game.

Third-party material is limited to Godot Engine and the Kenney CC0 review
effects documented below. Notices are reproduced in `THIRD_PARTY_NOTICES.md`.
The game uses Godot's built-in default font and does not bundle a separately
licensed commercial font.

## Shipped asset groups

| Paths or content | Production method | Release status |
|---|---|---|
| `assets/models/**/*.png`, `assets/textures/**/*.png`, `assets/ui/**/*.png`, `assets/vfx/**/*.png` | Developer-directed, AI-assisted original graphic generation followed by project-specific selection, conversion, sizing, composition, and revision. Designs are fictional and use no third-party source media. | Cleared for this release |
| `assets/textures/imagine/*.png`, `assets/ui/imagine/*.png` | Grok Imagine 2.0, developer-directed prompts, magenta chroma-key to PNG alpha where needed. Original logo, menu art, HUD plates, track/counter tiles, and toy-scale kitchen/workshop/office sprites. No third-party characters or brands. | Review selection; mix/scale approval pending |
| `assets/branding/pocket_circuit_icon.svg` | Original project vector artwork assembled from simple geometric shapes and the game's palette. | Cleared for this release |
| `assets/audio/*.wav` | Synthesized locally from mathematical waveforms and deterministic noise by `tools/generate_audio.gd`; no samples, recordings, or borrowed melodies. Menu and race loops remain temporary pending the project composer's final cues. | Review only |
| `assets/audio/engine_loop.ogg`, `countdown.ogg`, `go.ogg`, `ui_move.ogg`, `ui_confirm.ogg`, `drift.ogg`, `boost.ogg`, `impact.ogg`, `hazard_warning.ogg` | Edited from Kenney Interface Sounds 1.0, Impact Sounds 1.0, and Sci-Fi Sounds 1.0, all CC0. Resampled to 48 kHz mono OGG Vorbis; restrained gain/fades were applied. Exact mappings appear below. | Provisional review selection; license cleared, mix approval pending |
| Kitchen, Workshop, and Office track variants not represented by image files | Original runtime presentation drawn by project GDScript with Godot primitives, project-authored text, and the Pocket Circuit palette. | Cleared for this release |
| Championship driver portraits and machine sprites in `scripts/vendor/procedural_2d/`, `data/vendor/procedural_2d/`, and `scripts/presentation/procedural_identity_library.gd` | Deterministic local pixel rendering from explicit Pocket Circuit cast and vehicle mappings. Adapted from the first-party Procedural 2D project at the pinned revision above; no source images, network service, player prompt, or third-party design is used. | Cleared for this release |
| Route boards and supporting garage presentation in `scripts/ui/app_shell_stage.gd` | Original runtime vector illustration drawn from project-authored geometric primitives and Pocket Circuit data. | Cleared for this release |
| Story, dialogue, event names, vehicle names, rules, and interface copy | Developer-directed, AI-assisted original writing and implementation, edited for this game. | Cleared for this release |

Unused original prototype images under `assets/models/` and `assets/textures/`
follow the same pre-generated graphic workflow. They are retained as project
resources and make no third-party rights claim.

## Kenney review-audio mappings

Verified and accessed 2026-08-28. Pack archive hashes are Interface Sounds
`f2193d072726d6758a5f7871b2dcc54dcce0d5c35c6f0a62f92549b327c81232`,
Impact Sounds `029d734af1582474edf3a694d1b0cebc97c1c152f2f39fa34d4c2bafc5de77f8`,
and Sci-Fi Sounds `119340f351a5098ad814f78719438c0da355a9ce8a4c8a3af6a8d48aa3d49e04`.

| Final path | Pack and source file | Transformation |
|---|---|---|
| `assets/audio/engine_loop.ogg` | Sci-Fi Sounds, `engineCircular_000.ogg` | 48 kHz mono, -1 dB, Vorbis q5, full 5 s loop |
| `assets/audio/countdown.ogg` | Interface Sounds, `select_003.ogg` | 48 kHz mono, -1 dB, Vorbis q5 |
| `assets/audio/go.ogg` | Interface Sounds, `confirmation_003.ogg` | 48 kHz mono, -1 dB, Vorbis q5 |
| `assets/audio/ui_move.ogg` | Interface Sounds, `tick_004.ogg` | 48 kHz mono, -1 dB, Vorbis q5 |
| `assets/audio/ui_confirm.ogg` | Interface Sounds, `confirmation_001.ogg` | 48 kHz mono, -1 dB, Vorbis q5 |
| `assets/audio/drift.ogg` | Interface Sounds, `scratch_004.ogg` | 48 kHz mono, -1 dB, Vorbis q5 |
| `assets/audio/boost.ogg` | Sci-Fi Sounds, `thrusterFire_000.ogg` | First 0.85 s, 5 ms fade-in, 150 ms fade-out, 48 kHz mono, -1 dB, Vorbis q5 |
| `assets/audio/impact.ogg` | Impact Sounds, `impactTin_medium_000.ogg` + `impactGeneric_light_000.ogg` | 0.55/0.35 gain mix, body delayed 12 ms, 45 ms fade-out, 48 kHz mono, Vorbis q5 |
| `assets/audio/hazard_warning.ogg` | Interface Sounds, `error_003.ogg` | Stereo downmix, 48 kHz mono, -6 dB, Vorbis q5 |

Source pages: https://kenney.nl/assets/interface-sounds,
https://kenney.nl/assets/impact-sounds, and
https://kenney.nl/assets/sci-fi-sounds.

## Steam AI-content disclosure draft

Pocket Circuit contains pre-generated AI-assisted content. AI-assisted tools
supported developer-directed creation of original code, writing, 2D graphics,
and sound integration. All included output was selected, edited, integrated,
and reviewed by the developer. The review build uses licensed CC0 Kenney sound
effects documented above; no third-party characters, brands, vehicle designs,
track designs, or borrowed melodies were used.

The game has no live generative-AI features. It does not send player input or
gameplay data to an AI service. Fixed local GDScript deterministically renders
the assigned cast portraits and machine sprites at startup, without AI or a
network dependency.

The publisher must review this wording against the final uploaded build and
submit the disclosure in Steamworks before store review.

## Release rule

Any newly introduced asset must have its source, production method, commercial
rights, and required attribution verified here before it can enter a release
export. Third-party material also requires a matching entry and complete license
text in `THIRD_PARTY_NOTICES.md`.

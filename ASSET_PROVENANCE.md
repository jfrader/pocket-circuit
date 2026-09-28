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
`9fc832c9638471739a61aeac1e84fe44408212f5`. The vendored source, catalogs,
local compatibility edits, and MIT terms are shipped with the game.

Third-party material is limited to Godot Engine and the Kenney CC0 review
effects documented below. Notices are reproduced in `THIRD_PARTY_NOTICES.md`.
The game uses Godot's built-in default font and does not bundle a separately
licensed commercial font.

## Shipped asset groups

Specific rows take precedence over catch-all groups; pending assets are not release-cleared by a broader row.

The explicit output paths in `data/world_prop_art.json` supersede older
environment group provenance below. Its 151 contracts cover 223 prepared
outputs, including props, decals, materials and utility masks, for GURI-1262
(Unify track artwork and realistic household prop scale).

The active painted sources were generated with operator-authorized, text-only
xAI Grok Imagine (`grok-imagine-image-2.0`). They are original household artwork,
not third-party images or adaptations of protected designs. Source sheets live
in `assets/source/environment-v2/`; the approved pilot sources live in
`assets/source/environment-pilot/`. Both directories remain excluded from
exports. Approved pilot outputs are reused where they depict the same
object; remaining prop and decal cells use the new production sheets. The
manifest identifies every source cell, crop or prepared-source reuse.

`tools/prepare_environment_library.py` uses Pillow, NumPy and SciPy for chroma
removal, disconnected artifact cleanup, key-color unmixing, edge cleanup,
transparent 512px normalization and measurement of visible physical bounds.
It does not apply the rejected cel quantization or uniform black contour.
Front-facing mug and lamp attempts and a scratch drawn as a wooden slab were
replaced by `repair-overhead-01.jpg`; only the corrected cells are used. Raw
sheets can contain rejected cells that are not referenced by the manifest.

Room materials combine new painted grain sources with original local shader
patterns. The material seed controls structural profile, spacing, orientation,
phase, seams, grain and palette-compatible choices independently of geometry.
The game makes no runtime AI requests. Utility shadows, the checker and skid
mask are generated locally by the preparation tool.

Handmade course materials reuse these painted grain sources with original local
shader treatment and Godot's built-in FastNoiseLite, baked into ImageTexture
grain. Card
grain, cut edges, contact shadows and taped joins are procedural; no additional
generated image sheets or third-party source artwork are used for the course.

The operator approved the native production result, including the multi-seed
material comparisons, for closeout. This approval covers the environment
direction and integration, not publication of a release. Cars, portraits and
HUD artwork are unchanged.

| Paths or content | Production method | Release status |
|---|---|---|
| `data/world_prop_art.json` output paths | Original text-only Grok Imagine 2.0 sources and explicit approved pilot-source reuse, prepared by `tools/prepare_environment_library.py`. The manifest declares theme, overhead style, role, dimensions, zones, clearances, repetition, collision and shadow behavior. | Native environment result approved; publication not performed |
| `assets/textures/world_materials/*.png` | New painted grain sources from the approved pilot, prepared as wrap-continuous tiles. `data/household_material_patterns.json` and `household_surface.gdshader` generate the distinct room patterns and seeded variations locally. | Native environment result approved |
| `assets/textures/kitchen_hero/*.png`, `assets/textures/workshop_hero/*.png`, `assets/textures/office_hero/*.png` | Fresh overhead source cells and approved-source reuse identified per output in the manifest. No rejected front-facing alternatives or old cel filtering are used. | Native environment result approved |
| `assets/ui/imagine/motorsport_panel_dark.png`, `motorsport_panel_paper.png` | 96×64 nine-slice derivatives of the existing Imagine telemetry and number-plate sources, assembled with Pillow using fixed 12px corners/edges and clean center strips. The paper panel mirrors its clean right edge to remove the baked checker strip; Godot draws fixed-size checker marks. No new generation or external source material. | Integrated UI-polish candidate; operator review pending |
| `assets/ui/imagine/motorsport_loading.jpg` | xAI `grok-imagine-image-quality`, developer-directed text-only prompt for an original miniature pit-lane workbench illustration. No source images, brands or embedded UI text. Godot draws the actual loading stages and Back control over the image. | Integrated candidate; runtime/operator review pending |
| `assets/ui/imagine/motorsport_title.jpg`, `motorsport_garage.jpg`, `motorsport_telemetry_plate.jpg`, `motorsport_number_plate.jpg` and `.png` | xAI `grok-imagine-image-quality`, developer-directed text-only prompts following the approved GURI-636 workbench concepts. Production images contain no interface lettering: Godot renders text and interactive controls. The number plate PNG is a 1168×386 crop at (40, 240) of the 1248×832 source JPEG; other images are used as full rectangles. Garage cars are rendered by the existing first-party Procedural 2D identity library, not generated replacements. | Integrated candidate; exact-build operator review pending |
| `assets/textures/ground_dressing/*.png`, `track_boundary/*.png`, `giant_props/*.png`, `grip_patches/*.png` | Regenerated painted overhead cloth, paper, utensils, tools, appliances and ground marks from the manifest's new Imagine sources. Alpha footprints govern physical sizing; local code supplies collision, placement and contact shadows. | Native environment result approved |
| `assets/textures/edge_dressing/*.png` | Manifest-listed painted micro objects and decals from the new sources; grain aliases use the new material sources. White-alpha shadow utilities are generated locally with Pillow and tinted at runtime. | Native environment result approved |
| Other `assets/models/**/*.png`, `assets/textures/**/*.png`, `assets/ui/**/*.png`, and `assets/vfx/**/*.png` | Developer-directed, AI-assisted original graphic generation followed by project-specific selection, conversion, sizing, composition, and revision. Designs are fictional and use no third-party source media. | Cleared for this release |
| Legacy `assets/textures/imagine/*.png`, `assets/ui/imagine/*.png` not covered above | Mixed provenance: developer-directed Grok artwork and original SVG outputs from `tools/gen_prop_assets.gd` / `gen_prop_assets2.gd` share these folders. Folder naming alone does not identify generation method. | Per-file source and mix/scale audit remains pending |
| `assets/branding/pocket_circuit_icon.svg` | Original project vector artwork assembled from simple geometric shapes and the game's palette. | Cleared for this release |
| `assets/audio/*.wav` | Synthesized locally from mathematical waveforms and deterministic noise by `tools/generate_audio.gd`; no samples, recordings, or borrowed melodies. Menu music follows the first-party Gamestruments Tiny Torque `level-004` Grid catalog take and race music its Cruise take (`data/music/tiny_torque_level_004.score.json`). Music loops are mastered by `tools/audio_mastering.gd` to a -14 LUFS target with a -1 dBTP ceiling. | Cleared for this release |
| `assets/audio/engine_loop.ogg` | Edited from Kenney Sci-Fi Sounds 1.0, `engineCircular_000.ogg` (CC0). Resampled to 48 kHz mono OGG Vorbis. This is the engine's fallback only; the engine voice and every sound effect are generated by project code. | Provisional review selection; license cleared, mix approval pending |
| Kitchen, Workshop, and Office track variants not represented by image files | Original runtime presentation drawn by project GDScript with Godot primitives, project-authored text, and the Pocket Circuit palette, including the raised island side-face/top-lip construction and invisible corridor checkpoint sensors. | Cleared for this release |
| Championship driver portraits and machine sprites in `scripts/vendor/procedural_2d/`, `data/vendor/procedural_2d/`, and `scripts/presentation/procedural_identity_library.gd` | Deterministic local pixel rendering from explicit Pocket Circuit cast and vehicle mappings. Adapted from the first-party Procedural 2D project at the pinned revision above; no source images, network service, player prompt, or third-party design is used. | Cleared for this release |
| Route boards and supporting garage presentation in `scripts/ui/app_shell_stage.gd` | Original runtime vector illustration drawn from project-authored geometric primitives and Pocket Circuit data. | Cleared for this release |
| Story, dialogue, event names, vehicle names, rules, and interface copy | Developer-directed, AI-assisted original writing and implementation, edited for this game. | Cleared for this release |

Unused original prototype images under `assets/models/` and `assets/textures/`
follow the same pre-generated graphic workflow. They are retained as project
resources and make no third-party rights claim.

## Design-review concepts (not approved release assets)

`assets/ui/concepts/title-concept.jpg`, `garage-concept.jpg`, and
`hud-concept.jpg` were generated with xAI `grok-imagine-image-quality` from
developer-directed text prompts for GURI-636. They propose an after-hours
miniature-motorsport tabletop title, garage selection, and compact race HUD.
No source images were provided. The concepts are attached to GURI-636 for
review; they are not implemented UI or evidence of actual gameplay.
Generated lettering, controls, car proportions, and track geometry are
illustrative and require replacement or reconciliation before integration.
Do not include these flattened mockups in a release package.

## Kenney review-audio mappings

Verified and accessed 2026-08-28. Pack archive hashes are Interface Sounds
`f2193d072726d6758a5f7871b2dcc54dcce0d5c35c6f0a62f92549b327c81232`,
Impact Sounds `029d734af1582474edf3a694d1b0cebc97c1c152f2f39fa34d4c2bafc5de77f8`,
and Sci-Fi Sounds `119340f351a5098ad814f78719438c0da355a9ce8a4c8a3af6a8d48aa3d49e04`.

| Final path | Pack and source file | Transformation |
|---|---|---|
| `assets/audio/engine_loop.ogg` | Sci-Fi Sounds, `engineCircular_000.ogg` | 48 kHz mono, -1 dB, Vorbis q5, full 5 s loop |

Source page: https://kenney.nl/assets/sci-fi-sounds.

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

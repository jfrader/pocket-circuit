# Pocket Circuit Asset Provenance

This document covers the content shipped in Pocket Circuit 1.0.0. It records
production methods for release review and the Steam pre-generated-content
disclosure. It is not a substitute for `THIRD_PARTY_NOTICES.md`.

## Ownership and source material

Pocket Circuit's story, characters, vehicles, tracks, user interface, graphics,
music, sound effects, and branding are original project material produced for
Gurisitos Games. The release contains no third-party source images, recordings,
samples, characters, vehicle or track designs, logos, or branding.

The deterministic portrait and car generators are adapted from the first-party
Gurisitos Games Procedural 2D project at revision
`cb4ae73df94b60590b7dea95f09a7209775be9e1`. The vendored source, catalogs,
local compatibility edits, and MIT terms are shipped with the game.

The only third-party software included with the release is Godot Engine. Its MIT
license is reproduced in `THIRD_PARTY_NOTICES.md`. The game uses Godot's built-in
default font and does not bundle a separately licensed commercial font.

## Shipped asset groups

| Paths or content | Production method | Release status |
|---|---|---|
| `assets/models/**/*.png`, `assets/textures/**/*.png`, `assets/ui/**/*.png`, `assets/vfx/**/*.png` | Developer-directed, AI-assisted original graphic generation followed by project-specific selection, conversion, sizing, composition, and revision. Designs are fictional and use no third-party source media. | Cleared for this release |
| `assets/branding/pocket_circuit_icon.svg` | Original project vector artwork assembled from simple geometric shapes and the game's palette. | Cleared for this release |
| `assets/audio/*.wav` | Synthesized locally from mathematical waveforms and deterministic noise by `tools/generate_audio.gd`; no samples, recordings, or borrowed melodies. | Cleared for this release |
| Kitchen, Workshop, and Office track variants not represented by image files | Original runtime presentation drawn by project GDScript with Godot primitives, project-authored text, and the Pocket Circuit palette. | Cleared for this release |
| Championship driver portraits and machine sprites in `scripts/vendor/procedural_2d/`, `data/vendor/procedural_2d/`, and `scripts/presentation/procedural_identity_library.gd` | Deterministic local pixel rendering from explicit Pocket Circuit cast and vehicle mappings. Adapted from the first-party Procedural 2D project at the pinned revision above; no source images, network service, player prompt, or third-party design is used. | Cleared for this release |
| Route boards and supporting garage presentation in `scripts/ui/app_shell_stage.gd` | Original runtime vector illustration drawn from project-authored geometric primitives and Pocket Circuit data. | Cleared for this release |
| Story, dialogue, event names, vehicle names, rules, and interface copy | Developer-directed, AI-assisted original writing and implementation, edited for this game. | Cleared for this release |

Unused original prototype images under `assets/models/` and `assets/textures/`
follow the same pre-generated graphic workflow. They are retained as project
resources and make no third-party rights claim.

## Steam AI-content disclosure draft

Pocket Circuit contains pre-generated AI-assisted content. AI-assisted tools
supported developer-directed creation of original code, writing, 2D graphics,
and synthesized sound design. All included output was selected, edited,
integrated, and reviewed by the developer. No third-party source media, samples,
characters, brands, vehicle designs, or track designs were used.

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

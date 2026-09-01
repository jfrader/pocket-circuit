# Procedural Track System - Constraints and Conventions

Standing reference for anyone changing generated circuits, room canvases,
household story kits, surfaces, collision, or racing-line AI. These contracts
are load-bearing and must be reverified after changes. History belongs in the
changelog, not here.

## Architecture

```text
tools/track_seed_gen.gd          requested seed + room -> deterministic route
tools/track_builder_core.gd      route + story kit -> runtime PackedScene
tools/build_procedural_track.gd  optional CLI for saved development snapshots
scripts/race/prototype_race.gd   builds the requested circuit at race startup
```

- Generated races do not depend on a baked circuit roster or prebuilt scene
  pool. Quick Race and championship events build arbitrary seeds live through
  `TrackBuilderCore.build_packed`.
- The three authored track scenes remain regression fixtures for their themed
  collision and AI smoke tests. They are not a whitelist for generated play.
- The builder is runtime-safe and headless-safe. It does not depend on the
  editor or the active SceneTree.

## Seed Identity

- `TrackSeedGen.generate_with_retries` keeps its historical name, but it never
  walks to another seed. The requested seed is player-facing identity and is
  immutable.
- Family, target length, route variation, story kit, opening landmark, and room
  canvas use independent deterministic streams. Changing the room must not
  silently change a seed's selected family.
- A seed gets up to 12 rhythm variants of its selected family. If those do not
  fit, four deterministic technical-perimeter variants are attempted under the
  same seed and family metadata.
- Generated roots retain `requested_seed`, `family`, `realization`,
  `generation_attempt`, `generation_fallback`, `story_id`, `loop_length`,
  `theme`, and `room_shape` metadata.

## Route Geometry

- Route families are `speed_loop`, `kidney`, `dogbone`, `broad_triangle`,
  `offset_s`, and `deep_notch`.
- Family templates are normalized closed silhouettes. They are mirrored,
  oriented for the room, deformed with seed-driven harmonic lobes and localized
  chicanes, fitted, clearance-aware length-scaled, sampled into 24 controls,
  then exposed as a 260-point centerline.
- Retry attempts vary deformation phase and strength rather than only shrinking
  one silhouette. Wide and long rooms use stronger turn rhythm so their routes
  retain changing-radius character instead of becoming stretched ovals.
- The target-length stream spans roughly 2,500 to 5,500 units. A room may cap
  the realized length when its physical canvas cannot fit the target safely.
- Corridor half-width is 125 units. Validation reserves the complete 250-unit
  corridor plus wall clearance, rejects centerline self-intersections, enforces
  nonlocal self-distance, and keeps the route inside the room polygon.
- L-shaped rooms use the dedicated `el_safe` realization. The route must occupy
  both the upper-left arm and the right/lower extension while retaining the
  seed-selected family metadata.
- No figure-eight or self-crossing routes: checkpoint order and reverse racing
  require one simple closed loop.

## Room Canvases

| Key | Canvas |
|---|---|
| `classic` | 1750 x 1150 rectangle |
| `wide` | 2350 x 1200 rectangle |
| `tall` | 1150 x 1450 rectangle |
| `long` | 2600 x 1100 rectangle |
| `square` | 1500 x 1500 rectangle |
| `el` | 2400 x 1400 L-shaped polygon |

`App.circuit_room_for_seed` selects among all six with a mixed deterministic
stream independent from family and target length.

## Household Stories

- `STORY_KITS` is the source of truth for generated dressing. Kitchen,
  Workshop, and Office each provide four coherent stories.
- Semantic quantities are literal: `unique` is exactly 1, `few` is 2-3, and
  `many` is 8-20. A unique asset cannot repeat between the island, opening, and
  corner landmarks in the same track.
- Story dressing is concentrated into authored moments: one island focal
  cluster, one object line, one sparse delimiter, one or two corner landmarks,
  and one iconic opening landmark.
- Ambient room dressing uses 4-6 deterministic safe pockets of three props
  across distinct sectors. Each pocket is a semantic `few`, and the 12-18 prop
  room-level aggregate remains a semantic `many` without becoming uniform
  noise. Story assets marked `unique` are reserved before ambient placement.
- Ground sections add 2-4 broad, theme-specific cloth, paper, cardboard, or
  desk-pad anchors across distinct room sectors. They are non-colliding
  `Sprite2D` presentation and never become gameplay surfaces or barriers.
- Floor details add 12-20 non-colliding themed decals to large blank areas.
  Ambient props, ground sections, and decals stay inside the room and outside
  the protected route corridor.
- Asset dimensions and collider shapes come from `PROP_SHAPES`. Generated
  story props must use transparent PNG textures, never opaque JPG rectangles.
- Trackside placement must remain clear of checkpoint recovery corridors:
  230 units along the route and 48 units across it, plus the prop radius.

## Track Moments

Generated tracks implement the design contract in `game-design-spec.md` section
11 as playable geometry and mechanics:

- `OpeningLandmark`: one household focal prop near the opening sector.
- `EarlyConflictForward` and `EarlyConflictReverse`: a telegraphed moving
  hazard crossing the corridor 12-25% into the lap in either direction.
- `TechnicalSurfaceMoment`: a full-width low-grip or low-speed zone on a
  separated high-turn section.
- `ShortcutDecision`: a visibly decaled inside lane that is geometrically
  shorter and at least 1.06x faster, but has lower grip. The outer lane remains
  longer and safe for every vehicle build.
- `SpeedSection`: the unobstructed start/finish straight.
- `DramaticFinish`: clear forward and reverse run-ups ending at the full-width
  checker gate.

`generated_moment_indices`, `generated_hazard_paths`, and
`generated_surfaces` expose these contracts for runtime presentation and tests.
The generated racing line deliberately takes the safe outer lane through the
shortcut window; the shortcut remains a player choice rather than an AI trap.

## Visual and Collision Language

- No white edge lines, dashed centerlines, kerbs, painted route borders, or
  translucent gameplay-zone overlays. Household objects and material changes
  communicate the course. The checker is the only painted race marking.
- Generated routes use the themed `TrackSurface` directly and must not add the
  old `TrackRibbon`, whose triangulation produced artifacts in concave routes.
- Surface gameplay polygons remain visually transparent. Their themed decals
  show the technical section and risky shortcut lane.
- Full-window themed backdrops scale and tile to the selected room bounds so
  wider canvases do not expose black camera voids.
- Generated and authored inner barriers use closed `ConcavePolygonShape2D`
  segment chains on a `StaticBody2D`; do not send a concave island through
  convex polygon decomposition.
- Generated roots persist in the `track` group so runtime AI can discover the
  260-point `RacingLine`.
- Collision layers remain: vehicles 1, walls/island 2, player-only scenery 4,
  and AI-dodge scenery 16. The vehicle scene's base mask is 22 (`2 | 4 | 16`),
  and race setup also enables layer 1 so cars collide with one another.

## AI

- AI follows the invisible curvature-offset `RacingLine` with speed-dependent
  lookahead and curvature-limited speed.
- Reverse events traverse the same line in reverse through
  `RaceManager.is_reverse_direction`; never reverse only checkpoint order.
- Generated shortcut windows move the AI target to the safe outer lane with a
  tapered transition. This geometry is safe in both race directions.
- Current pace/corner constants are Sunday Drive 0.86/8.6, Club Circuit
  1.10/10.9, and Clockwork 1.14/11.6. Retune only with full forward and reverse
  harness coverage.
- Every AI vehicle must complete a legal lap with no more than three recoveries
  in `theme_ai_harness.gd`.

## Verification

Run after generator, builder, surface, collision, or AI changes:

1. `godot --headless --path . --script res://tests/track_seed_gen_test.gd`
2. `godot --headless --path . --script res://tests/generated_track_composition_test.gd`
3. `godot --headless --path . --script res://tests/generated_race_runtime_test.gd`
4. Representative family/room seeds through `tests/theme_ai_harness.gd` in
   both directions using `PC_THEME`, `PC_ROOM`, `PC_SEED`, and
   `PC_DIRECTION=both`.
5. `godot --headless --path . --script res://tests/ai_race_smoke_test.gd` for
   the three authored regression tracks.
6. A broad theme x room x seed construction stress matrix after geometry or
   composition changes.
7. Direct runtime captures for all six route families after visual changes.
8. `tools/build_release.sh <clean-output-directory>` for the authoritative
   import, complete test suite, scene smokes, native exports, packaged Linux
   smoke, and PCK inspection.

Keep `project.godot` release-clean with only the `App` autoload committed.

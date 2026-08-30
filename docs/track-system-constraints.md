# Procedural Track System — Constraints & Conventions

Standing reference for anyone adding tracks, rooms, props, textures, or AI
changes. All values below are load-bearing contracts discovered through
harness verification — do not change them without re-running the gates listed
in "Verification". History lives in the CHANGELOG, not here.

## Architecture

```
tools/track_seed_gen.gd        pure generator: seed → control-point loop
tools/track_builder_core.gd    runtime+headless builder: loop → full scene
tools/build_procedural_track.gd thin CLI (env-driven) that saves a .tscn
scenes/tracks/circuits/        baked roster (AI-validated pool)
```

- The generator is deterministic: `generate(seed, rect, params)` is pure.
  Invalid seeds are rejected and `generate_with_retries` walks to the next
  valid one (max 40). The "used" seed is reported and must be used for
  anything reproducible.
- The builder core is **runtime-safe** (no SceneTree/editor deps). The race
  loads a baked roster scene when it exists and builds the seed live
  otherwise (`TrackBuilderCore.build_packed`). Any seed must build at
  runtime.
- Generation parameters are per-archetype + per-room; the builder's
  `build_packed` owns the per-room overrides. Keep them together.

## Generator constraints (TrackSeedGen)

- Algorithm: random spread points → convex hull → displaced midpoints →
  angle clamp → point separation → bounds clamp + re-separation → arc-length
  resample (22 points) → post-resample angle clamp → validation.
- **Never use the hard bounds clamp without the re-separation passes** — it
  piles points on rect corners and folds the spline.
- Validation: min loop length per archetype, **max loop length** for the
  switchback (2300–2500), self-distance (corridor half-width 125 + margin),
  whole loop inside the room polygon with margin.
- Four archetypes (`posmod(seed, 4)`): fast (gentle 62°, long), technical
  (82°, busy), asymmetric (side bias), switchback (84° — **do not exceed
  ~84°; sharper turns fold the 125-wide corridor offset and the AI cannot
  hold the line**). No figure-8/self-crossings: gate ordering breaks in
  reverse.

## Room canvases (ROOM_SHAPES)

classic 1750×1150 · wide 2350×900 · tall 1150×1450 · long 2600×800 ·
square 1500×1500 · el (L-shape, loop lives in the left arm).
Per-room tuning in `build_packed` (self-distance, displacement scale, sample
rect, check margin) is mandatory for narrow/concave rooms. Rooms must stay
under ~2700×1500 so the QA wide capture (zoom 0.46) never shows void.

## Track visuals (the "seamless" language)

- **No painted delimitation anywhere**: no edge lines, no dashed centerline,
  no kerb blocks, no translucent zone overlays (surface-zone polygons are
  set to Color.TRANSPARENT but keep their gameplay grip/speed modifiers).
- The corridor = a subtle warm light tint (Color(1, 0.96, 0.88, ~0.17)) +
  theme wear-strip tiles at ~0.62–0.85 alpha. A distinct colored band was
  explicitly rejected; a dark tint is invisible on dark floors.
- Floor surfaces are full-bleed patterns per theme (gingham cloth, desk pad,
  wood planks). Track strips are darker theme variants of the floor.
- The checker start strip is the only allowed marking.
- The office canonical (`scenes/tracks/office_desk.tscn`) is a **frozen
  proven build**: do not regenerate it from the builder (its reverse
  direction is AI-marginal and only that bake passes reliably).

## Props

- Two asset scripts: `tools/gen_prop_assets.gd`, `tools/gen_prop_assets2.gd`
  (SVG → PNG via `Image.load_svg_from_buffer`, 256px SVG at 4×). All prop
  PNGs MUST have transparent backgrounds; floor/track tiles are the only
  opaque assets. **Never put JPGs (toolbox/keyboard photos) in prop pools** —
  they render as opaque rectangles.
- `PROP_SHAPES` is the single source of truth for each prop's real-world
  size (car ≈ 30u): rect entries (books, planks, rulers, tools) and circle
  entries. Sizes follow real ratios (basketball ≈ 100 ≈ 2.3× a mug 44,
  coin 12). Sprite scale and collider derive from this map — a prop must
  never render at its cell's size.
- Pools per theme: `island_fill_big/_textures/_small/_tiny`, `boundary_long`
  (straights: rulers/planks/cables, aligned to the tangent), `boundary_corner`
  (pots/plants — currently only placed ≥78u out; corner pots break the
  office reverse AI, kept out of the canonical), `corner_giants` (oversized
  set pieces at room corners), `decals`, `scatter_textures`.
- Collision layers: 1 vehicles, 2 track/walls/barrier (AI probe mask),
  layer 3 (value 4) player-collidable scenery the AI's probes ignore,
  layer 5 (value 16) **dodge layer** — the AI feels and swerves these but
  its racing-line probes don't read them as walls. Car masks: 22 (1|2|4|16).
- Island = one big real object (toolbox/keyboard/plate texture) + a curated
  fill: **one of each** big/medium item deep in the center (no 10-remotes),
  small/tiny near the edges, rim clearance 40u from the corridor so the AI's
  inside lines never graze props.

## AI (scripts/vehicle/ai_vehicle_controller.gd)

- Follows the baked `RacingLine` node (curvature-offset path, invisible)
  with speed-dependent lookahead; corner speeds from the turn radius
  (corner_constant × sqrt(radius), per difficulty). Falls back to
  gate-chasing when the line node is absent (the frozen office scene).
- Difficulty constants: sunday 0.86/8.6, club 1.10/10.9, clockwork
  1.14/11.6. Bumping club above ~1.12 or the corner constant above ~11.5
  has produced recovery flake in the harness.
- Constraints that must hold: all three cars complete legal laps forward and
  reverse with ≤2 stall-recoveries, on every track in the roster and on
  random runtime seeds sampled from the validated pool.

## Verification (run after any change here)

1. `PC_THEME=workshop|office|kitchen` `theme_ai_harness.gd` — 3/3 passes.
2. `ai_race_smoke_test.gd` — the office-reverse Milo flake is known (~30%);
   re-run to confirm a pass.
3. Full `tests/*_test.gd` suite.
4. Roster changes: rebuild scenes via the CLI, then re-run the harness per
   seed (parallel batches); prune seeds that fail twice.
5. Wide captures (`PC_SEED=… --write-movie`, gamma 0.5 / saturation 1.2) +
   a vision-agent review for any visual change.
6. Keep `project.godot` release-clean (only the App autoload).

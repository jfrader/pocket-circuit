# Procedural Track System - Constraints and Conventions

Standing reference for anyone changing generated circuits, room canvases,
household story kits, surfaces, collision, or racing-line AI. These contracts
are load-bearing and must be reverified after changes. History belongs in the
changelog, not here.

## Architecture

```text
scripts/race/track_seed_gen.gd          requested seed + room -> deterministic route
scripts/race/track_route_grammar.gd     seed-driven macro sections and dimensions
scripts/race/track_builder_core.gd      route + story kit -> runtime PackedScene
scripts/race/world_environment_catalog.gd  asset contract + semantic role pools
scripts/race/world_environment_plan.gd     pure seeded physical placement plan
scripts/race/world_environment_art.gd      yielded scene rendering
scripts/race/household_surface_materials.gd independent procedural material stream
scripts/race/handmade_course_materials.gd   seeded translucent paint, brushwork and edge markings
tools/build_procedural_track.gd  optional CLI for saved development snapshots
scripts/race/prototype_race.gd   builds the requested circuit at race startup
```

- Generated races do not depend on a baked circuit roster or prebuilt scene
  pool. Quick Race and championship events build arbitrary seeds live through
  staged `TrackBuilderCore.prepare_layout` / `assemble_runtime` preparation.
  `build_packed` remains the synchronous tooling and fixture API.
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
- A seed gets up to 12 composed route attempts. If those do not
  fit, four deterministic technical-perimeter variants are attempted under the
  same seed and family metadata.
- Generated roots retain `requested_seed`, `family`, `realization`,
  `generation_attempt`, `generation_fallback`, `story_id`, `loop_length`,
  `theme`, `room_shape`, `route_program`, `route_recipe`, and `route_sequence`
  metadata. `family` is stable seed identity; the program/recipe describe the
  actual accepted geometry.

## Route Geometry

- Route families are `speed_loop`, `kidney`, `dogbone`, `broad_triangle`,
  `offset_s`, and `deep_notch`.
- Perimeter, lobe and wedge programs compose seed-dependent straight extents,
  shoulders, waist/bay dimensions and optional sections. A seed-driven mirror
  flips handedness; most routes also insert a left/right chicane on a long
  straight so corners are not all the same way. Normalized shape-distance tests
  still discount translation, scale, rotation, mirroring and traversal direction,
  but raw turn mix must include both hands on a large fraction of seeds.
- Higher length rolls can select an explicitly identified `endurance` envelope
  with a broad inward section, preserving the long-route coverage without
  tightening corners. This is a separate realization, not evidence of greater
  within-program variety; the proposed sheet still requires operator review.
- Programs are fitted and rounded with world-space corner fillets, retaining
  literal collinear controls along straight portions (spacing at most 110 units).
  Control count is internal and variable, bounded below the 260-point public
  centerline size; callers must not assume 24 controls. Retry attempts may change the
  program/section combination, not just shrink the same failed shape.
- Generated route and room dimensions use `WORLD_SCALE = 1.75`. The target
  length stream spans roughly 4,375 to 9,625 world units; elongated room
  perimeters can realize longer loops when required by their silhouette.
  The length tiers (`GeneratedCircuitRules.LENGTH_TIERS`) are
  `compact` (4–6k, room_scale 0.95), `standard` (4,375–9,625, 1.0),
  `long` (12–16k, 1.8), `endurance` (18–24k, 2.8), and `marathon`
  (32–48k, 4.5).
- The `marathon` tier selects from a dedicated folded grammar
  (`TrackRouteGrammar.MARATHON_NAMES`: `double_switchback`, `deep_comb`)
  instead of the four standard programs, so the standard tiers' seed geometry
  is untouched. Marathon routes land 16–22 broad turn complexes (twice the
  standard bound below) at the same corridor width and corner rules.
  L-shaped rooms keep their dedicated `el_safe` route, which lands fewer
  complexes; a small number of wide/long seeds fall back to the technical
  perimeter when the folded shape cannot reach the 32k band floor.
- Corridor half-width is 125 units. Validation reserves the complete 250-unit
  nominal racing corridor for route fitting and prop placement, rejects
  centerline self-intersections, enforces nonlocal self-distance, and keeps the
  route inside the room polygon. That geometric corridor is not a collision
  tube: the surrounding room apron remains drivable.
- Minimum accepted centerline turn radius is 147 units: the 125-unit corridor
  half-width plus a 22-unit vehicle hull allowance. Geometry checks do not replace
  four-car physics verification on accepted routes.
- Every accepted route has at least two distinct 450-unit setup-straight
  regions whose segment headings stay within 0.04 radians (about 2.3 degrees),
  not merely gentle curves. Turn rhythm is limited to broad complexes rather than
  spline-scale wiggles, and validation rejects driveable chords that replace a
  complete complex.
- Individual routes retain a 1–10 broad-complex bound; the regression matrix
  average is at most 8. Marathon-tier routes are the deliberate exception:
  their folded programs land 16–22 complexes. Richer sections must remain
  separated by usable setup straights, not high-frequency spline wiggles.
- L-shaped rooms use the dedicated `el_safe` realization. The route must occupy
  both the upper-left arm and the right/lower extension while retaining the
  seed-selected family metadata.
- No figure-eight or self-crossing routes: checkpoint order and reverse racing
  require one simple closed loop.

## Room Canvases

| Key | Authored fixture | Generated canvas |
|---|---|---|
| `classic` | 1750 x 1150 | 3062.5 x 2012.5 |
| `wide` | 2350 x 1200 | 4112.5 x 2100 |
| `tall` | 1150 x 1450 | 2012.5 x 2537.5 |
| `long` | 2600 x 1100 | 4550 x 1925 |
| `square` | 1500 x 1500 | 2625 x 2625 |
| `el` | 2400 x 1400 L shape | 4200 x 2450 L shape |

`App.circuit_room_for_seed` selects among all six with a mixed deterministic
stream independent from family and target length. Generated room bounds drive
the runtime camera limits, while polygon-aware recovery preserves concave room
shapes with a 120-unit edge tolerance. Negative-seed authored snapshots retain
their original unscaled canvases.

## Household Stories

- `ROOM_COMPOSITIONS` (`STORY_KITS` alias) retains four semantic stories per
  theme and their gameplay surface choices. `WorldEnvironmentCatalog` combines
  these with the asset contract and `data/environment_composition.json` support
  families. A single `WorldEnvironmentPlan` replaces independent scatter passes.
- The planner selects one fitted focal, then supporting groups, restrained micro
  dressing, seeded boundary clusters and bounded ground/decal dressing. Role streams
  are seeded independently. Focal alternatives retain their real dimensions;
  a failed fit is not permission to shrink or stretch an object.
- Repetition is keyed by canonical asset id rather than output alias. The plan
  enforces the catalog budgets; visual gameplay-surface paint has its own bounded
  sampling. Flat ground can underlay objects but cannot straddle a solid rim.
- Gate footprints and sealed bay polygons are reserved before placement. Every
  planned environment object stays inside the room and outside the full 125-unit
  corridor plus its declared clearance. Solid footprints cannot overlap each other
  or on-course obstacles. The planner reserves an actual vehicle-width
  exit into the apron before placing scenery, plus an empty boundary sector.
- Procedural surface profiles live in `data/household_material_patterns.json`.
  Story families and curated palette identities constrain the independent material
  stream; profile, pattern layout, spacing, orientation, seams and grain vary
  without changing geometry. Floor and course share a world-coordinate substrate;
  independently seeded pigments and brushwork distinguish the intended route.
- Four floor and three island profiles are available per theme. Workshop timber
  and technical pads remain distinct from Office laminate/veneer and ink-blue,
  oxblood or indigo desk pads. Kitchen retains ceramics and preparation boards.
- The course adds a separate seed stream for paint pigments, brushwork and edge
  width. It does not perturb existing floor/island selections. Palette selection
  checks the composited paint, including minimum brush coverage and substrate
  modulation, at the least opaque configured setting that meets at least 1.5:1
  linear-luminance contrast against both neighbors' base/pattern color ranges.
  SDR and linear-color blends are checked separately;
  an unmatched custom palette chooses the strongest available contrast and exposes
  `contrast_safe=false` rather than silently claiming the target was met.
- Paint is explicitly `FLAT`, with no shadow, curb, tape or paper joins.
  Floor and paint shaders use `household_surface.gdshaderinc` and the same
  explicitly bound grain texture and pattern uniforms. Reapplication cannot
  add collision or change road width, racing lines or grip definitions.
  Brush UVs include the closing segment and repeat an integer number of times.
  Grain uses Godot's
  `FastNoiseLite.get_seamless_image()` and completed, mipmapped `ImageTexture`s.
  Never embed worker-owning `NoiseTexture2D` resources in threaded-loaded scenes:
  rapid scene cancellation can hang engine shutdown while they are destroyed.
  Generation is bounded by the configured texture size and a yielded loading stage.
  The grain cache is bounded by `course_settings.grain_cache_limit`.
- Material-only changes to saved tracks use `tools/update_track_materials.gd`
  with `PC_SCENE_OUT`, preserving the existing scene UID and physical nodes.
  Full geometry regeneration can recompute alpha hulls from differently imported
  textures and must not be used for a cosmetic-only refresh.
- `data/world_prop_art.json` owns sources, style, themes, roles, dimensions, zones,
  clearances, repetition and collision/shadow behavior for all active outputs.
  `WorldPropScale` uses one world unit per millimetre and trims transparent
  padding before uniform scaling. Catalog SOLID contracts use those lengths
  and alpha-derived hulls. All generated roles share the same size; no role
  clamps, random giant inflation, or anisotropic rail stretching are allowed.
  Tiny roles use physically small props. A focal or rail that cannot fit is
  replaced from a theme-specific pool at its own size, never shrunk to fit.
  Generated story props must use transparent PNG textures, never opaque JPG rectangles.
- Trackside placement must remain clear of checkpoint recovery corridors:
  230 units along the route and 48 units across it, plus the prop radius.

## Calm Stretches

- `TrackCornerMap` marks a centerline sample as corner when the heading turns
  more than 0.5 rad (~29°) over 5 samples each side, and records each sample's
  arc distance to the nearest corner sample ahead or behind.
- Races run both ways, so a spot is calm only when it is at least 250 units
  from any corner in either direction: a corner exit in one direction is the
  braking zone in the other.
- Low-grip surfaces (except the optional shortcut lane) and permanent on-course
  obstacles must sit entirely on calm stretches. Placement underfills rather
  than falling back to a corner. `track_surface_placement_test.gd` enforces it.

## Track Moments

Generated tracks implement the design contract in `game-design-spec.md` section
11 as playable geometry and mechanics:

- `environment_focal`: the fitted household anchor; opening index metadata remains
  available independently of the chosen physical placement.
- `TechnicalSurfaceMoment`: a full-width low-grip or low-speed zone on a seeded
  random calm stretch (see Calm Stretches). A lap without one has none.
- `ShortcutDecision`: a visibly decaled inside lane that is geometrically
  shorter and at least 1.06x faster, but has lower grip. The outer lane remains
  longer and safe for every vehicle build.
- Up to eight additional `patch` surface definitions (target 4-8) add
  deterministic themed grip and speed changes on calm stretches only. They
  remain inside the corridor and clear of every gate and the two designed
  surface moments; a lap short of calm room gets fewer. `TrackVariantPresenter`
  remains the only creator of authoritative runtime `SurfaceZone` nodes.
- `SpeedSection`: the unobstructed start/finish straight.
- `DramaticFinish`: clear forward and reverse run-ups ending at the checker.
  Its visible paint stays on the nominal corridor while its invisible ordered
  sensor reaches the real room/island boundaries.

`generated_moment_indices` and `generated_surfaces` expose these contracts for
runtime presentation and tests. The surface array contains the shortcut, the
technical moment when a calm stretch exists, and up to 8 grip patches. `RacingLine` takes the safe outer lane through the shortcut window,
while `ShortcutRacingLine` exposes the shorter lane to competitive AI when its
speed and grip metadata are suitable. Sunday Drive always stays on the safe
line.

## Visual and Collision Language

- The approved translucent course paint may have subtle hand-painted edge markings.
  No highway-style dashed centerlines, raised kerbs, or hard-edged gameplay-zone
  rectangles. Household objects, material changes and the checker remain readable.
- Generated routes use the themed `TrackSurface` directly and must not add the
  old `TrackRibbon`, whose triangulation produced artifacts in concave routes.
- Gameplay surfaces use feathered low-opacity material tints and seeded,
  physically scaled paint sprites clipped to their authoritative polygons.
  These cues show the technical section, risky shortcut and extra grip patches.
- World-coordinate procedural patterns provide floor detail without a fixed
  count of stamped corridor sprites. Material patterns are not racing lines or
  gameplay zones.
- The themed floor texture is clipped to the room surface. A 760-unit #111316
  overscan ring beyond the fully backed room walls deliberately reads as void,
  including around wide and L-shaped canvases.
- Generated tracks have no continuous inner/outer corridor collision and no
  contour bevel along open stretches. Players may leave the nominal racing
  corridor and drive across the room apron wherever no real visible asset is
  present. Collision belongs only to visible household props, rail sections,
  on-course obstacles, giants, the raised island, gate posts, and room perimeter
  walls.
- Every generated world visual declares one `visual_role`: `SOLID` or `FLAT`.
  `SOLID` means the owning `StaticBody2D` is on a
  vehicle-visible layer (`2`, `4`, or `16`) and its circle, local rotated
  rectangle, or composed shape covers the
  visible center and ends. Circular colliders reach at least 90% of the visible
  visual center and ends. Circular colliders reach at least 90% of the visible
  radius; rectangular coverage reaches at least 90% of the trimmed sprite AABB.
  `FLAT` means presentation only and never owns collision: floor decals, broad
  cloth/paper/cardboard ground sections, corridor material patterns, surface
  tints and grip decals, worn-floor hints, shadows, and checker paint. Solid
  objects must never use a sprite-only placement path.
- There is no moving hazard. The circuit identity keeps its `hazard` sub-seed
  as a reserved slot so the identity and share-code format do not change.
- The island is one visibly raised solid object. Its closed layer-2
  `ConcavePolygonShape2D` segment chain follows the outer contact edge of a dark
  side-face, theme-colored edge and top lip. Recovery begins at that
  visible contact edge; do not send the concave island through convex
  decomposition.
- Themed course rails are real assets drawn from the existing boundary pool.
  `boundary_density` in `data/environment_composition.json` controls outer-run
  coverage, membership, physical join gaps, bounded relocation and inner accents.
  Completed outer runs are first-class records with per-member arc positions;
  inner props and micro clutter cannot satisfy the outer-run requirement.
- Fit minimum complete runs first, then hardware rows, then optional extensions.
  Failed trials roll back every temporary footprint. Relocate whole sets along
  the outer edge or to a bounded parallel outset, never silently to the island.
  Coverage counts actual rail lengths, excluding the empty gaps between items
  and sets. Physical front/back gaps are checked independently of arc metadata.
- Common reusable rails and hardware have explicit repeat budgets in the asset
  contract. The single-focal composition rule does not impose a global one-copy
  limit on a pen that is also used in boundary sets.
  Eight sectors describe actual side occupancy. Outer run records and separately
  budgeted inner accents retain a reserved sector and collision-free apron exit.
  A physically tight placement selects another legal object or location rather
  than shrinking art or violating clearance. Kitchen mixes fork, spoon, chopstick,
  and cork rails; Workshop mixes paint stirrer, dowel, clamp, ruler, and nail
  rails; Office mixes pencil, ruler, pen, and book-spine rails. Rail and corner-
  accent colliders validate their complete oriented footprint, not only their
  center. Neighboring rail footprints do not overlap, and story placement
  reserves the existing physical boundaries and posts. An empty run means open
  drivable apron, never hidden collision.
- Permanent on-course obstacles use the existing AI-safe planner, with target
  ranges of 1–4, 2–6 and 3–8 by act, on calm stretches only. Targets may
  underfill if no safe placement exists; never reduce the 1.6-car viable corridor or either racing-line clearance
  to reach a quota. The obstacle stream remains independent of route geometry.
- Footprint sweeps reject distant segment AABBs before the unchanged narrow-phase
  checks. The optimized result is regression-checked against an exhaustive sweep;
  denser scenery must not trade collision accuracy for placement speed.
- Every ordered checkpoint `Area2D` is asymmetric: its inner endpoint stops at
  `HALF_WIDTH` or the raised island, while its outer endpoint reaches the room
  wall. Inner grass does not trip the gate, but legal outer-apron lines do. The
  checkpoint recovery anchor remains on the racing line. The finish checker
  spans the complete nominal corridor, and its paired physical-size themed posts sit
  symmetrically at the corridor ends so the same landmark reads in forward and
  reverse races. Other checkpoints use two small colliding themed posts without
  blocking the racing line.
- Physical scenery uses the same upper-left key light. Contact shadows follow
  the visible sprite alpha and transform, with a down-right offset of 8% of its
  short extent capped at 3 mm and 0.8 mm softening. The catalog can disable a
  shadow. Giants additionally retain a faint elongated cast shadow.
- Generated roots persist in the `track` group so runtime AI can discover the
  260-point `RacingLine`.
- Collision layers remain: vehicles 1, room walls/raised island 2, player-only
  scenery 4, and visible AI-dodge scenery such as rails/posts/props 16. The
  vehicle scene's base mask is 22 (`2 | 4 | 16`), and race setup also enables
  layer 1 so cars collide with one another.

## AI

- AI follows an invisible curvature-aware `RacingLine` with speed-dependent
  lookahead and curvature-limited speed. Broad turns set up toward the outside,
  then move inward at the apex by up to 90 units before opening the exit.
- Reverse events traverse the same line in reverse through
  `RaceManager.is_reverse_direction`; never reverse only checkpoint order.
- Generated shortcut windows provide both safe and shortcut racing lines with
  tapered transitions. Club Circuit and Clockwork may select the shortcut only
  when its declared speed advantage and grip meet their bounded thresholds.
- Traffic planning is stateful and straight-only. A trailing AI checks both
  lateral pass lanes with parallel probes against vehicles, walls, and visible
  scenery, commits to one clear side for a short hold, and cools down before
  another attempt. When neither side is clear it follows at 0.84 throttle
  instead of forcing contact.
- Close aligned following on a straight recharges the existing boost meter at a
  bounded drafting rate. Drafting never bypasses boost capacity, drain, or the
  shared boosted-speed limit.
- AI probes walls, traffic, AI-dodge scenery, and player-collision corner giants.
  It also samples upcoming `SurfaceZone` polygons, pre-slows for low-grip or
  low-speed material, and only steers around a zone when its lane metadata says
  an alternate corridor exists.
- Obstacle probes remain active at low speed with a 72-unit minimum feeler and a
  committed steer-away response. Sustained low-speed contact with static scenery
  triggers a brief reverse-and-steer escape before checkpoint recovery.
- Stuck detection uses checkpoint and racing-line arc progress rather than raw
  speed. No progress for 2 seconds, wrong-way progress for 0.75 seconds, or more
  than 1.25 seconds off-route can recover the car; a severe 420-unit route miss
  may bypass the normal recovery cooldown. Recovery clears any active overtake
  hold so the car resumes from the legal line.
- Finished and DNF AI stop driving, leave traffic planning, and disable their
  collision layer and mask for the rest of the race. Race setup restores the
  original vehicle collision contract before the next start.
- Juniper, Milo, Tess, and Cass use data-driven personalities for braking,
  corner pace, line commitment, boost timing, shortcut confidence, and passing
  aggression. All personality values are clamped to narrow legal ranges and
  reduced to 30% effect on Sunday Drive, so identity never becomes a hidden
  physics advantage.
- Curvature sampling caps the fitted racing-line radius at 2600 units. Current
  legal-physics tuning is:

  | Preset | Pace / corner k / floor | Braking near-far / response | Boost start / clean-line recharge | Engine force / catch-up |
  |---|---|---|---|---|
  | Sunday Drive | 0.94 / 13.0 / 0.48 | 190-380 / 72 | 28% / none | 1.00x / none |
  | Club Circuit | 1.08 / 15.2 / 0.53 | 165-350 / 56 | 58% / 5 per second | 1.06x / up to +0.09x |
  | Clockwork | 1.12 / 16.4 / 0.58 | 145-315 / 48 | 78% / 8 per second | 1.15x / none |

  The external engine-force ceiling is 1.15x; shared physics still caps normal
  speed at 1.0x and active boost at 1.2x. Retune only with full forward and
  reverse harness coverage.
- Every AI vehicle must complete a legal lap with no more than three recoveries
  in `theme_ai_harness.gd`. The harness also emits `AI_RACE_LAP` telemetry and
  enforces first-lap ceilings of 38 seconds on Sunday Drive, 34 on Club Circuit,
  and 32 on Clockwork across its supported authored and generated tracks.
- `ai_field_spread_test.gd` runs four AI racers for three Club Circuit laps on
  Kitchen, Workshop, and Office. It requires ordered legal gates, no DNFs, at
  least one position exchange and deliberate pass attempt, no more than three
  recoveries per racer, and a slowest/fastest finish-time ratio no greater than
  1.80.
- `ai_recovery_scenarios_test.gd` pins a sustained giant-contact jam and a
  finished car parked on the racing line. The jammed AI must exercise escape or
  recovery and finish legally; the trailing AI must ignore and pass through the
  ghosted finisher without a DNF.

## Verification

Run after generator, builder, surface, collision, or AI changes:

1. `godot --headless --path . --script res://tests/track_seed_gen_test.gd`
2. `godot --headless --path . --script res://tests/asset_collision_integrity_test.gd`
3. `godot --headless --path . --script res://tests/generated_track_composition_test.gd`
4. `godot --headless --path . --script res://tests/generated_race_runtime_test.gd`
5. Representative family/room seeds through `tests/theme_ai_harness.gd` in
   both directions using `PC_THEME`, `PC_ROOM`, `PC_SEED`, and
   `PC_DIRECTION=both`; set `PC_DIFFICULTY` to `sunday_drive`, `club_circuit`,
   or `clockwork` when comparing presets.
6. `godot --headless --path . --script res://tests/ai_race_smoke_test.gd` for
   the three authored regression tracks.
7. `godot --headless --path . --script res://tests/ai_field_spread_test.gd` for
   three-lap four-AI overtaking and field-spread coverage.
8. `godot --headless --path . --script res://tests/ai_recovery_scenarios_test.gd`
   for sustained giant-contact and parked-finisher regressions.
9. A broad theme x room x seed construction stress matrix after geometry or
   composition changes.
10. Direct runtime captures for all six route families after visual changes.
11. `tools/build_release.sh <clean-output-directory>` for the authoritative
   import, complete test suite, scene smokes, native exports, packaged Linux
   smoke, and PCK inspection.

Keep `project.godot` release-clean with only the `App` autoload committed.

# Changelog

## Unreleased

### Added
- A procedural circuit generator (`tools/track_seed_gen.gd`, ported from the
  juangallostra / ChrisPHP racetrack algorithms): random points, convex hull,
  displaced midpoints, angle clamping, and an arc-length spline resample —
  producing organic rounded circuits instead of rectangles. Seeds are
  validated for self-overlap and grid-straight length and are fully
  reproducible.
- Twenty-eight generated circuits baked into `scenes/tracks/circuits/` (fourteen
  layouts per workshop/office theme), each with painted ribbon, edge lines,
  dashed centerline, bold two-row checker strip, seeded prop scatter (island
  fill, corridor slalom, apron clutter) and per-theme furniture surfaces.
- A "GENERATED CIRCUITS" section in Quick Race (paged, workshop/office themed)
  so every baked circuit is playable, plus a circuit roster catalog and test.
- Brightened generated floor/island textures (desk mat, wood planks, toolbox,
  keyboard) and per-theme furniture edge strips on all room walls.
- Room-canvas variety: circuits now live in differently shaped rooms — the
  classic square bench, a long horizontal counter (~2350×900), and a tall
  vertical shelf (~1150×1450) — with polygon wall segments, room-shaped
  surfaces, and corridor clipping to the room outline. The circuit roster
  grew to 52 tracks (26 per theme: 16 classic, 5 wide, 5 tall).
- Track archetypes: the circuit generator now rolls one of four personalities
  per seed — fast (long straights, gentle corners), technical (tight S-curves
  and chicanes), asymmetric (one dominant side), and switchback (sharp
  direction changes) — so generated tracks differ in rhythm and silhouette,
  not just decoration. The circuit roster was re-scanned end-to-end
  (geometry + AI harness, 31 candidates, 16 robust seeds kept across all four
  archetypes, 32 tracks total).
- Wild-racing art pass: removed the circuit markings (white edge lines and
  dashed centerline) so the course reads as painted-on-real-surface plus props
  instead of a marked circuit; added a prop size hierarchy on every island
  (huge hose/toolbox, medium books and planks, small apples and limes, tiny
  paperclips) and a new hand-drawn paperclip prop; fixed a fuchsia-background
  cable hazard; per-theme ribbon contrast tuning.
- Dense collidable island fills: the inner park of every circuit is now packed
  with real objects (books, wooden planks, hose coils, paint cans, utensils)
  that physically block shortcut cuts, layered behind the island prop barrier.
- Three new hand-drawn props (book, wood plank, hose coil) rendered from SVG.

- The complete nine-event Grand Household Circuit, with three story acts,
  persistent standings, unlocks, replayable events, and a championship ending.
- Four tuned handling builds and four-racer fields with AI opponents that plan
  for corners, hold stable racing lines, recover from stalls, and contest rival
  duels, reverse races, legal checkpoint ranking, and finish order.
- Kitchen, Workshop, and Office room identities with distinct surfaces, moving
  hazards, track dressing, and event conditions.
- The Office circuit rebuilt as a desk-triangle route with a keyboard island,
  reversing the lap direction and distinct gate fractions so it no longer
  mirrors the Workshop paperclip.
- Counter-top edge strips along every room wall, and a big plate and cutting
  board dressed across the Kitchen island so walls and the island read as
  real furniture instead of invisible barriers.
- Fixed-height, controller-safe title, paged championship, briefing, vehicle,
  settings, credits, pause, results, and ending screens without menu scrolling.
- A Quick Race circuit picker plus in-race audio and comfort settings that keep
  the current race paused.
- Versioned local saves with atomic replacement, validated backup recovery,
  corrupt-save fallback, and protection against overwriting newer save formats.
- Original music and licensed CC0 toy-racing sound effects, persistent volume
  controls, reduced camera shake, reduced motion, and pause-aware race audio.
- Native Windows x86_64 and Linux x86_64 release exports for offline Steam and
  Steam Deck play.

### Changed

- Championship screens now pair controller-safe actions with original driver,
  vehicle, garage, and route illustrations; the garage visibly presents the
  full four-car roster, unlock requirements, and focused-machine stats.
- Driver portraits and race machines now use distinct, deterministic pixel-art
  identities throughout the championship shell and live races, rendered by the
  refined Procedural 2D avatar and car generators with sharper faces and a
  wider part catalog.
- The start/finish checker now sits on the left straight behind the starting
  grid, and lap gates span the full drivable corridor, so wide lines and brief
  off-track excursions still count the lap.
- Kitchen, Workshop, and Office are now three different circuits: the kitchen
  keeps its counter loop, while the workshop and office are generated from
  smooth closed splines (a wide bench oval for the workshop, a tall paperclip
  for the office) with rounded corners, painted surfaces, and race-grid-aligned
  starting lineups.
- The generated tracks are painted layouts on real environments: the workshop
  is a wooden-plank bench with a giant toolbox island and scattered hardware,
  and the office is a desk mat with a giant keyboard island, sticky notes, and
  paper clips — the props are the collision, not invisible track walls.
- The title and machine bay now use a high-contrast after-hours workbench
  presentation with one dominant race action and the full four-car roster.
- Title PLAY starts the championship; Quick Race, Options, Credits, and Quit are real buttons under it.
- Vehicle select previews a machine, then PLAY confirms the race.
- Title uses a cartoon night-kitchen poster with clean amber and coral action plates; race HUD stays floating clusters.
- Kitchen mugs, fruit, cereal, sponge, utensils, start/finish, and moving
  hazards now use illustrated toy-scale sprites instead of flat polygons.
- The race HUD now keeps position, lap, timer, speed, boost, recovery controls,
  and horizontal racer labels readable without covering the circuit.
- Vehicle-to-vehicle contact now separates along the physics normal instead of
  gluing cars together, caps heading only on the first hit, and restores
  steering as soon as they split.
- AI opponents now hold near-top speed on straights, use their boost meter on
  open stretches, and carry more speed through corners, so club races stay
  close and clockwork races apply real pressure.
- AI opponents also stay in the track corridor, dodge cars and moving hazards,
  catch up from behind without cheating top speed, and recover heading instead
  of stalling short of a lap.
- Engine, countdown, launch, drift, boost, impact, warning, and menu interaction
  cues now use clearer toy-scale sounds, with the engine spooling into a wider
  rev range under throttle.

### Fixed

- Debug hazard warnings and on-track section labels no longer appear in races.
- Menu music now plays a longer melodic loop instead of repeating an alarm-like
  pulse every half second.
- Championship map and settings metadata remain readable at the release
  resolution, keyboard focus stays visible after returning between screens, and
  completed off-screen events remain reachable without a mouse.
- Failed disk writes no longer advance championship progress, discard an
  existing championship, or claim that a race result was saved; affected
  screens now keep Continue blocked and offer an explicit retry.
- A championship win now remains pending across restarts until the ending is
  acknowledged, so quitting before Continue cannot permanently skip it.
- Recovery ghost periods no longer expire while paused, save-error Back returns
  to its originating screen, and reduced motion also disables decorative track
  pulses and the boost camera pulse.
- The full inner circuit now has collision aligned to a continuous visible
  guardrail, preventing cars from cutting through the painted infield.

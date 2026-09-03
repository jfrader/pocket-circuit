# Changelog

## Unreleased

### Added

- The complete nine-event Grand Household Circuit, with three story acts,
  recurring rivals, persistent standings, vehicle and event unlocks,
  replayable races, and a championship ending.
- Four distinct machines and four-racer fields with legal lap validation,
  starting grids, countdowns, race position, finish order, results, and
  championship points.
- Live generated household circuits for every Quick Race reroll and
  championship event. Players can choose a theme and seed, while six route
  silhouettes and six room canvases produce reproducible layouts without a
  curated circuit list.
- Designed track moments on generated circuits: an iconic opening, an early
  crossing hazard in either race direction, a technical surface section, a
  faster low-grip shortcut beside a safe lane, a speed straight, and a clear
  checker run to the finish.
- Kitchen, Workshop, and Office environments with coherent household story
  scenes, toy-scale props, distinct material behavior, moving hazards, and
  readable object-delimited courses.
- Main menu, new and continue flow, championship map, event briefing, machine
  selection, Quick Race, pause settings, credits, results, and ending screens
  designed for keyboard and controller use at 1280 x 720.
- Versioned local saves with atomic replacement, validated backup recovery,
  corrupt-save fallback, and protection from overwriting newer save formats.
- Original music, licensed sound effects, persistent volume controls, reduced
  camera shake, reduced motion, and pause-aware race audio.
- Native Windows x86_64 and Linux x86_64 offline release exports with Steam
  Deck-compatible controls.
- Adaptive music follows race phase when the live engine is loaded (grid on
  countdown, "race" at start with speed-normalized intensity and standing
  pressure, final-lap flag, finish+win result).

### Changed

- Quick Race now accepts arbitrary seeds, and championship events draw a fresh
  seed and deterministic room canvas whenever a race starts.
- Generated circuits now use larger 1.75x room canvases, longer absolute laps,
  and fewer broad corner complexes separated by multiple setup straights. Route
  validation rejects direct chords that replace an entire corner sequence.
- Circuit dressing now combines coherent household story moments with safe
  themed prop pockets, broad cloth and paper set dressing, and denser floor
  details that fill blank room sectors without obstructing the racing corridor.
- Generated rooms now surround the course with dense themed micro-details and
  giant household landmarks, while material patterns and readable grip patches
  break up flat-looking corridors without adding painted racing lines.
- Course boundaries now come only from real household assets. Players can leave
  the racing line and drive across open room aprons wherever no visible prop or
  rail blocks the way, while the central island reads as a raised solid object.
- Full-room ordered checkpoint sensors protect legal laps when players explore
  wide apron routes; small themed posts mark the corridor-sized checker gates.
- Props, obstacles, and giant landmarks now share shape-matched warm shadows in
  one down-right light direction, with longer cast shadows grounding the largest
  objects. Room perimeter walls now overlook a dark void instead of extra floor.
- Racing-line AI now fields genuinely competitive opponents: difficulty changes
  corner pace, braking, acceleration, and boost strategy; rivals set up and hit
  corner apexes, draft, pass through checked clear lanes, use suitable
  shortcuts, and express distinct bounded driving personalities while staying
  within the player's legal normal and boosted speed limits.
- Championship screens pair controller-safe actions with original drivers,
  machines, garage art, and route illustrations; the garage presents the full
  roster, unlock requirements, and focused-machine stats.
- The race HUD keeps position, lap, timer, speed, boost, recovery controls, and
  horizontal racer labels readable without covering the circuit.
- Vehicle contact separates along the physics normal and restores steering as
  cars split, reducing prolonged collision lockups.

### Fixed

- Every solid generated object now stops cars across its visible footprint,
  including giant hammers, wrenches, utensils, desk props, and boundary accents;
  only ground-painted art remains drive-over.
- Generated circuits no longer stop cars against invisible corridor walls.
  Every generated collider is backed by a visible prop, rail, raised-island
  rim, gate post, hazard, giant landmark, or room wall.
- The race camera and out-of-bounds recovery now follow each generated room's
  full scale and shape, including the missing quadrant of L-shaped rooms.
- Start grids remain outside the island, lap gates span the full available room
  cross-section, and forward and reverse races use the correct checker order.
- Menu and shell screens now loop the Tiny Torque Grid catalog take instead of
  an alarm-like pulse or the previous placeholder arrangement.
- Recovery timers do not expire while paused, championship map and settings
  metadata remain readable at the release resolution, keyboard focus stays
  visible between screens, and completed off-screen events remain reachable
  without a mouse.
- Failed disk writes no longer advance championship progress, discard an
  existing championship, or claim that a result was saved.
- Championship wins remain pending across restarts until the ending is
  acknowledged, preventing a quit from permanently skipping the finale.
- Debug surface labels and development-only overlays no longer appear in
  release races; gameplay hazard telegraphs remain visible.

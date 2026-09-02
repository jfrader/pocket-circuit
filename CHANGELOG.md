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
- Course boundaries read from material changes and sparse household-object runs
  that alternate between both sides, one side, and open visual sectors rather
  than enclosing the track with a repeated fence or painted race lines.
- Racing-line AI now fields genuinely competitive opponents: difficulty changes
  corner pace, braking, acceleration, and boost strategy; racers anticipate bad
  surfaces, dodge every collidable course prop, and stay within the player's
  legal normal and boosted speed limits.
- Championship screens pair controller-safe actions with original drivers,
  machines, garage art, and route illustrations; the garage presents the full
  roster, unlock requirements, and focused-machine stats.
- The race HUD keeps position, lap, timer, speed, boost, recovery controls, and
  horizontal racer labels readable without covering the circuit.
- Vehicle contact separates along the physics normal and restores steering as
  cars split, reducing prolonged collision lockups.

### Fixed

- Generated circuits now have continuous round-joined collision on both course
  edges, preventing apron and infield cuts even where themed barrier props are
  intentionally absent. Authored island collision still follows its complete
  visible boundary without concave-polygon decomposition failures.
- The race camera and out-of-bounds recovery now follow each generated room's
  full scale and shape, including the missing quadrant of L-shaped rooms.
- Start grids remain outside the island, lap gates span the full drivable
  corridor, and forward and reverse races use the correct checker order.
- Menu and shell screens now loop the Tiny Torque Grid catalog take instead of
  an alarm-like pulse or the previous placeholder arrangement.
- Championship map and settings metadata remain readable at the release
  resolution, keyboard focus stays visible after returning between screens, and
  completed off-screen events remain reachable without a mouse.
- Failed disk writes no longer advance championship progress, discard an
  existing championship, or claim that a result was saved.
- Championship wins remain pending across restarts until the ending is
  acknowledged, preventing a quit from permanently skipping the finale.
- Recovery timers do not expire while paused, keyboard focus remains visible
  between screens, and completed off-screen events remain reachable without a
  mouse.
- Debug surface labels and development-only overlays no longer appear in
  release races; gameplay hazard telegraphs remain visible.

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

### Changed

- Quick Race now accepts arbitrary seeds, and championship events draw a fresh
  seed and deterministic room canvas whenever a race starts.
- Generated circuits now give six route families seed-driven changing-radius
  bends, harmonic lobes, and localized chicanes, with wider long-form rooms and
  technical fallbacks that preserve identity without becoming stretched ovals.
- Circuit dressing now combines coherent household story moments with safe
  themed prop pockets, broad cloth and paper set dressing, and denser floor
  details that fill blank room sectors without obstructing the racing corridor.
- Course boundaries read from household objects and material changes rather
  than white edge lines, dashed centerlines, kerbs, or translucent overlays.
- Racing-line AI now follows generated routes in the active race direction,
  keeps to the safe lane beside optional shortcuts, plans for corners, dodges
  traffic and moving hazards, and recovers from stalls.
- Championship screens pair controller-safe actions with original drivers,
  machines, garage art, and route illustrations; the garage presents the full
  roster, unlock requirements, and focused-machine stats.
- The race HUD keeps position, lap, timer, speed, boost, recovery controls, and
  horizontal racer labels readable without covering the circuit.
- Vehicle contact separates along the physics normal and restores steering as
  cars split, reducing prolonged collision lockups.

### Fixed

- Inner island collision follows the complete visible boundary on both
  generated and authored circuits, preventing cuts through the infield without
  concave-polygon decomposition failures.
- Start grids remain outside the island, lap gates span the full drivable
  corridor, and forward and reverse races use the correct checker order.
- Failed disk writes no longer advance championship progress, discard an
  existing championship, or claim that a result was saved.
- Championship wins remain pending across restarts until the ending is
  acknowledged, preventing a quit from permanently skipping the finale.
- Recovery timers do not expire while paused, keyboard focus remains visible
  between screens, and completed off-screen events remain reachable without a
  mouse.
- Debug surface labels and development-only overlays no longer appear in
  release races; gameplay hazard telegraphs remain visible.

# Changelog

## Unreleased

### Added

- The complete nine-event Grand Household Circuit, with three story acts,
  persistent standings, unlocks, replayable events, and a championship ending.
- Four tuned handling builds and four-racer fields with AI opponents that plan
  for corners, hold stable racing lines, recover from stalls, and contest rival
  duels, reverse races, legal checkpoint ranking, and finish order.
- Kitchen, Workshop, and Office room identities with distinct surfaces, moving
  hazards, track dressing, and event conditions.
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
- AI opponents now stay in the track corridor, dodge cars and moving hazards,
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

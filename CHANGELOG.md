# Changelog

## Unreleased

### Added

- The complete nine-event Grand Household Circuit, with three story acts,
  persistent standings, unlocks, replayable events, and a championship ending.
- Four tuned handling builds and four-racer fields with AI opponents, rival
  duels, reverse races, legal checkpoint ranking, finish order, and DNF grace.
- Kitchen, Workshop, and Office room identities with distinct surfaces, moving
  hazards, track dressing, and event conditions.
- Controller-safe title, championship, briefing, vehicle, settings, credits,
  pause, results, and ending screens.
- A Quick Race circuit picker plus in-race audio and comfort settings that keep
  the current race paused.
- Versioned local saves with atomic replacement, validated backup recovery,
  corrupt-save fallback, and protection against overwriting newer save formats.
- Original music and sound effects, persistent volume controls, reduced camera
  shake, reduced motion, and pause-aware race audio.
- Native Windows x86_64 and Linux x86_64 release exports for offline Steam and
  Steam Deck play.

### Fixed

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

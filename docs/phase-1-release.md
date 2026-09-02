# Pocket Circuit Phase 1 Release

## Product

Phase 1 is scoped as a complete premium offline game for Windows, Linux, and
Steam Deck. It is not intended to ship as an online-game preview. At release, a
player must be able to begin, complete, and replay the entire championship
without an account or network connection.

The release uses the bracket pressure, recurring rivals, short event intros,
and vehicle unlock rhythm associated with classic miniature arcade racers.
Every name, character, vehicle, environment, layout, story beat, visual, sound,
and line of copy is original.

## Player Promise

> Tiny racing. Big stakes. Win the Grand Household Circuit before sunrise.

Races last two to five minutes. The full first championship should take about
two to four hours on a first playthrough, with immediate event replay and
faster subsequent runs.

## Championship Story

The annual Grand Household Circuit is an after-hours championship built across
three enormous rooms. Retired racer and garage owner Inez "Spanner" Solis
enters newcomer Rae Sparks with a repaired Rustbug. Rae must qualify in the
kitchen, survive the improvised workshop league, and earn a place in the
office final before reigning champion Cass Relay closes the circuit to rookies.

The tone is playful, brisk, and arcade-first. Story appears in event cards and
short post-race exchanges. It never interrupts driving with long cutscenes.

### Cast

| Character | Role | Racing identity |
|---|---|---|
| Rae Sparks | Player driver | Adaptable newcomer; starts in the Rustbug |
| Inez "Spanner" Solis | Mentor and garage owner | Practical, warm, never stops tuning |
| Juniper Gear | Act I rival | Precise lines and late braking in the Pinbolt |
| Milo Dash | Act II rival | Heavy contact and fearless shortcuts in the Scrapjaw |
| Tess Circuit | Act III rival | Long controlled drifts in the Flicker |
| Cass Relay | Reigning champion | Calm, fast, and dismissive until Rae earns respect |

## Event Structure

Each act contains two four-car races and one rival event. A race awards points
for the player's best finish: 10 for first, 7 for second, 5 for third, and 3
for fourth. Retrying never removes points. Ten points unlock the next event;
twenty points across an act unlock its rival finale. This keeps losses
meaningful without creating a lives system or progression dead end.

| ID | Act | Event | Environment | Format | Unlock |
|---|---:|---|---|---|---|
| kitchen_crumb_rush | 1 | Crumb Rush | Kitchen Counter | 2-lap circuit | Start |
| kitchen_mug_run | 1 | Mug Run | Kitchen Counter reverse | 3-lap circuit | 10 act points |
| kitchen_clean_line | 1 | The Clean Line | Kitchen Counter | Rival duel, first to finish | 20 act points; Pinbolt |
| workshop_screw_loose | 2 | Screw Loose | Workshop Bench | 2-lap circuit | Win Act I |
| workshop_ruler_drop | 2 | Ruler Drop | Workshop Bench reverse | 3-lap circuit | 10 act points |
| workshop_heavy_metal | 2 | Heavy Metal | Workshop Bench | Rival duel, first to finish | 20 act points; Scrapjaw |
| office_paper_trail | 3 | Paper Trail | Office Desk | 2-lap circuit | Win Act II |
| office_keyboard_cut | 3 | Keyboard Cut | Office Desk reverse | 3-lap circuit | 10 act points |
| office_last_light | 3 | Last Light Grand Final | Office Desk | 4-car, 4-lap final | 20 act points; Flicker and ending |

Reverse events use the finish line followed by checkpoints 7 through 1. Their
recovery transforms rotate and mirror the forward recovery offset, their start
grid faces into the reverse route, and AI reads the same RaceManager order as
the player. They are not implemented by merely negating vehicle input.

## Track Design

All three room themes use a shared, tested championship course footprint.
Kitchen keeps its authored texture and dressing art. Workshop and Office are
runtime-authored variants created from Node2D, Polygon2D, Line2D, and Label
nodes: they hide Kitchen texture/dressing sprites, reveal and recolor
collision-matched polygon fallbacks, safely reposition and recontextualize
selected obstacle bodies, and add room-specific world markings and oversized
props.

The current surface and environmental-hazard configuration is exact:

| Theme | Base surface | Special surfaces (grip / speed) | Moving hazard |
|---|---|---|---|
| Kitchen | Polished counter | Wet spill (0.58 / 0.88) | Rolling fruit crosses the top racing line |
| Workshop | Workbench | Oil slick (0.45 / 0.92); sawdust (0.78 / 0.72) | Sliding socket crosses the bottom racing line |
| Office | Desk mat | Loose paper (0.84 / 0.78); keyboard (0.70 / 0.64) | Swinging cable crosses the right racing line |

Surface multipliers are transient vehicle state and never mutate the selected
VehicleStats resource. They apply equally to player and AI, support overlapping
zones, and reset to the room's base surface after exit or recovery. Each hazard
uses a deterministic 1.2-second warning, 1.6-second crossing, and 2.8-second
cooldown. Contact applies a bounded 90-unit impulse after a 0.78 velocity slow;
hazards use Area2D collision, never modify checkpoints, and stop with the paused
scene tree.

All three rooms use the championship's homologated collision and checkpoint
footprint, letting players carry learned racing lines between acts. Distinct
room dressing, surface physics, warning language, moving hazards, lap counts,
field formats, and reverse events change how that footprint races in each act.

## Vehicles

| Vehicle | Archetype | Strength | Tradeoff | Unlock |
|---|---|---|---|---|
| Rustbug | Balanced | Predictable recovery and all-round pace | No dominant specialty | Start |
| Pinbolt | Grip | Braking and technical corner speed | Lower drift boost and top speed | Win Act I |
| Scrapjaw | Heavy | Stability, collisions, and straight-line speed | Slow turn-in and recovery | Win Act II |
| Flicker | Drift | Rotation and boost generation | Demands precise counter-steer | Complete championship |

Vehicle unlocks are permanent on the local save. They are side-grades, not a
power ladder. Any unlocked vehicle can replay any completed event.

The four machines use explicit deterministic Procedural 2D mappings shared by
the garage and live race. Rustbug, Pinbolt, Scrapjaw, and Flicker keep distinct
compact, coupe, muscle, and buggy silhouettes with fixed palettes and parts.
The generated textures replace presentation only: every machine retains its
existing VehicleStats, transform, common collision geometry, and save identity.

## Audio and Feedback

The current review build keeps original synthesized menu and race loops pending
the project composer's final cues. Engine, countdown, go, UI, drift, boost,
impact, and hazard-warning effects use edited 48 kHz audio from Kenney's CC0
Interface, Impact, and Sci-Fi packs. Exact sources, transformations, and pack
hashes live in `ASSET_PROVENANCE.md` and `assets/audio/LICENSE.md`.

One persistent AudioDirector owns a single music player, a local-player engine
loop, and a fixed one-shot effects pool. It switches rather than stacks menu
and race loops, follows local vehicle speed and throttle for engine pitch and level, ducks
race music and silences engine feedback while paused, and routes through the
persisted Master, Music, and SFX settings.

## Application Flow

```text
BOOT
  -> TITLE
  -> NEW CHAMPIONSHIP / CONTINUE / QUICK RACE PICKER / SETTINGS / CREDITS / QUIT
  -> CHAMPIONSHIP MAP
  -> EVENT CARD + RIVAL LINE
  -> VEHICLE SELECT
  -> COUNTDOWN
  -> RACE
  -> PAUSE / AUDIO + COMFORT SETTINGS
  -> RESULTS + POINTS + UNLOCKS
  -> CHAMPIONSHIP MAP
  -> FINAL ENDING
  -> POST-CHAMPIONSHIP REPLAY
```

The last selected vehicle and settings persist. Save data is written when a
championship result is finalized, as well as after an unlock or setting change.
The final result stores the ending as pending; leaving the ending screen records
its acknowledgment, so a restart before Continue presents it again. A missing
or corrupt primary save recovers a validated backup when available, otherwise
it falls back to defaults without blocking the title screen. A save from a
newer game version remains untouched: the current build enters read-only mode,
disables New Championship, and explains how to preserve the existing progress.

The comfort settings expose reduced camera shake and reduced motion separately,
including from the pause menu. Reduced motion skips AppShell screen entrance
tweens, countdown scaling, decorative track pulses, and the boost camera pulse
while preserving content, focus indication, race timing, and audio cues.

## Difficulty

Phase 1 exposes three AI presets. Difficulty changes racing pressure, not
rewards or content access.

| Preset | AI behavior |
|---|---|
| Sunday Drive | Conservative corner floor, earlier braking, limited opening boost, and no catch-up power |
| Club Circuit | Competitive baseline with later braking, clean-line boost recovery, and modest bounded catch-up |
| Clockwork | Highest legal corner pace, strongest boost economy, and maximum legal acceleration without catch-up |

Catch-up never teleports a racer, alters checkpoints, or raises the vehicle
beyond its legal boosted speed. AI engine force is capped at 1.15x while the
shared vehicle controller still enforces the same 1.0x normal and 1.2x boosted
top-speed limits for every racer. AI cannot handbrake-drift, so Club Circuit and
Clockwork recover a small amount of boost only while holding a clean, fast line;
the meter still uses the player capacity, drain, and boosted-speed cap. The
player receives no hidden handling penalty.

## Release Gates

Phase 1 is release-ready only after all of the following are verified:

- Fresh, continued, completed, backup-recovery, and corrupt-save flows pass.
- Every event is completable by the player and by AI simulation.
- Keyboard and one controller operate every menu and race action.
- The debug overlay is unavailable in release exports.
- Master, music, and effects volumes persist; reduced camera shake and reduced
  motion persist independently.
- Windows x86_64 and Linux x86_64 release exports build without errors.
- The game runs offline and contains no login, premium currency, or
  unavailable-online-mode prompts.
- Credits include licenses for every shipped font, image, and audio asset.

These are gates, not a substitute for the signed manual QA checklist. Automated
tests, headless boot/race smokes, release-config validation, Linux packaged
startup, and Windows/Linux export generation are covered by the release
pipeline. Controller-wide playthroughs and clean-machine Windows, Linux, and
Steam Deck checks must still be recorded against the exact candidate hash.

## Deferred Releases

Split-screen, LAN, internet multiplayer, matchmaking, accounts, dedicated
servers, MMO persistence, live economy, premium currency, and seasonal systems
are outside Phase 1. Their future architecture must adapt to the shipped race
rules rather than holding this release open.

## Exact Release Commands

Run from the repository root:

```bash
python3 tools/validate_release_config.py
/usr/bin/godot --path . --headless --import
for test in tests/*.gd; do /usr/bin/godot --path . --headless --script "res://$test"; done
/usr/bin/godot --path . --headless --scene res://scenes/boot/boot.tscn --quit-after 300
/usr/bin/godot --path . --headless --scene res://scenes/race/prototype_race.tscn --quit-after 600
./tools/build_release.sh
(cd builds && sha256sum --check SHA256SUMS)
```

To keep output outside the worktree, pass one explicit directory:

```bash
./tools/build_release.sh /absolute/path/to/pocket-circuit-release
(cd /absolute/path/to/pocket-circuit-release && sha256sum --check SHA256SUMS)
```

## Current External Steam Blockers

- The publisher must complete Steamworks enrollment, the per-app fee, banking,
  tax, and identity checks.
- Steamworks has not supplied repository-safe values for `<STEAM_APP_ID>`,
  `<WINDOWS_DEPOT_ID>`, or `<LINUX_DEPOT_ID>`; no real IDs belong in Git.
- The owner must approve store assets and copy, base/regional pricing and any
  discount, the content survey, build/depot assignment, and release branches.
- Valve must review and approve the store page and release build, and all
  current waiting/Coming Soon requirements must be satisfied.
- The owner must perform the final Steamworks release action. Repository builds
  and SteamPipe uploads cannot press the release button or replace that approval.

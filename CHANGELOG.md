# Changelog

## [Unreleased]

### Changed
- Outer track edges now have coherent, colliding sets of pencils, pens, utensils, straightedges and workshop hardware. Each set stays on the outside and follows the edge as a unit; inner props and scattered crumbs no longer count as outer framing. This physical-layout update advances the generator version.
- Generated tracks restore colliding household objects along both sides of the course, with seed-varying clusters and quantities. Pens, rulers, sticks, utensils and workshop rails keep their real sizes and leave an open exit to the apron.
- On-course obstacle targets now vary from 1–4, 2–6 and 3–8 by act, with more small household objects to steer around. AI passing space, checkpoints and recovery clearances are unchanged. These physical-layout changes advance the generator version; older circuit codes and lap/ghost records no longer match.
- Racing routes now use muted, translucent paint with subtle brushwork and painted edge markings. Countertop tiles and wood grain continue beneath the course instead of forming a separate cut-out surface. The surrounding tabletop remains drivable; vehicle handling and grip zones are unchanged.
- Kitchen, Workshop, and Office have a regenerated painted overhead environment library. Household objects keep believable relative sizes, with one focal arrangement, supporting groups and clearer space around the racing line. Cars are unchanged.
- Room surfaces vary procedurally by seed: Kitchen ceramics and preparation boards, Workshop timber and cutting mats, and Office desktops and woven or leather-like pads. Pattern layout, spacing, orientation and material combinations vary independently of track geometry; the same seed rebuilds the same room.
- Menus, the loading screen, the pause menu, and the race HUD now sit on a lamp-lit midnight workbench: cream plates with ink outlines, masking-tape labels, and the cast, their cars, and the four-car garage on the right of every screen. The garage shows speed, grip, mass, and drift for the focused car, and locked cars appear as padlocked silhouettes.
- The title and settings boards are cream, so the cars and portraits no longer sink into the wood. The race speed number sits beside the boost tube.
- The championship is the route board. Each race is a stop on the road. Focus follows the road.
- Quick Race opens on a new circuit each visit. The title music is a new piece each launch.
- The Garage score now carries its chord and bass through each bar, and Ignition builds from low to full intensity across its eight bars instead of replaying Garage quietly.

### Fixed
- Vehicle-audio warm-up now yields between engine voice, loop and effect synthesis so it does not stall the loading screen in one long batch.
- Quick Race entries and rerolls cycle through Kitchen, Workshop and Office instead of remaining pinned to Kitchen. The preview and Play action use the selected theme.
- Course palettes now contrast with both the tabletop and the island, including their appearance after translucent paint is blended over the room surface.
- Starting grids stay clear of rotated finish sensors and nearby furniture edges in both race directions. Scenery placement reserves gate posts and sealed bays, and grip artwork no longer hides solid rims behind rectangular texture stamps.
- Button labels no longer carry a thick text stroke.
- Starting Grid now holds from the menu through loading, countdown, and the complete first lap. A circuit's own seed lands directly on Grid in one musical handoff; automatic race rotation begins after lap one and excludes the drumless Breather and post-race Cooldown phases.
- Starting a newly generated menu or circuit score no longer cuts off the score already playing. The outgoing score stays up until the incoming music is audible, then crossfades into it.
- Your car keeps its engine note for every race in a session. It used to fall silent after the first one, while still reporting that it was playing.
- Leaving a race for the menu no longer drops the music out. The menu stays on Starting Grid until the next race.
- Your own tyres now use the same loop as rival cars, and they stay quiet unless the car is actually sliding. A small steer does not open them.
- Settings has separate Engine and Tyres sliders. SFX no longer changes them.
- Nearby rival cars now have their own engine note, pitched from that car. Far cars stay quiet.
- Tyre sound now follows the same drift and slide state as skid marks, stays present through ordinary steering, changes character with the room surface, and comes from nearby rival cars as positional audio.
- Tyre scrub is quieter in ordinary corners and resolves into a rising, resonant squeal during a full slide instead of broadband hiss.
- Fixed false "WRONG WAY" warnings and the resulting teleport reset when driving on the open apron beside a folded circuit. Wrong-way is now a warning only — the car is never reset for it.
- Race music no longer loops one section or lags behind the race. Each circuit now generates its own score from the track seed, so a circuit always sounds the same while different circuits, tiers, and acts sound different, and the race rotates through grooves and peaks after lap one, with a reset sting, final-lap cue, and win/loss outros.
- Shipped the live Gamestruments engine into the release gate (sync + hard `ClassDB.class_exists("GamestrumentsPlayer")` check at the start of `tools/build_release.sh`). Removed rendered WAV fallbacks (`assets/audio/menu_loop.wav`, `race_loop.wav` and their `.import`s); the live engine is now mandatory — there is no silent-music or WAV fallback mode.

### Added

- Drifting now makes a continuous tyre scrub that follows the slide instead of a
  single scratch at the start of it, and it bites harder the faster and more
  sideways you go. Crashes are built from the machine's own weight and
  toughness, so a light tap, a hard hit and a heavy car all sound different.
  Boost and the menu/race blips are generated too — the game no longer ships any
  recorded sound effects.
- Each machine now has its own engine voice, generated from the car's own stats
  instead of pitching one shared loop. A virtual gearbox pulls revs up and drops
  them on each shift, the note changes with throttle and load, and coasting
  sounds different from power.
- Championship events now use progressive track length tiers (from compact to marathon). Quick Race exhibition lengths now rotate across tiers per entry.
- The complete nine-event Grand Household Circuit, with three story acts,
  recurring rivals, persistent standings, vehicle and event unlocks,
  replayable races, and a championship ending.
- Four distinct machines and four-racer fields with legal lap validation,
  starting grids, countdowns, race position, finish order, results, and
  championship points.
- Four new Quick Race / exhibition-only machines (Thimble, Spindle, Anvil,
  Dustmite) — one per body type (compact/coupe/muscle/buggy) with dedicated
  procedural car_art (seeds 92005–92008, palettes, parts) and retuned
  VehicleStats (light agile, technical grip, heavy bruiser, loose off-road).
  Championship acts, unlocks, and progression are unchanged.
- Live generated household circuits for every Quick Race reroll and
  championship event. Players can choose a theme and seed, while seeded circuit
  plans and six room canvases produce reproducible layouts without a
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
- Race music now uses the full extended arc (menu/garage, grid, ignition,
  slipstream, attack, redline, final lap, finish, cooldown).
- Completed championship events now open solo Mastery Runs against a compatible
  personal-best ghost, with transparent circuit-shape-calibrated bronze, silver,
  and gold targets plus configuration-specific lap and race records.
  Medals never affect story points or unlocks.
- Generated circuits now have readable deterministic names and complete compact
  identity summaries. Offline share codes open a verified route preview before
  an exhibition race, while bounded recent history and favorites survive
  restarts without affecting championship progress, mastery records, or ghosts.
- Kitchen, Workshop, and Office circuits now pick a room-story material family
  and one of two curated palettes from a separate seed. Floor and racing surface
  stay on one world-space pattern; the racing line does not change.
- Solo time trials no longer trap you on Results if a save fails. Continue still
  works, and championship progress stays unchanged.
- Time-trial ghosts now save after a real race instead of failing a hidden
  validation check.
- Generated circuits mix left and right corners instead of one-way ovals, and
  workshop wood no longer sits under a grey racing-surface wash.
- Long championship seeds keep mixed corners instead of collapsing into a
  simple oval. Share codes from generator v2 no longer load.
- Generated circuits now include deep infield sections, offset switchbacks,
  doglegs and harbour loops, with seeded proportions and properly rounded
  corners instead of rotated ovals. Generator v6 rejects older share codes.
- Compound corners add diagonal connectors and independently varied approach
  and exit angles while retaining deep infields and long braking straights.
- Cars keep a readable toy-scale top speed. Pushing too hard at speed can
  start a recoverable slide; counter-steer saves it, and handbrake drifts
  still award boost.
- Quick Race and Circuit Discovery now offer Compact, Standard, Long and
  Endurance sizes. Larger circuits use expanded rooms and distance-aware curve
  sampling; shared codes and favorites preserve the selected size.
- A new Marathon size joins the tier list: a 4.5x room and a dedicated folded
  grammar (`double_switchback` and `deep_comb`) produce circuits with roughly
  twice the turns (16–22 broad complexes) at roughly twice the length
  (32–48k world units), without touching the other tiers' seed geometry.
- Opening/tightening two-arc corners and safe section excursions add new turn
  profiles. L-shaped rooms now vary their elbow and proportions by seed.
- Correctly following a long curve no longer causes a false wrong-way reset,
  and generated AI racing lines no longer fold at abrupt lateral transitions.
- Deep bays contain visible raised pads that block cross-cuts throughout the
  infield while preserving the driving corridor and an open apron sector.
- Championships keep their master seed, rooms and story progress after the
  geometry update; old-layout ghosts and mastery records no longer match new laps.
- Race HUD calls a solo run a time trial instead of 1st of 1, drops invisible
  gate numbers, and the personal ghost is easier to see. Championship results
  say saved instead of filed.
- Marathon-length circuits are now genuinely folded instead of just longer:
  the seeded route packs switchback spines, combs, a serpentine, and a
  four-lobe cross into the room, and the L-shaped room gets its own folded
  route with a combed lower arm.

### Changed

- Existing shared marathon codes and any saved laps or ghosts keyed to the old
  marathon geometry no longer match, because the generator version advanced.
  Championship seeds, rooms, and story progress are kept.
- Live race music now cycles through extended cruise and high-pressure sections, with grid reprises and a victory sting, replacing the previous repetitive loops.

- Quick Race is now a one-click exhibition: a fixed Kitchen/Classic circuit
  (seed 875, standard length, forward direction) with just PLAY, CHANGE CAR,
  and BACK TO TITLE. Theme, size, and direction selectors are gone.
- Cars now receive distinct procedural liveries per driver. Rae, Inez, Tess,
  Cass and rivals sharing a chassis get different palette/livery/wheel/spoiler
  cosmetics; the same race field always produces the same looks via deterministic
  slot disambiguation on collisions (including fallbacks).
- Music now plays at a normal listening level instead of sitting far below it.
  Both loops are mastered to the same -14 LUFS target with a -1 dBTP ceiling the
  Gamestruments library uses, the race loop is the catalogue's Cruise take
  rather than a short motor hum, and the engine is balanced under the music
  instead of over it. A Master-bus limiter keeps the summed mix below 0 dBFS.
- Driving forward no longer teleports you back to the last gate after
  brushing a nearby checkpoint or leaving the racing line briefly. Recovery
  puts you back on the nearby route, facing the right way.
- Steering follows the stick more at speed. Fast throttle-on corners can
  slide the rear a little without Space; Space is still the big drift.
- Generated finish lines now span the full racing corridor and use symmetric
  household landmarks that read clearly in forward and reverse races. Moving
  hazard artwork is no longer reused as static scenery.
- Generated circuits now add progression-scaled permanent obstacles with
  AI-validated passing space. Kitchen and workshop hazards roll onto the course
  without a countdown overlay; the office coiled cable stays put.
- Generated circuits now compose different straight extents, headings and turn
  sections within each route program, with broader minimum corner radii.
- Scenery collision footprints are prepared off the main thread before race
  assembly instead of being scanned during visible scene construction.
- Workshop and Office now use coherent bench/desktop materials, distinct
  cutting-mat and desk-pad islands, and standalone tools, keyboard and notebook
  artwork instead of stretching whole objects across the infield.
- Grip and shortcut markings no longer sit on grey translucent rectangles;
  rectangular prop shadows now fade out smoothly instead of ending abruptly.
- Kitchen races now use a coherent countertop and wooden island, with
  world-aligned material detail and illustrated mugs, plates and tea-service
  landmarks. Ambient cloth and paper dressing stays clear of the racing path.
- Cloth, wood and desk-pad floors now repeat across the room at a consistent
  material scale instead of appearing as large solid-color fills.
- Raised-island artwork now displays its full image over a solid material base
  rather than sampling a nearly invisible corner of the texture.
- Menu buttons now keep crisp borders at different sizes, with distinct hover,
  keyboard focus, pressed, disabled and car-selection feedback. HUD instruments
  use fixed-size details, cleaner type and more consistent spacing.
- Race starts and retries now show an illustrated pit lane while preparing the
  circuit, car animations and graphics before the countdown. Car animation
  frames are prepared ahead of play instead of being drawn when racing begins.
- Title and garage screens now use illustrated motorsport workbench artwork,
  clear Play/Next actions, and the actual selected car. Quick Race can change
  cars without losing its chosen circuit, and briefings can launch immediately.
- Race position, lap, checkpoint, timer, speed, boost, and racer progress now
  use a compact illustrated HUD that leaves more of the circuit visible.
- Recovering players can pass through rival cars but still collide with the
  circuit and trigger checkpoints, preventing ghost-state corner cuts and
  repeated resets when accelerating away from recovery.
- Raised inner islands now stop corner cuts at their visible edge, while legal
  wide lines across the open outer apron still count. Persistent wrong-way
  driving returns the car to its last checkpoint instead of wasting a lap.
- Race cars no longer draw a heading caret on the rear; front wheels steer
  and tyres roll with the live Procedural 2D animation frames.
- Starting a race after updating an existing checkout no longer depends on
  refreshing Godot's generated global-script cache first.
- Driver portraits and vehicle sprites now use Procedural 2D's remade native
  layered artwork, with sharper silhouettes, body panels, faces, clothing,
  wheels, lights, trim, and liveries while preserving gameplay dimensions.
- Vehicle handling now uses per-car power curves, axle grip and braking with
  speed-sensitive steering. Steering settles promptly after release, and
  releasing the handbrake restores grip instead of sustaining a spin.
- Rustbug, Pinbolt, Scrapjaw and Flicker have distinct chassis parameters;
  AI steering and braking use the same handling model as the player.
- Slippery and slow surfaces preserve entry momentum instead of abruptly
  cutting speed. Rival cars accelerate between corners, brake for the actual
  upcoming curve, and no longer mistake repeated escape shuffling for progress.
- Rivals can use clear apron shortcuts to the next required checkpoint,
  avoid unnecessary straight-line grip braking, and judge passing space
  against the actual route rather than nearby wall placement.
- Club Circuit rivals now keep competitive pace across generated fields and
  resume recoveries in their own lane with useful speed and boost.
- Starting-grid physics no longer displaces rivals into the island before
  they launch. Following cars now respect the leader's speed and distance
  rather than accelerating into a slow queue.
- Quick Race now accepts arbitrary seeds, while each new championship keeps a
  versioned circuit identity for every event so retries, replays, reverse races,
  saves, and resumes retain the same generated route and room canvas.
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
- Quick Race now uses a single fixed household circuit (Kitchen, Classic canvas,
  seed 875) instead of rerolling a fresh track each visit, and the title screen
  preloads its route preview. The seed picker is reserved for debug builds.

### Fixed

- Every solid generated object now stops cars across its visible footprint,
  including giant hammers, wrenches, utensils, desk props, and boundary accents;
  only ground-painted art remains drive-over.
- Generated circuits no longer stop cars against invisible corridor walls.
  Every generated collider is backed by a visible prop, rail, raised-island
  rim, gate post, hazard, giant landmark, or room wall.
- AI rivals now detect stalls by route progress, keep avoiding obstacles at low
  speed, reverse and steer out of sustained scenery contact, and recover from
  severe route departures without forming DNF trains. Finished rivals become
  non-colliding ghosts instead of parked obstacles.
- Generated rails, solid apron props, and giant landmarks now reserve a full
  car-width safety margin outside the racing corridor, while giant placement
  also protects the committed safe and shortcut racing lines with a swept hull.
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

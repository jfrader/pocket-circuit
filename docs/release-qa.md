# Phase 1 Release QA

Test the packaged candidate on each target machine. Copy this checklist for each
platform/input pass. Leave blocked or failed checks unticked and link the defect.

## Candidate record

| Field | Record |
|---|---|
| Tester / date | |
| Exact candidate Git SHA | |
| Package path / SHA-256 | |
| SHA256SUMS verification result | |
| Steamworks build / branch / depot, if assigned | |
| OS / version | |
| Hardware / display resolution | |
| Keyboard / controller model / connection | |
| QA save directory / backup location | |
| Run seeds / routes / car IDs used | |
| Per-check evidence / result / defect links | |
| Final result / tester signature | |

- [ ] Verify the package against `SHA256SUMS` before installation; record the
  candidate Git SHA and package SHA-256 above, and match the Steamworks candidate
  when assigned. Record the check, OS, input and outcome with every evidence item.
- [ ] Use a disposable OS profile; copy its save directory before fault tests.
  Locate `pocket_circuit_save.json` and `.bak` using
  [Steam Cloud save paths](steam-release.md#steam-cloud-save). Close the game
  before editing or restoring save fixtures; retain originals outside that directory.
- [ ] Record the full source/export/package gate result for this exact candidate;
  both Windows and Linux exports and their checksums must pass.

The packaged release smoke is championship-only and forces a finish; it does NOT
certify the Run. Complete the Run checks below in the packaged candidate.

## Save and championship

- [ ] Remove only the disposable profile's saves; launch to title and start a new
  championship. Only Rustbug is initially unlocked.
- [ ] Restart the process and Continue; event points, unlocks, selected vehicle,
  settings and ending state match the saved state.
- [ ] Complete all nine events below. Check best-finish points 10/7/5/3, the
  10-point next-event and 20-point rival unlocks, and no points lost on retry.
- [ ] Win each act and verify Pinbolt, Scrapjaw and Flicker unlock in order.
  Complete the ending, then replay every completed event with an unlocked car.
- [ ] Restart before acknowledging the ending; the ending returns. Continue past
  it, restart again and verify the acknowledgment persists.
- [ ] With a valid `.bak`, corrupt the primary save and relaunch; the validated
  backup restores championship progress without blocking title.
- [ ] Corrupt both disposable saves and relaunch; defaults load safely. Restore
  the fixtures and repeat with a missing primary save and valid backup.
- [ ] Load a newer-version save fixture; record its before/after checksum. The
  save stays untouched, read-only state is visible and New Championship is
  disabled. PLAY may open a Run, but writes fail visibly and countdown cannot start.

## Championship events

For each box: drive the event; check unlock, intro, countdown, ordered checkpoints,
lap count, AI finish/DNF behavior, results, retry and return. Check reverse-route
grid orientation and recovery where applicable. Record player and AI completion.

- [ ] Crumb Rush (`kitchen_crumb_rush`): Kitchen, four cars, two laps.
- [ ] Mug Run (`kitchen_mug_run`): Kitchen reverse, four cars, three laps.
- [ ] The Clean Line (`kitchen_clean_line`): Kitchen rival duel, first to finish.
- [ ] Screw Loose (`workshop_screw_loose`): Workshop, four cars, two laps.
- [ ] Ruler Drop (`workshop_ruler_drop`): Workshop reverse, four cars, three laps.
- [ ] Heavy Metal (`workshop_heavy_metal`): Workshop rival duel, first to finish.
- [ ] Paper Trail (`office_paper_trail`): Office, four cars, two laps.
- [ ] Keyboard Cut (`office_keyboard_cut`): Office reverse, four cars, three laps.
- [ ] Last Light Grand Final (`office_last_light`): Office, four cars, four laps.

## Run start, routes and persistence

- [ ] On a fresh profile choose PLAY; start the Run, complete its intro/controls
  and reach the board with a generated compact or buggy.
- [ ] Restart and choose PLAY; resume the same seed, act, stop, points, current
  car, per-car wear, held/fitted parts, tow/nitro counts, haul and pending offer.
- [ ] Inspect a reachable stop's route, opponents, reward and cost; Back without
  travelling, then reopen and confirm with mouse, keyboard and controller.
- [ ] At each unused van, bench, lockup and errand, Back and restart; reopen it
  until used or a child route is taken. A used action cannot repeat; after moving
  on, the previous stop cannot reopen.
- [ ] Visit different stops; verify their room, circuit and direction. Restart
  at the same stop and verify its circuit and direction are unchanged.
- [ ] Cancel loading before countdown; the race remains available at no cost.
- [ ] Quit after countdown starts; resume to one last-place DNF and its points/
  wear consequences, with no retry. Repeat using a full process exit and restart;
  restart once more to confirm the DNF is not applied twice.
- [ ] Load malformed current-run node, act, edge and nested-value fixtures;
  recover safely before showing the board, preserving unrelated championship
  progress and garage data. Record each fixture and result.
- [ ] Corrupt the primary with a valid Run backup, then test missing primary,
  then corrupt both. Relaunch each time; verify backup recovery or safe defaults
  without blocking title.

## Run races and night endings

- [ ] Drive six-car ordinary races to each finish position across recorded runs;
  verify 1st–6th pay exactly 6/4/3/2/1/0 points, once each.
- [ ] Finish third or worse and DNF in ordinary races; verify added wear. First
  and second do not receive that ordinary finish penalty.
- [ ] Win an optional one-on-one rival duel; receive 6 points and a car offer.
- [ ] Lose optional duels with at least 10 points and with insufficient points;
  lose up to 10 points and receive wear only for insufficient funds, not the
  ordinary-race finish penalty. Verify each displayed consequence.
- [ ] Win the first two mandatory six-car act rivals; advance one act each time,
  with the intermediate car offer preserved across restart.
- [ ] Win the three-lap Basement finale; reach sunrise victory without an extra
  offer screen. Record player completion and the corresponding AI completion
  evidence for six-car races, duels and the finale.
- [ ] Lose an act rival by finishing below first while holding a tow; the night
  ends rather than spending the tow to advance.
- [ ] DNF an act rival after countdown, then restart; the night ends once with
  the act-rival defeat, not a replay or NO ACTIVE RUN.
- [ ] Wear out a car with no tow; the night ends with the car-failure verdict.
- [ ] At both victory and defeat, open VIEW GARAGE; only collection-safe won
  cars transfer once, fitted Run parts do not transfer, and the ended Run clears
  from the save. Restart and verify the collection and title remain correct.

## Run stop actions and tow recovery

Use separate visits/runs for mutually exclusive choices; record affordability,
points/items before and after, and persistence after restart for each choice.

- [ ] At a parts van buy a named part for its listed price; it enters held parts
  once and no second purchase/action is available that visit.
- [ ] At separate vans buy one tow for 10 points and one nitro for 5 points;
  each spends its price once and adds the named consumable. Use nitro in a race
  and verify one charge is consumed.
- [ ] Try each van purchase and ransom without enough points; no charge, item
  or consumed visit. Reopen the stop and verify it remains usable.
- [ ] At a bench repair a worn car fully; repair consumes the visit's one action.
- [ ] At another bench fit a held part; consume the part and apply its stated
  upside/downside in the next race. Repair is unavailable at the used bench.
- [ ] At another bench swap to an owned available car; the next race uses it and
  each car retains its own wear. No second bench action is available.
- [ ] At separate lockups choose DRIVE IT and SEND IT HOME; the free car is
  available once per act, without chase or points cost. DRIVE IT changes the
  current car; SEND IT HOME makes the won car collection-safe.
- [ ] At separate errands choose pay, tune-up and tow; receive exactly 6 points,
  the displayed seeded wear repair, or one tow respectively. Each visit resolves once.
- [ ] Hold a tow, wear out the car and verify immediate repair and one tow spent,
  without moving to a different map node or ending the night. Restart before
  the next bench and verify recovery and the pending bench cost persist.
- [ ] Reach that next bench; its action is already consumed by the tow. Attempt
  repair, fitting, swapping and banking; none grants an extra action. At a later
  bench an ordinary action is available again.

## Run offers, chase and collection

- [ ] On a robbed-driver offer choose RACE IT NOW with a same-band spare
  available; switch to the won car, keep the points, carry it unbanked and trigger
  pursuit on the next hot connector. Without a spare, the choice is unavailable.
- [ ] On another robbed-driver offer choose SEND IT AHEAD; switch to the car,
  spend exactly that win's points, keep it unbanked and travel without pursuit.
- [ ] On another offer choose SEND IT HOME; retain the current car and points,
  make the won car collection-safe and verify it survives a later night loss.
- [ ] Escape a chase through traffic and cross the finish; ARRIVED reaches the
  destination and banks the haul once. Continue to the stop; restart and verify
  collection safety persists.
- [ ] Allow capture: stay within two car widths in the same route section with
  clear sight for 1500 ms continuously; verify CAUGHT and impounded haul. Record
  timed video. Break range, section or sight before the threshold in separate
  attempts; exposure resets and does not accumulate across interruptions.
- [ ] Evade capture without finishing for 180 seconds; rescue stops the pursuer
  but does not arrive, end the drive or bank the haul. Continue to the finish;
  verify ARRIVED after rescue and no duplicate result. Record timed video.
- [ ] Carry multiple unbanked cars into capture; all carried haul becomes
  impounded, while already safe cars stay safe.
- [ ] At a van ransom one impounded car for 10 points; it becomes collection-safe,
  the visit is consumed and the car cannot be ransomed twice. Restart and verify.
- [ ] At a bench bank carried haul; all carried cars become collection-safe and
  the bench action is consumed. Restart and verify safety persists.
- [ ] Carry haul into an act-rival resolution; verify it banks. On an intermediate
  win the newly offered rival car still needs its own offer decision.
- [ ] End a night with unbanked haul; record the IDs and verify those cars are
  absent from the collection after restart.
- [ ] End another night with impounded cars; record the IDs and verify those cars
  are absent from the collection after restart.
- [ ] Save at an unanswered car offer and close the game. In a copied disposable
  save fixture set `current_run.failed` to `true`, leaving `pending_offer`
  unchanged. Relaunch, choose PLAY then NEW RUN; record the offered ID and verify
  it never transfers. Sent-home, banked and ransomed cars transfer once; restart
  and start another Run to check for duplicate awards.

## Run failed writes

In the disposable profile's save directory, create a directory named
`pocket_circuit_save.json.tmp` to block temporary-file creation. Remove that
directory to restore writes. Do not replace or delete the primary or backup for
these checks. Record the exact injection point and save hashes for each attempt.

- [ ] Block writes before countdown; starting the race fails visibly and no
  countdown/driving starts. Restore writes, retry and start the race once.
- [ ] Block writes after countdown but before the result; the failed result
  write is visible. Restore writes and retry saving the existing outcome without
  duplicating points, wear, cars or purchases.
- [ ] Block writes immediately before ending the night; the ended Run stays
  visible with SAVE AGAIN, and NEW RUN cannot replace the unsaved night.
  Restore writes and select SAVE AGAIN; the outcome and collection
  transfer save together once, then restart and verify no duplicate awards.
- [ ] Repeat the failed countdown, result and night-end write cases with a full
  process restart before retrying. Recover the last durable state, settle any
  saved in-flight race once as DNF, and use SAVE AGAIN where offered. Verify no
  duplicated rewards, wear or collection transfer and no stuck title/board.

## Vehicles and controls

- [ ] Rustbug, Pinbolt, Scrapjaw and Flicker are selectable when unlocked,
  visually distinct and retain their stated handling tradeoffs.
- [ ] Using keyboard only, complete the Run win/loss/recovery matrix and the
  championship; operate title, intro, board, every stop/offer, garage, settings,
  event card, vehicle select, pause, results, endings and every race action.
- [ ] Repeat that full menu/action and playthrough pass with an Xbox-compatible
  controller. Record a PlayStation-style controller navigation pass when available.
- [ ] Check visible focus, consistent cancel/back, safe controller reconnect and
  simultaneous keyboard/controller input without double submission.

## Runtime presentation and options

- [ ] Pause during countdown and driving; time, racers, countdown and result
  changes freeze. Resume, championship retry, settings and abandon work; Run
  abandon cannot grant a retry.
- [ ] Hear menu/race music, engine, countdown, go, UI, drift, boost and impact
  cues once; Master/Music/SFX route correctly, music ducks and engine silences
  while paused, and loops do not stack between screens/races.
- [ ] Set Master, Music, SFX, Engine and Tyres volumes to mute, minimum and
  maximum in separate passes; restart and verify every setting persists.
- [ ] Toggle reduced camera shake and reduced motion separately; both persist
  after restart, preserve cues/content/focus and do not change race timing.
- [ ] Attempt to open the debug overlay in the release export; it is unavailable.
  No test screen, MCP component, server tool or release credential ships.
- [ ] Inspect forward/reverse obstacles and slippery zones in each room: calm
  clearance for obstacles and ordinary slippery zones, bounded corner water/
  debris leaving a driveable line, and no moving hazard.
- [ ] Open credits; every shipped font, image and audio asset has its license.

## Platform, offline and performance

- [ ] Windows x86_64 clean machine: install, first launch, saves, fullscreen,
  keyboard/controller playthroughs, suspend/resume and uninstall/reinstall save
  behavior; record the exact candidate and results.
- [ ] Linux x86_64 clean machine: executable permission, first launch, saves,
  fullscreen, keyboard/controller playthroughs and desktop-session behavior;
  record the exact candidate and results.
- [ ] Steam Deck native Linux depot: correct launch target, gamepad-only Run and
  championship, 1280x800 readability, suspend/resume and no mandatory keyboard
  prompt; record the exact candidate and results.
- [ ] Disable networking; start, continue and finish the Run and championship.
  No login, unavailable-online-mode prompt, premium currency, telemetry failure
  or network timeout appears.
- [ ] Drive every room theme, including Basement, and every vehicle through
  starts, obstacles, collisions, recovery, pause and results. Record average and
  worst observed frame rate/frame time; investigate sustained missed 60 Hz frames,
  hitches, runaway memory, audio breakup or input latency on target hardware.
- [ ] Sign the candidate record only after every required check passes on the
  recorded hash; link unresolved defects and leave the candidate blocked otherwise.

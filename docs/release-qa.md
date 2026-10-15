# Phase 1 Release QA

Record OS/build hash, hardware, input device, result, and defect link for every
run. Test the packaged release build, not only the editor project.

## Save and championship

- [ ] Fresh install reaches title and starts a new championship with only the
  Rustbug unlocked.
- [ ] Continue resumes exact event points, unlocks, selected vehicle, settings,
  and ending state after a full process restart.
- [ ] A valid `.bak` recovers when the primary save is corrupt.
- [ ] Corrupt primary and backup files fall back safely without blocking title;
  unsupported future save versions remain untouched.
- [ ] Completing the championship leaves all completed events replayable.

## Runs and the garage

- [ ] A fresh profile can start a run; YOUR RUN resumes its seed, act, stop,
  points, car, wear, held/fitted parts, and pending offer after a process restart.
- [ ] Select and confirm stops with mouse, keyboard, and controller. Opening
  races are playable; completed races cannot resolve twice or be retried.
- [ ] Loading cancellation leaves the race available. Quit or process exit after
  countdown settles one last-place DNF on resume, with its stated consequences.
- [ ] Each act reaches its mandatory rival; victory advances the act or ends the
  night. Boss loss and worn-out cars end the night with the correct outcome
  visible after saving, not NO ACTIVE RUN.
- [ ] Rival and lockup wins show DRIVE IT / KEEP. Both choices preserve the won
  car; DRIVE IT changes the next race's car. The garage receives winnings once
  when a run ends or is replaced, without adding fitted run parts.
- [ ] Van purchase spends the stated points once and grants its named part.
  Bench fitting consumes a held part and applies its upside and downside to the
  next race. Repair and fitting remain mutually exclusive per visit.
- [ ] Race wear, rival loss, full bench repair, and errand tune-up match their
  displayed costs and effects. Each errand resolves only once.
- [ ] Failed countdown/result/terminal writes show an unsaved state. Retry saves
  the existing outcome without duplicating points, wear, cars, or purchases.
  Repeat with a process restart after the failed write.
- [ ] Malformed current-run nodes, acts, edges, and nested values recover safely
  before displaying the board; valid unrelated progress and garage data survive.
- [ ] BACK/restart keeps each unused bench, van, lockup, or errand reopenable
  until choosing a child route. Used actions cannot repeat; after moving on,
  the previous stop cannot reopen.
- [ ] Different stops have their intended circuit identities and act rooms;
  restarting the same stop preserves its circuit and direction.

## All nine events

- [ ] Crumb Rush (`kitchen_crumb_rush`)
- [ ] Mug Run (`kitchen_mug_run`)
- [ ] The Clean Line (`kitchen_clean_line`)
- [ ] Screw Loose (`workshop_screw_loose`)
- [ ] Ruler Drop (`workshop_ruler_drop`)
- [ ] Heavy Metal (`workshop_heavy_metal`)
- [ ] Paper Trail (`office_paper_trail`)
- [ ] Keyboard Cut (`office_keyboard_cut`)
- [ ] Last Light Grand Final (`office_last_light`)

For each event, verify unlock rules, intro, countdown, legal checkpoint order,
laps, AI finish/DNF behavior, results, retry, return flow, and reverse-route
recovery where applicable.

## Vehicles and controls

- [ ] Rustbug, Pinbolt, Scrapjaw, and Flicker are selectable when unlocked,
  visually distinct, and preserve their stated handling tradeoffs.
- [ ] Keyboard completes every title, settings, map, vehicle-select, pause,
  results, ending, and race action without a mouse.
- [ ] An Xbox-compatible controller completes the same flow; repeat a navigation
  pass with a PlayStation-style controller when available.
- [ ] Focus is always visible, cancel/back is consistent, controller reconnect
  is safe, and simultaneous keyboard/controller input does not double-submit.

## Runtime presentation and options

- [ ] Pause freezes race time, racers, countdown, and results changes;
  resume, retry, settings, and abandon behave correctly.
- [ ] Menu/race music, engine, countdown, go, UI, drift, boost, and impact
  audio play once and route through Master/Music/SFX controls.
- [ ] Mute and minimum/maximum volume persist after restart.
- [ ] Reduced camera shake and reduced motion work independently, preserve all
  cues/content, and persist after restart.
- [ ] No debug overlay, test screen, MCP component, server tool, or release
  credential appears in the packaged build.

## Platform, offline, and performance

- [ ] Windows x86_64: clean install, first launch, save/write, fullscreen,
  keyboard, controller, suspend/resume, and uninstall/reinstall save behavior.
- [ ] Linux x86_64: executable permission, first launch, save/write, fullscreen,
  keyboard, controller, and common desktop-session behavior.
- [ ] Steam Deck: native Linux depot, correct launch target, gamepad-only flow,
  1280x800 readability, suspend/resume, and no mandatory keyboard prompt.
- [ ] Start and complete races with networking disabled. No login, unavailable
  online mode, premium currency, telemetry failure, or network timeout appears.
- [ ] Run every room theme and vehicle long enough to cover race start, obstacles,
  collisions, recovery, pause, and results. Record average and worst observed
  frame rate/frame time; investigate sustained missed 60 Hz frames, hitches,
  runaway memory, audio breakup, or input latency on target hardware.
- [ ] Verify the SHA-256 manifest before install and confirm the tested build hash
  matches the candidate assigned in Steamworks.

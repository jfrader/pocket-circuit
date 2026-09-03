# Audio Production Contract

This is the prototype gate for replacing the current procedural audio with compact production-ready music and sound effects. Do not ingest assets until each chosen file passes the quality and provenance checks below.

## Current Integration Facts

- Engine: Godot 4.7.2, main scene `res://scenes/boot/boot.tscn`, 1280x720 canvas-items stretch, mobile renderer.
- Current `AudioDirector` preloads WAV assets only from `res://assets/audio/`: `menu_loop`, `race_loop`, `engine_loop`, `countdown`, `go`, `ui_move`, `ui_confirm`, `drift`, `boost`, `impact`, and `hazard_warning`.
- Current runtime looping is WAV-specific: `_make_runtime_loop()` duplicates `AudioStreamWAV`, sets `LOOP_FORWARD`, `loop_begin = 0`, and `loop_end` to the decoded sample end.
- Current routing is one `MusicPlayer` on `Music`, one speed-reactive `EnginePlayer` on `SFX`, and six one-shot `SFXPlayer` instances on `SFX`.
- Current pause behavior ducks race music to `-9 dB` and silences the engine loop.
- Current tests require every listed asset to exist as non-empty `22.05 kHz` WAV, verify the fixed six-player SFX pool, reject unknown SFX names, and check the menu loop for mono import, useful RMS, no clipping, low DC offset, and a click-free seam.
- Design-spec audio priority is engine clarity, tire feedback, collision impact, boost, surface changes, hazard telegraph, then UI reward feedback.

## Music Deliverables

The human composer owns music composition, arrangement, mix, and master. No paid libraries, recognisable borrowed melodies, copyrighted game references, generative-AI music, or uncleared samples.

| File stem | Role | Scope | Brief |
|---|---|---|---|
| `menu_loop` | Title, garage, settings, championship map | Required | Warm toy-garage pulse, lower intensity than race, optimistic but not cozy-menu generic. Compact motif, light percussion, room for UI clicks. |
| `race_loop` | Standard race bed | Required | Energetic miniature tabletop racing, clear forward drive, playful tension, no pastiche of Micro Machines, Road Rash, Mario Kart, or chiptune stock loops. |
| `race_final_lap_layer` | Optional future intensity layer | Deferred until code supports it | Adds urgency without masking engine/tire feedback. Percussion or harmonic lift only; must layer over `race_loop` without phase mud. |
| `race_intro` | Optional race start sting | Deferred until code supports it | One-bar lift into countdown or green light; should not delay control. |
| `race_outro_win` / `race_outro_loss` | Optional results stingers | Deferred until code supports it | Short result punctuation, not a full jingle. Win is bright and earned; loss is light, not punitive. |

Technical delivery:

- Masters: 48 kHz, 24-bit WAV, stereo for music, no limiter overs that create inter-sample clipping.
- Game-ready exports: provide OGG Vorbis plus WAV reference for each cue. The later integrator decides final import format after tests are updated; do not remove WAV coverage until the code no longer casts loops to `AudioStreamWAV`.
- Current-compatibility fallback: `menu_loop.wav` and `race_loop.wav` must be mono or stereo-to-mono safe if used before the director is extended. If the tests still require `22.05 kHz` WAV, create downsampled temporary exports from the 48 kHz masters rather than composing at 22.05 kHz.
- Loop length: `menu_loop` 60-90 seconds; `race_loop` 90-150 seconds. The rejected build's 16-second menu loop proved that a short repeating phrase becomes fatiguing quickly, so neither production cue may return to its full opening arrangement in under 60 seconds.
- Arrangement variation: retain one memorable motif, but change percussion, register, harmony, or instrumentation every 8-16 bars. Keep scope compact by delivering two complete cues rather than many weak variants, not by shortening either cue into an obvious loop.
- Loop seam: supply renders whose loop region is the full file by default. First and last samples must meet cleanly; no click, DC jump, reverb pop, or cymbal tail cut. If a musical pickup needs an intro, deliver it as `race_intro` and keep `race_loop` as a standalone seamless bed.
- Loop points: Godot 4 WAV can use sample loop begin/end; current code assumes begin `0` and end at decoded sample end. Godot OGG usage should be whole-file seamless unless a later implementation explicitly handles `AudioStreamOggVorbis.loop_offset` and documents the offset in seconds.
- Tails: loop files must not contain a non-looping tail. Stingers/outros may ring out naturally, with silence trimmed after the tail drops below the noise floor.
- Loudness: music target `-18 LUFS integrated` with acceptable range `-20` to `-16 LUFS`; true peak at or below `-1 dBTP`; no audible clipping or pumping. Leave headroom because engine and SFX are gameplay-critical.
- Mix discipline: race music must remain readable at `-6 dB` under SFX and still feel musical when paused/ducked to `-9 dB`.

## Required SFX Cue List

Priorities control stealing when simultaneous voices exceed the current six-player pool. Prototype mix should assume one music loop, one engine loop, up to four high-priority gameplay one-shots, and up to two low-priority UI/ambience one-shots at once.

### Vehicle

| Cue | Status | Priority | Voices | Direction |
|---|---|---:|---:|---|
| `engine_loop` | Current required | Critical | 1 loop | Local player speed-reactive loop; clear pitch range, toy-scale engine identity, no fatiguing buzz. |
| `engine_loop_compact`, `engine_loop_muscle`, `engine_loop_buggy`, `engine_loop_coupe` | Future extension | Critical | 1 chosen loop | Family identities after one excellent base loop exists; same loudness and loop behavior. |
| `drift` | Current required | Critical | 2 | Tire scrub and grip loss; must communicate controllable slide, not white-noise hiss. |
| `boost` | Current required | High | 2 | Short propulsion burst with toy-racer sparkle; should cut through music without masking engine. |
| `tire_grip_scrub` | Future extension | High | 2 | Subtle cornering stress before drift; loop or short retrigger only if code supports it. |
| `surface_change` | Future extension | High | 2 | Tiny material accent for metal, wood, tile, carpet, or paper transitions. |

### Contact

| Cue | Status | Priority | Voices | Direction |
|---|---|---:|---:|---|
| `impact` | Current required | Critical | 3 | Scaled bump hit; crisp transient plus toy-body thump, not cinematic explosion. |
| `wall_scrape` | Future extension | High | 2 | Short scrape/rasp for grazing contact; avoid harsh broadband noise. |
| `hazard_hit` | Future extension | High | 2 | Distinct from wall impact; small environmental punishment without slapstick clutter. |
| `pickup_collect` | Future extension | Normal | 2 | Positive pickup tick, if pickups enter the prototype. |

### Race State

| Cue | Status | Priority | Voices | Direction |
|---|---|---:|---:|---|
| `countdown` | Current required | High | 1 | Three repeated pips; timing clarity beats musical flourish. |
| `go` | Current required | Critical | 1 | Green-light accent with immediate attack and short tail. |
| `hazard_warning` | Current required | High | 1 | Telegraph, not alarm fatigue; audible under engine and music. |
| `lap_complete` | Future extension | Normal | 1 | Short confirmation; should not sound like final victory. |
| `final_lap` | Future extension | High | 1 | Urgent but compact; pair with optional final-lap music layer later. |
| `race_finish_win`, `race_finish_loss` | Future extension | Normal | 1 | Results punctuation, not long music. |

### UI

| Cue | Status | Priority | Voices | Direction |
|---|---|---:|---:|---|
| `ui_move` | Current required | Low | 2 | Focus movement tick; quiet, non-piercing, frequent-use safe. |
| `ui_confirm` | Current required | Low | 2 | Positive press/selection; distinct from `ui_move`. |
| `ui_back` | Future extension | Low | 1 | Gentle reverse/cancel cue. |
| `ui_error` | Future extension | Normal | 1 | Soft blocked-action feedback; avoid buzzer annoyance. |
| `reward_small` | Future extension | Normal | 2 | Lightweight post-race reward feedback. |

### Ambience

| Cue | Status | Priority | Voices | Direction |
|---|---|---:|---:|---|
| `ambience_kitchen_loop` | Future extension | Low | 1 loop | Very quiet room tone and miniature scale; no identifiable appliance brands or speech. |
| `ambience_workshop_loop` | Future extension | Low | 1 loop | Gentle workshop air, distant tiny rattles; must not mask engine/tire cues. |
| `ambience_office_loop` | Future extension | Low | 1 loop | Soft office air and paper texture; no keyboard chatter that reads as UI. |

## Recommended Sourcing Strategy

Use original composition for music. For SFX, first audition from the shortlist below, then edit/layer in-house. Keep source choices minimal: one CC0 source for UI/arcade impacts, one professional source for realistic foley/vehicle texture only if needed.

Verified facts, accessed 2026-08-28:

| Source | Exact URL | License facts verified | Recommended use |
|---|---|---|---|
| Kenney Interface Sounds | https://kenney.nl/assets/interface-sounds | Page lists Audio category, 100 files, Creative Commons CC0, direct ZIP available. CC0 deed allows copy, modification, distribution, and commercial use without asking permission. | Primary source for `ui_move`, `ui_confirm`, `ui_back`, `ui_error` candidates. |
| Kenney UI Audio | https://kenney.nl/assets/ui-audio | Page lists Audio category, 50 files, Creative Commons CC0, direct ZIP available. | Secondary UI audition pool if Interface Sounds is too samey. |
| Kenney Impact Sounds | https://kenney.nl/assets/impact-sounds | Page lists Audio category, 130 files, Creative Commons CC0, direct ZIP available. | Primary source for toy-scale `impact`, `hazard_hit`, `pickup_collect`, and small contact layers. |
| Kenney Sci-fi Sounds | https://kenney.nl/assets/sci-fi-sounds | Page lists Audio category, 70 files, Creative Commons CC0, direct ZIP available. | Audition sparingly for `boost`, `hazard_warning`, and synthetic engine layers; reject if it feels space-game generic. |
| Sonniss GameAudioGDC archive | https://sonniss.com/gameaudiogdc/ | Page states sounds are royalty-free, commercially usable, no attribution required, unlimited projects, editable, media-production only, and AI/ML training prohibited. License page grants worldwide non-exclusive royalty-free use and modification for personal/commercial projects without attribution, synchronized in games and other media. | Professional fallback for tire scrubs, wall scrapes, tiny impacts, room-tone ambiences, and non-stylized foley layers when Kenney lacks quality. |
| Sonniss GameAudioGDC license | https://sonniss.com/gdc-bundle-license/ | Version 2.0 shown effective 2026-08-27; redistribution as standalone SFX or SFX libraries is prohibited; finished games are allowed. | Save the exact license text/version at ingestion time if any Sonniss file is used. |

Recommendations and cautions:

- Prefer Kenney CC0 for final included SFX whenever quality is good enough because attribution and redistribution obligations are simplest.
- Use Sonniss only for production-quality vehicle/contact/ambience gaps. It is not CC0; its license is suitable for a finished game but unsuitable for redistributing raw files in a separate asset pack or training dataset.
- Reject Freesound unless a future pass validates each individual sound ID, exact license, author, and download terms. The site contains mixed licenses and often requires attribution or an account.
- Reject Pixabay/Mixkit/Zapsplat-style broad libraries for this gate unless a future legal review accepts their terms. They are not needed for the minimal prototype and add policy/download/provenance ambiguity.
- Reject sources whose license is noncommercial, share-alike, attribution-heavy for dozens of one-off authors, unclear about commercial games, download-gated behind account approval, or marked/marketed as AI-generated.

Validation performed 2026-08-28:

- Web pages fetched and read for the listed Kenney packs, Creative Commons CC0 deed, Sonniss GameAudioGDC archive, and Sonniss GameAudioGDC license.
- HTTP HEAD checks returned `200` for the Kenney pack pages and direct ZIP links for Interface Sounds, UI Audio, Impact Sounds, and Sci-fi Sounds without downloading assets.
- Sonniss pages were readable through web fetch, but direct `curl -I` checks returned a Cloudflare `403` challenge. Treat Sonniss access as browser-verifiable but not CLI-verified in this pass.

## Audition And Rejection Checklist

Every candidate must pass in-game audition, not just solo playback.

- Gameplay information first: engine speed, drift state, impact severity, boost, and hazard telegraphs must be immediately understandable at race speed.
- No painful procedural feel: reject obvious raw sine beeps, static oscillator loops, unvaried half-second pulses, aliasing, zipper noise, harsh white noise, and DC-offset clicks.
- No cheap placeholder feel: reject sounds that resemble default UI packs, meme sounds, stock sci-fi lasers, phone notification tones, casino jingles, or asset-store trailer whooshes.
- Toy-scale realism: sounds should imply tiny vehicles on household surfaces, not full-size motorsport, explosions, firearms, or cinematic metal destruction.
- Mix fit: audition with music, engine, drift, boost, and impact stacked. Critical cues must cut through without simply being louder.
- Frequency spacing: reserve low-mid body for engine/contact, high transient detail for UI/countdown, and airy highs for boost/hazard. Reject cues that mask tire feedback.
- Loudness: one-shots should normally peak between `-6 dBFS` and `-1 dBFS` after editing, with no clipping. Frequent UI cues should sit lower than gameplay cues.
- Variation: repeated cues need at least two acceptable alternates or pitch/volume variation later. Do not add alternates until the director supports them.
- Loop quality: looped engine and ambience must run for two minutes without fatigue, clicks, thumps, or obvious periodic resets.
- Legal cleanliness: reject any cue with unclear author, missing license, noncommercial terms, mandatory attribution that would clutter notices, third-party voices, recognizable brands, copyrighted vehicle recordings packaged under unclear rights, or AI-generation flags.

## Future Integration Seam

No implementation is part of this document. Later work should replace or extend these seams deliberately:

- `scripts/audio/audio_director.gd` currently hardcodes preload constants and a single `SFX_STREAMS` map. Production ingestion should move cue metadata into a resource/table or extend the map with documented priorities and optional alternates.
- OGG music support requires changing `MENU_LOOP`, `RACE_LOOP`, and `_make_runtime_loop()` assumptions or adding a format-specific loop setup path. Do not simply swap in `.ogg` while the code casts loops to `AudioStreamWAV`.
- The SFX pool is fixed at six and steals round-robin without priority. Before adding ambience, surface loops, alternates, or frequent tire scrub, add priority-aware playback or separate loop players.
- Vehicle-family engine identity requires a way to choose an engine loop from vehicle stats/family. Current `set_local_vehicle()` only reads `stats.max_speed` and applies pitch/volume to one loop.
- Dynamic final-lap music requires a second music/layer player or an explicit transition system. Current music switches whole streams and does not layer.
- Tests will need updates when production assets change format, sample rate, stereo mode, cue count, or loop metadata. Preserve the existing tests' intent: assets load, loops are click-free, bus setup is idempotent, music players do not stack, unknown SFX are rejected, and the mix avoids clipping/flat repetition.

## Provenance And Notices Obligations

Before any asset ingestion:

- Record every selected cue in `ASSET_PROVENANCE.md` with original source URL, pack name, source filename, author/vendor, license name/version, access date, transformation steps, final project path, and release status.
- Add license text or required notice to `THIRD_PARTY_NOTICES.md` for every non-first-party source before release. CC0 sources still need a provenance record; attribution is not required, but documenting the source is required.
- Preserve a local review note or manifest for rejected candidates so the same weak sources are not re-auditioned repeatedly.
- If Sonniss is used, include the exact GameAudioGDC license version/date that applied on download day and note the media-production-only and no-standalone-redistribution restrictions.
- Update `assets/audio/LICENSE.md` once third-party audio replaces or augments the original procedural WAVs; the current statement says the directory contains only mathematical waveform/noise assets and would become false.
- Keep masters outside the game export unless intentionally shipped. Commit only game-ready assets and license/provenance material needed for release review.

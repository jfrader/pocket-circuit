# Promo video kit

Makes a gameplay promo like `pocket_circuit_public_alpha_promo.mp4`
(2026-10-06, 58.9 s, 1080p30, about -14 LUFS): real game footage recorded with
Godot Movie Maker, cut on the beat of a score the game generated, with title
cards, a wall of 108 generated circuits and a wall of 104 generated cars.

Nothing here ships: release exports exclude `tools/**`, and the capture
director is registered only inside a throwaway capture worktree.

## Needs

`godot` 4.7.2, `xvfb-run`, `ffmpeg`, `node`, `python3`. Edit dependencies:

```bash
cd tools/promo/edit && npm install && npx playwright install chromium
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```

Everything is written under `$PROMO_OUT` (default `/tmp/opencode/pc-promo`).
A full capture takes about 25 GB of PNG frames there.

## Make one

```bash
# 1. Capture worktree (detached, autoload + 2560x1440 window + Gamestruments).
tools/promo/setup_capture_worktree.sh /tmp/opencode/pc-capture origin/dev

# 2. Record every take, three at a time (about 45 minutes).
/tmp/opencode/pc-capture/tools/promo/capture_all.sh

# 3. Circuit routes and cars for the two walls (seconds each).
cd /tmp/opencode/pc-capture
PROMO_OUT=/tmp/opencode/pc-promo godot --path . --headless --script res://tools/promo/export_routes.gd
PROMO_OUT=/tmp/opencode/pc-promo godot --path . --headless --script res://tools/promo/export_cars.gd

# 4. Tempo, downbeat and race-start frames; contact sheets for picking shots.
cd tools/promo/edit && .venv/bin/python analyze.py

# 5. Cards and walls at the measured tempo, then the edit.
node render_cards.js
python3 build.py
```

The video lands at `$PROMO_OUT/pocket_circuit_public_alpha_promo.mp4`. Remove
the capture worktree afterwards (`setup_capture_worktree.sh` prints the
command).

## After a recapture

Takes are deterministic per seed but not frame-identical once the game
changes. Open `$PROMO_OUT/sheets/<take>.png` (center crop every 20 frames,
frame numbers in red) and update the source frames in the cut list in
`edit/build.py`. Each `seg(length, take, first_frame, zoom)` line is one shot;
lengths are in beats and bars, so the cut stays on the music.

Check before sharing: loudness with
`ffmpeg -i <video> -af ebur128=peak=true -f null -` (adjust `MASTER_GAIN` to
land near -14 LUFS) and a contact sheet of the whole cut.

## Director arguments

Passed after `--` to `shot.sh` (see `capture_all.sh` for the real takes).

| Argument | Effect |
|---|---|
| `--promo-shot=race\|strip\|title\|garage\|flip` | What to record. `garage` cycles the 8 cars; `flip` shows a new Discovery circuit every `--dwell` seconds. |
| `--theme=` `--seed=` `--vehicle=` `--tier=` `--reverse=1` `--theme-b=` | The circuit. Reuse a seed from a take's `log.txt` (`PROMO start`) to get the same circuit again. |
| `--seconds=` | Race seconds to record after GO (other shots: total seconds). |
| `--boss=1` | Aggressive driver: `boss_ai.gd` tuning plus a handbrake flick at each braking zone and boost on straights. Tune with `--ai-<key>=` and `--b-hold= --b-brake= --b-steer= --b-cool=`. |
| `--difficulty=sunday_drive` | Rival tier, so the boss driver passes them. |
| `--look-seed=N` | Random palette, livery, wheels and spoiler per car (`--vary=0` keeps catalog looks). |
| `--silence=boost,pursuit` | Drops those generated one-shots (turbo, Strip chase pulse). |
| `--mute=Music` | Mutes audio buses; record the score separately with `--mute=SFX,Engine,Tyre`. |
| `--metrics=1` | Prints progress, position, drift, boost and hits (used by `bench.sh`). |

## Tuning the driving

`bench.sh` runs a headless race in about 20 seconds and prints one metrics
line. Run variants in parallel and compare progress (`prog`), position, drift
and boost seconds and hits:

```bash
cd /tmp/opencode/pc-capture
tools/promo/bench.sh base --theme=kitchen --seed=274524 --difficulty=sunday_drive &
tools/promo/bench.sh boss --theme=kitchen --seed=274524 --difficulty=sunday_drive --boss=1 &
tools/promo/bench.sh long --theme=kitchen --seed=274524 --difficulty=sunday_drive --boss=1 --b-hold=0.3 &
wait
```

On 2026-10-06 the 0.15 s flick won: longer holds crashed 10+ times a race.
Quick Race rolls a new rival lineup each run, so the same arguments land a
place or two apart; compare a few runs per variant.

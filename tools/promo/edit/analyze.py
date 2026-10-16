#!/usr/bin/env python3
"""Measures the captured takes so the edit can lock to them.

Writes $PROMO_OUT/analysis.json with the score's beat length and first groove
downbeat (shots/music/f.wav), plus the frame where each race take's clock starts
(read off the HUD timer), and draws a contact sheet per take into
$PROMO_OUT/sheets/ for picking moments.

    python analyze.py [--groove-after SECONDS]
"""
import argparse, json, os, subprocess
import numpy as np
import librosa

OUT = os.environ.get("PROMO_OUT", "/tmp/opencode/pc-promo")
SHOTS = f"{OUT}/shots"
RACE_TAKES = ["kitchen", "workshop", "office", "reverse", "strip", "drift"]
# HUD race clock digits at 2560x1440 (top-right plate).
TIMER_CROP = "crop=120:60:2390:110"
TIMER_W, TIMER_H = 120, 60
HUD_BRIGHTNESS = 170
CLOCK_CHANGE = 3
SCAN_FROM, SCAN_FRAMES = 200, 500
SHEET_EVERY = 20


def score_timing(groove_after):
    y, sr = librosa.load(f"{SHOTS}/music/f.wav", sr=22050, mono=True)
    _, frames = librosa.beat.beat_track(y=y, sr=sr)
    beats = librosa.frames_to_time(frames, sr=sr)
    steady = beats[(beats > groove_after) & (beats < groove_after + 40)]
    slope, intercept = np.polyfit(np.arange(len(steady)), steady, 1)
    return float(slope), float(intercept)


def clock_start(take):
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-start_number", str(SCAN_FROM), "-framerate", "30",
                          "-i", f"{SHOTS}/{take}/f%08d.png", "-frames:v", str(SCAN_FRAMES),
                          "-vf", f"{TIMER_CROP},format=gray", "-f", "rawvideo", "-"], capture_output=True).stdout
    frames = np.frombuffer(raw, np.uint8).reshape(-1, TIMER_H, TIMER_W).astype(int)
    hud = next(i for i in range(len(frames)) if frames[i].mean() > HUD_BRIGHTNESS)
    go = next(i for i in range(hud + 1, len(frames)) if np.abs(frames[i] - frames[hud + 2]).mean() > CLOCK_CHANGE)
    return SCAN_FROM + go


def contact_sheet(take):
    os.makedirs(f"{OUT}/sheets", exist_ok=True)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", "30", "-i", f"{SHOTS}/{take}/f%08d.png",
                    "-vf", f"select='not(mod(n\\,{SHEET_EVERY}))',crop=1422:800:569:320,scale=280:-1,"
                           f"drawtext=text='%{{eif\\:n*{SHEET_EVERY}\\:d}}':x=4:y=4:fontsize=18:fontcolor=red,tile=9x9",
                    "-frames:v", "1", f"{OUT}/sheets/{take}.png"], check=True)


def main():
    parser = argparse.ArgumentParser()
    # Beat tracking finds the beats but not which one starts the bar. 28.0 s is
    # just before the first full-groove downbeat of the seed-707143 score that
    # capture_all.sh records; for another score, listen and pass your own.
    parser.add_argument("--groove-after", type=float, default=28.0,
                        help="a time just before the score's first full-groove downbeat")
    args = parser.parse_args()
    beat, downbeat = score_timing(args.groove_after)
    takes = [t for t in RACE_TAKES if os.path.isdir(f"{SHOTS}/{t}")]
    analysis = {"beat": beat, "score_drop": downbeat, "go": {t: clock_start(t) for t in takes}}
    for take in takes:
        contact_sheet(take)
    with open(f"{OUT}/analysis.json", "w") as fh:
        json.dump(analysis, fh, indent=2)
    print(json.dumps(analysis, indent=2))
    print(f"{60 / beat:.2f} BPM; sheets in {OUT}/sheets")


if __name__ == "__main__":
    main()

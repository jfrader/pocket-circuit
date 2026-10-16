#!/usr/bin/env python3
"""Pocket Circuit 'Public Alpha Testing' promo: beat-locked edit of Movie Maker captures.

Reads takes from $PROMO_OUT/shots, card frames from $PROMO_OUT/cards and the
timings analyze.py wrote to $PROMO_OUT/analysis.json. The cut list below holds
the 2026-10-06 picks; after a recapture, pick new source frames from the
contact sheets in $PROMO_OUT/sheets.
"""
import json, os, subprocess, sys

ROOT = os.environ.get("PROMO_OUT", "/tmp/opencode/pc-promo")
SHOTS = f"{ROOT}/shots"
CARDS = f"{ROOT}/cards"
WORK = f"{ROOT}/build"
FPS = 30
with open(f"{ROOT}/analysis.json") as fh:
    ANALYSIS = json.load(fh)
BEAT = ANALYSIS["beat"]               # fitted to the captured race score's beats
BAR = 4 * BEAT
SCORE_DROP = ANALYSIS["score_drop"]   # first groove downbeat in the captured score
GO = ANALYSIS["go"]                   # frame where each race take's clock starts
COUNTDOWN_FRAMES = 59                 # the HUD and 3-2-1 appear this many frames before GO
DROP = 4 * BAR              # the drop lands four bars into the promo
MUSIC_IN = SCORE_DROP - DROP
GROOVE_BARS = 11            # score bars before the build starts
REPEAT_BARS = 2             # groove bars repeated so the car wall fits before the build
BUILD_BARS = 8              # build up to the hit where the score falls back to the sparse grid
END_HIT = DROP + (GROOVE_BARS + REPEAT_BARS + BUILD_BARS) * BAR
CARD_LEN = 2 * BAR
END_LEN = 5.6
TOTAL = END_HIT + CARD_LEN + END_LEN
MASTER_GAIN = float(os.environ.get("MASTER_GAIN", "-5.2"))
os.makedirs(WORK, exist_ok=True)

def fr(t):
    return round(t * FPS)

cuts = []   # (t_start, t_end, shot, src_frame, zoom, sfx_gain, crop_xy)
t = 0.0
def seg(length, shot, frame, zoom=1.0, sfx=1.0, crop_xy=None):
    global t
    cuts.append((t, t + length, shot, frame, zoom, sfx, crop_xy))
    t += length

# Intro: garage, one car per beat (car i is selected at 2 s + 1.15 s * i in the garage capture)
for i in range(8):
    seg(BEAT, "garage", fr(2.0 + 1.15 * i) + 12, 1.0, 0.0)
seg(DROP - COUNTDOWN_FRAMES / FPS - t, "title", 150, 1.0, 0.0)
seg(DROP - t, "kitchen", GO["kitchen"] - COUNTDOWN_FRAMES, 1.6)              # 3-2-1, GO lands on the drop
seg(2 * BAR, "kitchen", GO["kitchen"], 1.0)                      # bars 0-1: launch under the logo
for shot, f, z in [("workshop", 380, 1.3), ("office", 500, 1.3), ("reverse", 440, 1.3), ("kitchen", 408, 1.5)]:
    seg(BAR, shot, f, z)                                         # bars 2-5: tiny cars, big rooms
for k in range(4):                                               # bar 6: in-game Discovery previews
    seg(BEAT, "flip", 60 + 75 * (k + 1) - 16, 1.3, 0.0, crop_xy=(0, 0))
seg(2 * BAR, "wall", 0, 1.0, 0.0)                                # bars 7-8: 108 generated circuits
for shot, f in [("office", 600), ("reverse", 500)]:             # bar 9
    seg(2 * BEAT, shot, f, 1.2)
seg(BAR, "drift", 740, 1.8)                                  # bars 10-11: drift
seg(BAR, "kitchen", 800, 1.7)
seg(2 * BAR, "office", 700, 1.1)                                # bars 12-13: own score
seg(BAR, "strip", 480, 1.3)                                      # bars 14-15: quick strip
seg(BAR, "strip", 920, 1.3)
seg(2 * BAR, "carwall", 0, 1.0, 0.0)                             # bars 16-17: 104 generated cars
for shot, f in [("kitchen", 424), ("office", 540), ("reverse", 460), ("drift", 600)]:
    seg(2 * BEAT, shot, f, 1.8)                                  # bars 18-19: rivals
for shot, f in [("office", 1280), ("kitchen", 830), ("drift", 620), ("strip", 700)]:
    seg(BEAT, shot, f, 1.7)                                      # bar 20: one cut per beat
assert abs(t - END_HIT) < 0.02, (t, END_HIT)

cards = [("logo", 0), ("tiny", 2), ("drift", 10), ("music", 12), ("strip", 14), ("rivals", 18)]
cards = [(name, DROP + bar * BAR) for name, bar in cards]
IMAGE_SEQUENCES = {"wall": f"{CARDS}/wall/%04d.png", "carwall": f"{CARDS}/carwall/%04d.png"}

def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit(" ".join(cmd) + "\n" + r.stderr[-3000:])

# 1. Render each segment to an intermediate with its own game SFX.
parts = []
for i, (a, b, shot, f, zoom, sfx, crop_xy) in enumerate(cuts):
    n = fr(b) - fr(a)
    out = f"{WORK}/seg{i:02d}.mov"
    w, h = round(2560 / zoom / 2) * 2, round(1440 / zoom / 2) * 2
    cx, cy = crop_xy if crop_xy else (f"(iw-{w})/2", f"(ih-{h})/2")
    vf = f"crop={w}:{h}:{cx}:{cy},scale=1920:1080:flags=lanczos,setsar=1,fps={FPS}"
    if shot == "title":   # slow push-in on the title screen
        vf = f"zoompan=z='1+0.06*on/{n}':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d=1:s=1920x1080:fps={FPS},setsar=1"
    if shot in IMAGE_SEQUENCES:
        frames, audio = IMAGE_SEQUENCES[shot], ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"]
        vf = f"scale=1920:1080,setsar=1,fps={FPS}"
    else:
        frames, audio = f"{SHOTS}/{shot}/f%08d.png", ["-ss", f"{f / FPS:.4f}", "-i", f"{SHOTS}/{shot}/f.wav"]
    run(["ffmpeg", "-y", "-loglevel", "error", "-start_number", str(f), "-framerate", str(FPS),
         "-i", frames, *audio, "-frames:v", str(n), "-vf", vf,
         "-af", f"atrim=0:{n / FPS:.4f},apad=whole_dur={n / FPS:.4f},volume={sfx},afade=t=in:d=0.01,afade=t=out:st={n / FPS - 0.01:.4f}:d=0.01,aformat=sample_rates=48000:channel_layouts=stereo",
         "-c:v", "prores_ks", "-profile:v", "1", "-c:a", "pcm_s16le", out])
    parts.append(out)
    print(f"seg {i:02d} {a:6.2f}-{b:6.2f} {shot:9s} f{f} z{zoom} frames {n}")

with open(f"{WORK}/list.txt", "w") as fh:
    fh.writelines(f"file '{p}'\n" for p in parts)
run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", f"{WORK}/list.txt",
     "-c", "copy", f"{WORK}/body.mov"])

# 2. Score bed: intro + groove, the last two groove bars again, then the build and the hit.
groove_end = SCORE_DROP + GROOVE_BARS * BAR
repeat_in = groove_end - REPEAT_BARS * BAR
score = f"{SHOTS}/music/f.wav"
bed_parts = [(MUSIC_IN, groove_end), (repeat_in, groove_end), (groove_end, groove_end + TOTAL)]
fc = [f"[0:a]atrim={a:.4f}:{b:.4f},asetpts=PTS-STARTPTS,afade=t=in:d=0.008,afade=t=out:st={b - a - 0.008:.4f}:d=0.008[m{k}]"
      for k, (a, b) in enumerate(bed_parts)]
fc.append("[m0][m1][m2]concat=n=3:v=0:a=1[bed]")
run(["ffmpeg", "-y", "-loglevel", "error", "-i", score, "-filter_complex", ";".join(fc), "-map", "[bed]",
     "-t", f"{TOTAL:.3f}", "-c:a", "pcm_s16le", f"{WORK}/bed.wav"])

# 3. Overlay cards, append the coming-next and end cards, mix the score under the game SFX.
inputs = ["-i", f"{WORK}/body.mov"]
for name, _ in cards:
    inputs += ["-framerate", str(FPS), "-i", f"{CARDS}/{name}/%04d.png"]
inputs += ["-framerate", str(FPS), "-i", f"{CARDS}/next/%04d.png"]
inputs += ["-framerate", str(FPS), "-i", f"{CARDS}/end/%04d.png"]
inputs += ["-i", f"{WORK}/bed.wav"]
fc = []
prev = "[0:v]"
for k, (name, start) in enumerate(cards, 1):
    fc.append(f"[{k}:v]setpts=PTS+{start:.4f}/TB[c{k}]")
    fc.append(f"{prev}[c{k}]overlay=eof_action=pass:enable='between(t,{start:.3f},{start + CARD_LEN:.3f})'[v{k}]")
    prev = f"[v{k}]"
e = len(cards) + 1
fc.append(f"[{e}:v]format=yuv420p,setsar=1,trim=end_frame={fr(END_HIT + CARD_LEN) - fr(END_HIT)}[nextv]")
fc.append(f"[{e + 1}:v]format=yuv420p,setsar=1[endv]")
fc.append(f"{prev}format=yuv420p[bodyv]")
fc.append("[bodyv][nextv][endv]concat=n=3:v=1:a=0,fade=t=in:st=0:d=0.25[vout]")
fc.append(f"[0:a]apad=whole_dur={TOTAL:.3f},volume=0.7[sfx]")
fc.append(f"[{e + 2}:a]aformat=sample_rates=48000:channel_layouts=stereo,afade=t=in:st=0:d=0.3,afade=t=out:st={TOTAL - 2.2:.3f}:d=2.2[mus]")
fc.append(f"[mus][sfx]amix=inputs=2:normalize=0,volume={MASTER_GAIN}dB,alimiter=limit=0.84[aout]")
out = f"{ROOT}/pocket_circuit_public_alpha_promo.mp4"
run(["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", ";".join(fc),
     "-map", "[vout]", "-map", "[aout]", "-t", f"{TOTAL:.3f}",
     "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", "-r", str(FPS),
     "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", out])
print("wrote", out, f"{TOTAL:.2f}s")

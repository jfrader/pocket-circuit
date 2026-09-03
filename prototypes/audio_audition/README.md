# Audio Audition Prototype

`PROTOTYPE / NOT SHIP AUDIO`

This is an isolated audition surface for **candidate** effects. Nothing here is an approved production asset, and none of these files may replace `assets/audio` until an explicit selection, in-game mix pass, production provenance update, and production test update are completed.

Launch the graphical runner from the repository root:

```sh
godot --path . --script res://prototypes/audio_audition/audio_audition.gd
```

The runner starts on `engine_loop` candidate A and remains silent until explicit input.

## Controls

- **Left / Right:** candidate A/B
- **Up / Down:** cue group
- **Space:** play or stop
- **R:** replay from the beginning
- **Escape:** quit

The runner uses exactly one `AudioStreamPlayer`. For engine playback it duplicates the loaded `AudioStreamOggVorbis` and enables looping only on that duplicate, so the imported source resource is never globally mutated.

## Verified sources and license

Verified and accessed 2026-08-28.

| Pack | Exact source page | Downloaded filename | SHA-256 |
|---|---|---|---|
| Kenney Interface Sounds 1.0 | https://kenney.nl/assets/interface-sounds | `kenney_interface-sounds.zip` | `f2193d072726d6758a5f7871b2dcc54dcce0d5c35c6f0a62f92549b327c81232` |
| Kenney Impact Sounds 1.0 | https://kenney.nl/assets/impact-sounds | `kenney_impact-sounds.zip` | `029d734af1582474edf3a694d1b0cebc97c1c152f2f39fa34d4c2bafc5de77f8` |
| Kenney Sci-Fi Sounds 1.0 | https://kenney.nl/assets/sci-fi-sounds | `kenney_sci-fi-sounds.zip` | `119340f351a5098ad814f78719438c0da355a9ce8a4c8a3af6a8d48aa3d49e04` |

The pack license files identify the works as **Creative Commons Zero (CC0)** and link to http://creativecommons.org/publicdomain/zero/1.0/. They state that the content is free for personal, educational, and commercial projects and that crediting Kenney is appreciated but not mandatory. CC0 permits copying, modification, and distribution, including commercial use, without asking permission. The preserved pack texts and their source note are in `LICENSE-KENNEY-CC0.txt`.

The source archives and extracted raw files remain outside the repository under `/tmp/opencode/audio-sources/`. Only the compact audition outputs are present here.

## Candidate map and audition criteria

| Group | A | B | Focus |
|---|---|---|---|
| `engine_loop` | `engineCircular_000.ogg` | `spaceEngineSmall_000.ogg` | Tiny-vehicle identity, pitch range, seam, fatigue |
| `countdown` | `select_003.ogg` | `select_004.ogg` | Repeated timing clarity, no shrillness |
| `go` | `confirmation_002.ogg` | `confirmation_003.ogg` | Immediate green-light distinction without masking launch |
| `ui_move` | `tick_004.ogg` | `select_001.ogg` | Frequent-use safety and clear separation from confirm |
| `ui_confirm` | `confirmation_001.ogg` | `confirmation_004.ogg` | Positive press without notification-jingle character |
| `drift` | `scratch_004.ogg` | `scratch_005.ogg` | Controllable tire scrub rather than hiss or damage |
| `boost` | shaped `thrusterFire_000.ogg` extract | shaped `thrusterFire_002.ogg` extract | Compact propulsion that does not read as a weapon |
| `impact` | `impactTin_medium_000` + `impactGeneric_light_000` | `impactMetal_light_002` + `impactSoft_medium_002` | Restrained toy-body contact, not cinematic impact |
| `hazard_warning` | `error_003.ogg` | `error_005.ogg` | Telegraph clarity without alarm fatigue |

Audition candidates in context with engine, tire, boost, impact, hazard, and music layers before approval. Prefer gameplay information, toy scale, frequency separation, and repeatability over solo loudness. Reject stock sci-fi weapon character, harsh broadband noise, phone-notification character, clipping, obvious loop resets, or any cue that wins only by being louder.

## Final prototype paths

All outputs are 48 kHz mono OGG Vorbis (`libvorbis`, quality 5):

```text
prototypes/audio_audition/candidates/engine_loop_{a,b}.ogg
prototypes/audio_audition/candidates/countdown_{a,b}.ogg
prototypes/audio_audition/candidates/go_{a,b}.ogg
prototypes/audio_audition/candidates/ui_move_{a,b}.ogg
prototypes/audio_audition/candidates/ui_confirm_{a,b}.ogg
prototypes/audio_audition/candidates/drift_{a,b}.ogg
prototypes/audio_audition/candidates/boost_{a,b}.ogg
prototypes/audio_audition/candidates/impact_{a,b}.ogg
prototypes/audio_audition/candidates/hazard_warning_{a,b}.ogg
```

## Exact transformations

Generated with FFmpeg `n9.0.1`. There is no normalization, compression, limiting, or positive gain. The ordinary direct conversions receive a 1 dB safety attenuation. Two unusually sharp interface transients receive 6 dB attenuation because decoded Vorbis checks showed that smaller attenuation left insufficient peak headroom. Dynamics are otherwise preserved.

The following commands are the exact reproducible transformations, with `$SRC=/tmp/opencode/audio-sources` and `$OUT=prototypes/audio_audition/candidates`:

```sh
SRC=/tmp/opencode/audio-sources
OUT=prototypes/audio_audition/candidates

ffmpeg -y -v error -i "$SRC/sci-fi/Audio/engineCircular_000.ogg" -vn -af "volume=-1dB" -ar 48000 -ac 1 -c:a libvorbis -q:a 5 "$OUT/engine_loop_a.ogg"
ffmpeg -y -v error -i "$SRC/sci-fi/Audio/spaceEngineSmall_000.ogg" -vn -af "volume=-1dB" -ar 48000 -ac 1 -c:a libvorbis -q:a 5 "$OUT/engine_loop_b.ogg"
ffmpeg -y -v error -i "$SRC/interface/Audio/select_003.ogg" -vn -af "volume=-1dB" -ar 48000 -ac 1 -c:a libvorbis -q:a 5 "$OUT/countdown_a.ogg"
ffmpeg -y -v error -i "$SRC/interface/Audio/select_004.ogg" -vn -af "volume=-1dB" -ar 48000 -ac 1 -c:a libvorbis -q:a 5 "$OUT/countdown_b.ogg"
ffmpeg -y -v error -i "$SRC/interface/Audio/confirmation_002.ogg" -vn -af "volume=-1dB" -ar 48000 -ac 1 -c:a libvorbis -q:a 5 "$OUT/go_a.ogg"
ffmpeg -y -v error -i "$SRC/interface/Audio/confirmation_003.ogg" -vn -af "volume=-1dB" -ar 48000 -ac 1 -c:a libvorbis -q:a 5 "$OUT/go_b.ogg"
ffmpeg -y -v error -i "$SRC/interface/Audio/tick_004.ogg" -vn -af "volume=-1dB" -ar 48000 -ac 1 -c:a libvorbis -q:a 5 "$OUT/ui_move_a.ogg"
ffmpeg -y -v error -i "$SRC/interface/Audio/select_001.ogg" -vn -af "volume=-6dB" -ar 48000 -ac 1 -c:a libvorbis -q:a 5 "$OUT/ui_move_b.ogg"
ffmpeg -y -v error -i "$SRC/interface/Audio/confirmation_001.ogg" -vn -af "volume=-1dB" -ar 48000 -ac 1 -c:a libvorbis -q:a 5 "$OUT/ui_confirm_a.ogg"
ffmpeg -y -v error -i "$SRC/interface/Audio/confirmation_004.ogg" -vn -af "volume=-1dB" -ar 48000 -ac 1 -c:a libvorbis -q:a 5 "$OUT/ui_confirm_b.ogg"
ffmpeg -y -v error -i "$SRC/interface/Audio/scratch_004.ogg" -vn -af "volume=-1dB" -ar 48000 -ac 1 -c:a libvorbis -q:a 5 "$OUT/drift_a.ogg"
ffmpeg -y -v error -i "$SRC/interface/Audio/scratch_005.ogg" -vn -af "volume=-1dB" -ar 48000 -ac 1 -c:a libvorbis -q:a 5 "$OUT/drift_b.ogg"
ffmpeg -y -v error -i "$SRC/sci-fi/Audio/thrusterFire_000.ogg" -vn -af "atrim=start=0:end=0.85,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.005,afade=t=out:st=0.70:d=0.15,volume=-1dB" -ar 48000 -ac 1 -c:a libvorbis -q:a 5 "$OUT/boost_a.ogg"
ffmpeg -y -v error -i "$SRC/sci-fi/Audio/thrusterFire_002.ogg" -vn -af "atrim=start=0:end=0.90,asetpts=PTS-STARTPTS,afade=t=in:st=0:d=0.005,afade=t=out:st=0.72:d=0.18,volume=-1dB" -ar 48000 -ac 1 -c:a libvorbis -q:a 5 "$OUT/boost_b.ogg"

ffmpeg -y -v error -i "$SRC/impact/Audio/impactTin_medium_000.ogg" -i "$SRC/impact/Audio/impactGeneric_light_000.ogg" -filter_complex "[0:a]aformat=sample_rates=48000:channel_layouts=mono,volume=0.55[tin];[1:a]aformat=sample_rates=48000:channel_layouts=mono,volume=0.35,adelay=12ms:all=1[body];[tin][body]amix=inputs=2:duration=longest:normalize=0,afade=t=out:st=0.13:d=0.045[out]" -map "[out]" -c:a libvorbis -q:a 5 "$OUT/impact_a.ogg"
ffmpeg -y -v error -i "$SRC/impact/Audio/impactMetal_light_002.ogg" -i "$SRC/impact/Audio/impactSoft_medium_002.ogg" -filter_complex "[0:a]aformat=sample_rates=48000:channel_layouts=mono,volume=0.50[metal];[1:a]aformat=sample_rates=48000:channel_layouts=mono,volume=0.38,adelay=16ms:all=1[body];[metal][body]amix=inputs=2:duration=longest:normalize=0,afade=t=out:st=0.19:d=0.045[out]" -map "[out]" -c:a libvorbis -q:a 5 "$OUT/impact_b.ogg"

ffmpeg -y -v error -i "$SRC/interface/Audio/error_003.ogg" -vn -af "volume=-6dB" -ar 48000 -ac 1 -c:a libvorbis -q:a 5 "$OUT/hazard_warning_a.ogg"
ffmpeg -y -v error -i "$SRC/interface/Audio/error_005.ogg" -vn -af "volume=-1dB" -ar 48000 -ac 1 -c:a libvorbis -q:a 5 "$OUT/hazard_warning_b.ogg"
```

Boost A is 0.850 seconds; boost B decodes as approximately 0.890 seconds because the Vorbis stream ends on its final encoded granule. Impact A is 0.176 seconds and impact B is 0.236 seconds. Both impact mixes keep layer sums below unity, use no automatic `amix` normalization, and remain well under the 0.6-second cap. Peak checks of the final decoded candidates found no sample clipping; measured maxima range from about -5.3 dBFS to -1.6 dBFS for the regular candidates, -4.2/-3.5 dBFS for the two additionally attenuated transients, and -3.2/-2.3 dBFS for the impact composites.

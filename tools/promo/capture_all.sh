#!/usr/bin/env bash
# Records every take the 2026-10-06 promo used, three at a time (~45 min on a
# software-rendered Xvfb). Run from inside a capture worktree.
set -Euo pipefail
readonly KIT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly D="${DISPLAY_BASE:-121}"
S="$KIT/shot.sh"
# Race takes: boss driver, easy rivals so it passes them, no turbo/pursuit one-shots, music off (the score is recorded on its own).
R="--mute=Music --silence=boost,pursuit --difficulty=sunday_drive --boss=1"
(
	$S kitchen $D --promo-shot=race --theme=kitchen --seed=274524 --vehicle=rustbug --seconds=40 $R --look-seed=11
	$S drift $((D+3)) --promo-shot=race --theme=kitchen --seed=27639 --vehicle=pinbolt --seconds=24 $R --look-seed=5
	$S garage $((D+6)) --promo-shot=garage --seconds=11.5
) &
(
	$S workshop $((D+1)) --promo-shot=race --theme=workshop --seed=614214 --vehicle=scrapjaw --seconds=40 $R --look-seed=21
	$S strip $((D+4)) --promo-shot=strip --theme=kitchen --theme-b=office --seed=537581 --vehicle=pinbolt --seconds=40 $R --field=2 --look-seed=12
	$S title $((D+7)) --promo-shot=title --seconds=14
	$S flip $((D+8)) --promo-shot=flip --seconds=33 --dwell=2.5
) &
(
	$S office $((D+2)) --promo-shot=race --theme=office --seed=510421 --vehicle=flicker --seconds=40 $R --look-seed=31
	$S reverse $((D+5)) --promo-shot=race --theme=kitchen --seed=363461 --vehicle=anvil --reverse=1 --tier=compact --seconds=30 $R --look-seed=41
	# Score bed: a full race with only the music bus audible.
	$S music $((D+9)) --promo-shot=race --theme=workshop --seed=707143 --vehicle=thimble --tier=compact --seconds=150 --mute=SFX,Engine,Tyre
) &
wait
echo "CAPTURE DONE"

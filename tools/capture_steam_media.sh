#!/usr/bin/env bash
set -Eeuo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly SCRIPT_PATH="$(realpath -- "${BASH_SOURCE[0]}")"

cleanup_session() {
	if [[ -n "${game_pid:-}" ]]; then
		kill "$game_pid" 2>/dev/null || true
		wait "$game_pid" 2>/dev/null || true
	fi
}

if [[ "${1:-}" == "--xvfb-session" ]]; then
	mode="$2"
	binary="$3"
	data_home="$4"
	output="$5"
	map_tabs="$6"
	vehicle_tabs="$7"
	log_path="$8"
	expected_event="$9"
	expected_vehicle="${10}"
	export XDG_DATA_HOME="$data_home"
	stdbuf -oL -eL "$binary" --audio-driver Dummy --resolution 1920x1080 --position 0,0 -- --media-capture >"$log_path" 2>&1 &
	game_pid=$!
	trap cleanup_session EXIT
	windows=()
	for _attempt in {1..100}; do
		mapfile -t windows < <(xdotool search --pid "$game_pid" 2>/dev/null || true)
		(( ${#windows[@]} > 0 )) && break
		sleep 0.1
	done
	if (( ${#windows[@]} == 0 )); then
		printf 'Pocket Circuit window did not appear.\n' >&2
		exit 1
	fi
	window_id="${windows[0]}"
	xdotool windowsize "$window_id" 1920 1080
	xdotool windowmove "$window_id" 0 0
	sleep 1
	send_key() {
		xdotool key --window "$window_id" "$@" 2>/dev/null
	}
	key_down() {
		xdotool keydown --window "$window_id" "$@" 2>/dev/null
	}
	key_up() {
		xdotool keyup --window "$window_id" "$@" 2>/dev/null
	}
	wait_for_marker() {
		local marker="$1"
		for _marker_attempt in {1..200}; do
			if grep -Fq -- "$marker" "$log_path"; then
				sleep 0.35
				return 0
			fi
			if ! kill -0 "$game_pid" 2>/dev/null; then
				printf 'Pocket Circuit exited before runtime marker: %s\n' "$marker" >&2
				grep -E '(SCRIPT ERROR|ERROR:|MEDIA_)' "$log_path" >&2 || true
				exit 1
			fi
			sleep 0.1
		done
		printf 'Timed out waiting for Pocket Circuit runtime marker: %s\n' "$marker" >&2
		grep -E '(SCRIPT ERROR|ERROR:|MEDIA_)' "$log_path" >&2 || true
		exit 1
	}

	wait_for_marker "MEDIA_SCREEN_READY title"

	if [[ "$mode" != "title" ]]; then
		send_key Return
		wait_for_marker "MEDIA_SCREEN_READY map"
	fi
	if [[ "$mode" != "title" && "$mode" != "map" ]]; then
		for (( tab_index=0; tab_index<map_tabs; tab_index++ )); do
			send_key Tab
		done
		send_key Return
		wait_for_marker "MEDIA_SCREEN_READY briefing"
	fi
	if [[ "$mode" == "vehicle" || "$mode" == "race" || "$mode" == "clip" ]]; then
		send_key Return
		wait_for_marker "MEDIA_SCREEN_READY vehicle_select"
	fi
	if [[ "$mode" == "race" || "$mode" == "clip" ]]; then
		for (( tab_index=0; tab_index<vehicle_tabs; tab_index++ )); do
			send_key Tab
		done
		send_key Return
		wait_for_marker "MEDIA_RACE_READY $expected_event $expected_vehicle"
	fi

	if [[ "$mode" == "clip" ]]; then
		ffmpeg -nostdin -y -loglevel error \
			-video_size 1920x1080 -framerate 30 -f x11grab -i "$DISPLAY+0,0" \
			-t 5 -an -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p "$output" &
		ffmpeg_pid=$!
		key_down Up
		sleep 1.0
		key_down Right
		sleep 1.1
		key_up Right
		key_down Left
		sleep 1.1
		key_up Left
		send_key space
		sleep 1.0
		key_up Up
		wait "$ffmpeg_pid"
	else
		if [[ "$mode" == "race" ]]; then
			key_down Up
			key_down Right
			sleep 1.4
		fi
		import -window "$window_id" "$output"
		magick "$output" -alpha off -resize 1920x1080! "$output"
		if [[ "$mode" == "race" ]]; then
			key_up Right
			key_up Up
		fi
	fi
	cleanup_session
	game_pid=""
	trap - EXIT
	if grep -Eq '(SCRIPT ERROR|ERROR:)' "$log_path"; then
		printf 'Pocket Circuit reported a runtime error during media capture.\n' >&2
		grep -E '(SCRIPT ERROR|ERROR:)' "$log_path" >&2 || true
		exit 1
	fi
	exit 0
fi

build_root="${1:-/tmp/opencode/pocket-circuit-release-candidate}"
binary="$build_root/linux/pocket-circuit.x86_64"
if [[ ! -x "$binary" ]]; then
	printf 'Packaged Linux release is missing or not executable: %s\n' "$binary" >&2
	exit 1
fi
if [[ ! -f "$build_root/SHA256SUMS" ]]; then
	printf 'Candidate SHA-256 manifest is missing: %s\n' "$build_root/SHA256SUMS" >&2
	exit 1
fi
if ! (cd -- "$build_root" && sha256sum --check SHA256SUMS); then
	printf 'Candidate files do not match their SHA-256 manifest: %s\n' "$build_root" >&2
	exit 1
fi
for command_name in godot sha256sum stdbuf grep xvfb-run xdotool import magick ffmpeg ffprobe; do
	if ! command -v -- "$command_name" >/dev/null 2>&1; then
		printf 'Required media tool is missing: %s\n' "$command_name" >&2
		exit 1
	fi
done

media_root="$PROJECT_ROOT/media/steam"
screenshots_root="$media_root/screenshots"
trailer_root="$media_root/trailer"
mkdir -p -- "$screenshots_root" "$trailer_root"
cp -- "$build_root/SHA256SUMS" "$media_root/BUILD_SHA256SUMS"
temporary_root="$(mktemp -d /tmp/opencode/pocket-circuit-media.XXXXXX)"
cleanup_outer() {
	rm -rf -- "$temporary_root"
}
trap cleanup_outer EXIT
data_home="$temporary_root/data"
mkdir -p -- "$data_home"
run_session() {
	local mode="$1"
	local output="$2"
	local map_tabs="$3"
	local vehicle_tabs="$4"
	local expected_event="${5:-}"
	local expected_vehicle="${6:-}"
	local log_path="$temporary_root/${mode}-${map_tabs}-${vehicle_tabs}.log"
	XDG_DATA_HOME="$data_home" godot --path "$PROJECT_ROOT" --headless --script res://tools/create_media_save.gd >/dev/null
	xvfb-run -a --server-args="-screen 0 1920x1080x24" \
		"$SCRIPT_PATH" --xvfb-session "$mode" "$binary" "$data_home" "$output" "$map_tabs" "$vehicle_tabs" "$log_path" "$expected_event" "$expected_vehicle"
}

run_session title "$screenshots_root/01_title.png" 0 0
run_session map "$screenshots_root/02_championship_map.png" 0 0
run_session briefing "$screenshots_root/03_kitchen_briefing.png" 0 0
run_session vehicle "$screenshots_root/04_vehicle_select.png" 0 0
run_session race "$screenshots_root/05_kitchen_race.png" 0 0 kitchen_crumb_rush rustbug
run_session race "$screenshots_root/06_workshop_race.png" 3 2 workshop_screw_loose scrapjaw
run_session race "$screenshots_root/07_office_race.png" 6 3 office_paper_trail flicker

run_session clip "$temporary_root/kitchen-rustbug.mp4" 0 0 kitchen_crumb_rush rustbug
run_session clip "$temporary_root/kitchen-pinbolt.mp4" 0 1 kitchen_crumb_rush pinbolt
run_session clip "$temporary_root/workshop-scrapjaw.mp4" 3 2 workshop_screw_loose scrapjaw
run_session clip "$temporary_root/office-flicker.mp4" 6 3 office_paper_trail flicker

ffmpeg -nostdin -y -loglevel error \
	-loop 1 -t 2 -i "$trailer_root/opening_card.png" \
	-i "$temporary_root/kitchen-rustbug.mp4" \
	-i "$temporary_root/kitchen-pinbolt.mp4" \
	-i "$temporary_root/workshop-scrapjaw.mp4" \
	-i "$temporary_root/office-flicker.mp4" \
	-loop 1 -t 3 -i "$trailer_root/ending_card.png" \
	-stream_loop -1 -i "$PROJECT_ROOT/assets/audio/race_loop.wav" \
	-filter_complex "[0:v]fps=30,format=yuv420p[v0];[1:v]fps=30,format=yuv420p[v1];[2:v]fps=30,format=yuv420p[v2];[3:v]fps=30,format=yuv420p[v3];[4:v]fps=30,format=yuv420p[v4];[5:v]fps=30,format=yuv420p[v5];[v1][v0][v2][v3][v4][v5]concat=n=6:v=1:a=0[v]" \
	-map "[v]" -map 6:a:0 -t 25 -c:v libx264 -preset slow -b:v 6M -minrate 6M -maxrate 6M -bufsize 12M \
	-x264-params "nal-hrd=cbr:force-cfr=1" \
	-c:a aac -b:a 192k -ar 48000 -ac 2 -pix_fmt yuv420p -movflags +faststart \
	"$trailer_root/pocket_circuit_gameplay_trailer.mp4"

for screenshot in "$screenshots_root"/*.png; do
	dimensions="$(identify -format '%wx%h' "$screenshot")"
	if [[ "$dimensions" != "1920x1080" ]]; then
		printf 'Screenshot has unexpected dimensions: %s (%s)\n' "$screenshot" "$dimensions" >&2
		exit 1
	fi
done
video_summary="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,pix_fmt,r_frame_rate -of csv=p=0 "$trailer_root/pocket_circuit_gameplay_trailer.mp4")"
audio_summary="$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of csv=p=0 "$trailer_root/pocket_circuit_gameplay_trailer.mp4")"
video_bitrate="$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of csv=p=0 "$trailer_root/pocket_circuit_gameplay_trailer.mp4")"
audio_bitrate="$(ffprobe -v error -select_streams a:0 -show_entries stream=bit_rate -of csv=p=0 "$trailer_root/pocket_circuit_gameplay_trailer.mp4")"
if [[ "$video_summary" != "h264,1920,1080,yuv420p,30/1" || "$audio_summary" != "aac,48000,2" || ! "$video_bitrate" =~ ^[0-9]+$ || ! "$audio_bitrate" =~ ^[0-9]+$ || "$video_bitrate" -lt 5000000 || "$audio_bitrate" -lt 160000 ]]; then
	printf 'Trailer encoding is unexpected: video=%s at %s bps, audio=%s at %s bps\n' "$video_summary" "$video_bitrate" "$audio_summary" "$audio_bitrate" >&2
	exit 1
fi
(
	cd -- "$media_root"
	LC_ALL=C sha256sum -- \
		BUILD_SHA256SUMS \
		capsules/community_icon.png capsules/header_capsule.png capsules/library_capsule.png \
		capsules/library_hero.png capsules/library_logo.png capsules/main_capsule.png \
		capsules/page_background.png capsules/small_capsule.png capsules/vertical_capsule.png \
		screenshots/01_title.png screenshots/02_championship_map.png \
		screenshots/03_kitchen_briefing.png screenshots/04_vehicle_select.png \
		screenshots/05_kitchen_race.png screenshots/06_workshop_race.png \
		screenshots/07_office_race.png trailer/opening_card.png trailer/ending_card.png \
		trailer/pocket_circuit_gameplay_trailer.mp4 > SHA256SUMS
)
printf 'STEAM_MEDIA PASS: 7 screenshots and H.264/AAC gameplay trailer under %s\n' "$media_root"

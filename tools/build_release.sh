#!/usr/bin/env bash
set -Eeuo pipefail

readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
command -v python3 >/dev/null 2>&1 || { printf 'python3 is required.\n' >&2; exit 1; }
readonly REQUIRED_GODOT_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$PROJECT_ROOT/tools/godot_release.json")"
readonly TEMPLATE_VERSION="$REQUIRED_GODOT_VERSION.stable"

if (( $# > 1 )); then
  printf 'Usage: %s [output-directory]\n' "$0" >&2
  exit 2
fi

godot_bin="${GODOT_BIN:-godot}"
if ! command -v -- "$godot_bin" >/dev/null 2>&1; then
  printf 'Godot executable not found: %s\n' "$godot_bin" >&2
  exit 1
fi

godot_version="$("$godot_bin" --version)"
case "$godot_version" in
  "$REQUIRED_GODOT_VERSION"|"$REQUIRED_GODOT_VERSION".*) ;;
  *)
    printf 'Godot %s is required exactly; found %s\n' "$REQUIRED_GODOT_VERSION" "$godot_version" >&2
    exit 1
    ;;
esac

output_arg="${1:-$PROJECT_ROOT/builds}"
if [[ "$output_arg" = /* ]]; then
  output_root="$output_arg"
else
  output_root="$PWD/$output_arg"
fi
mkdir -p -- "$output_root"
output_root="$(realpath -- "$output_root")"
linux_dir="$output_root/linux"
windows_dir="$output_root/windows"

for platform_dir in "$linux_dir" "$windows_dir"; do
  if [[ -L "$platform_dir" ]]; then
    printf 'Refusing symlinked output directory: %s\n' "$platform_dir" >&2
    exit 1
  fi
  mkdir -p -- "$platform_dir"
done

if ! command -v sha256sum >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1 || ! command -v grep >/dev/null 2>&1 || ! command -v tee >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1 || ! command -v xargs >/dev/null 2>&1 || { ! command -v magick >/dev/null 2>&1 && ! command -v convert >/dev/null 2>&1; }; then
	printf 'python3, sha256sum, ImageMagick (magick or convert), ffprobe, grep, tee, timeout, and xargs are required.\n' >&2
	exit 1
fi

source "$PROJECT_ROOT/tools/godot_gate.sh"

# Default 4 (not 6) on an 8-core shared host so the longest serial and parallel
# tests still have CPU headroom under load; PC_GATE_PARALLELISM overrides.
# Checked here so a bad value fails before the slow sync and import steps.
gate_parallelism="${PC_GATE_PARALLELISM:-4}"
validate_gate_parallelism "$gate_parallelism" || exit 1

export GAMESTRUMENTS_ADDON_DIR="${GAMESTRUMENTS_ADDON_DIR:-$PROJECT_ROOT/vendor/gamestruments}"
printf 'Syncing Gamestruments live engine from %s...\n' "$GAMESTRUMENTS_ADDON_DIR"
"$PROJECT_ROOT/tools/sync_gamestruments.sh"

python3 "$PROJECT_ROOT/tools/validate_release_config.py"
python3 -m unittest discover -s "$PROJECT_ROOT/tests" -p 'test_*.py'

printf 'Checking runtime vehicle dependencies...\n'
for runtime_script in \
	"$PROJECT_ROOT/scripts/vehicle/vehicle_controller.gd" \
	"$PROJECT_ROOT/scripts/vehicle/ai_vehicle_controller.gd"; do
	if ! grep -Fq 'const DYNAMICS := preload("res://scripts/vehicle/vehicle_dynamics.gd")' "$runtime_script"; then
		printf 'Runtime controller must explicitly preload vehicle_dynamics.gd: %s\n' "$runtime_script" >&2
		exit 1
	fi
	if grep -Fq 'VehicleDynamics.' "$runtime_script"; then
		printf 'Runtime controller depends on Godot generated class-cache state: %s\n' "$runtime_script" >&2
		exit 1
	fi
done

printf 'Importing project with Godot %s...\n' "$godot_version"
run_godot_checked timeout 300 "$godot_bin" --path "$PROJECT_ROOT" --headless --editor --import --quit

printf 'Verifying Gamestruments live engine is present and loadable (release gate has no silent-music WAV fallback mode)...\n'
check_script="$(mktemp "${TMPDIR:-/tmp}/pocket-circuit-check-gamestruments.XXXXXX.gd")"
cat > "$check_script" << 'EOGD'
extends SceneTree
func _initialize() -> void:
	if ClassDB.class_exists("GamestrumentsPlayer"):
		print("LIVE_GAMESTRUMENTS_ENGINE_PRESENT")
		quit(0)
	else:
		push_error("LIVE_GAMESTRUMENTS_ENGINE_ABSENT: ClassDB.class_exists(\"GamestrumentsPlayer\") must be true; WAV fallbacks removed")
		quit(1)
EOGD
if ! POCKET_CIRCUIT_EXPECT_OUTPUT="LIVE_GAMESTRUMENTS_ENGINE_PRESENT" run_godot_checked timeout 60 "$godot_bin" --path "$PROJECT_ROOT" --headless --script "$check_script"; then
	printf 'Gamestruments live engine missing or failed to load after sync. The release gate requires the native extension.\n' >&2
	rm -f -- "$check_script"
	exit 1
fi
rm -f -- "$check_script"

shopt -s nullglob dotglob
tests=("$PROJECT_ROOT"/tests/*.gd)
if (( ${#tests[@]} == 0 )); then
  printf 'No tests/*.gd files found.\n' >&2
  exit 1
fi

# Tests that assert on wall-clock responsiveness stay serial so CPU contention
# from the parallel workers cannot skew their timings.
serial_tests=(
	"tests/ai_seed_sweep_test.gd"
	"tests/race_start_timing_test.gd"
	"tests/reset_manager_test.gd"
	"tests/menu_feedback_test.gd"
	"tests/track_outer_cut_map_test.gd"
)

# The remaining tests run in parallel; run_gate_tests accounts for every one.
# With these traps set, a signal waits for the gate to stop its test processes
# and remove its scratch instead of ending this script first.
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
if ! run_gate_tests "$PROJECT_ROOT" "$godot_bin" "$gate_parallelism" "${serial_tests[@]}" -- "${tests[@]#"$PROJECT_ROOT"/}"; then
	printf 'Release tests failed; no exports will be attempted.\n' >&2
	exit 1
fi
trap - HUP INT TERM

printf 'Smoke-testing the boot scene...\n'
POCKET_CIRCUIT_EXPECT_OUTPUT="RELEASE_RACE_SMOKE PASS" \
	run_godot_checked timeout 180 "$godot_bin" --path "$PROJECT_ROOT" --headless --scene res://scenes/boot/boot.tscn -- --release-smoke

printf 'Smoke-testing the race scene...\n'
run_godot_checked "$godot_bin" --path "$PROJECT_ROOT" --headless --scene res://scenes/race/prototype_race.tscn --quit-after 600

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
templates_dir="$data_home/godot/export_templates/$TEMPLATE_VERSION"
required_templates=(
  "$templates_dir/linux_release.x86_64"
  "$templates_dir/windows_release_x86_64.exe"
)
missing_templates=()
for template_path in "${required_templates[@]}"; do
  [[ -f "$template_path" ]] || missing_templates+=("$template_path")
done
if (( ${#missing_templates[@]} > 0 )); then
  printf 'Official native export templates for Godot %s are missing; no exports were attempted:\n' "$REQUIRED_GODOT_VERSION" >&2
  printf '  %s\n' "${missing_templates[@]}" >&2
  exit 1
fi

linux_binary="$linux_dir/pocket-circuit.x86_64"
linux_pck="$linux_dir/pocket-circuit.pck"
linux_library="$linux_dir/libgamestruments_godot.so"
windows_binary="$windows_dir/pocket-circuit.exe"
windows_pck="$windows_dir/pocket-circuit.pck"
windows_library="$windows_dir/gamestruments_godot.dll"

# Remove only the known outputs inside the selected output root. Other files
# and directories are never recursively cleaned.
rm -f -- \
	"$linux_binary" "$linux_pck" "$linux_library" "$linux_dir/SHA256SUMS" \
	"$windows_binary" "$windows_pck" "$windows_library" "$windows_dir/SHA256SUMS" \
	"$output_root/SHA256SUMS"

for platform_dir in "$linux_dir" "$windows_dir"; do
	remaining_entries=("$platform_dir"/*)
	if (( ${#remaining_entries[@]} > 0 )); then
		printf 'Refusing output directory with unexpected content: %s\n' "$platform_dir" >&2
		printf '  %s\n' "${remaining_entries[@]}" >&2
		exit 1
	fi
done

printf 'Exporting Linux x86_64 release...\n'
run_godot_checked "$godot_bin" --path "$PROJECT_ROOT" --headless --export-release "Linux x86_64" "$linux_binary"

printf 'Exporting Windows Desktop x86_64 release...\n'
run_godot_checked "$godot_bin" --path "$PROJECT_ROOT" --headless --export-release "Windows Desktop x86_64" "$windows_binary"

for artifact in "$linux_binary" "$linux_pck" "$linux_library" "$windows_binary" "$windows_pck" "$windows_library"; do
  if [[ ! -s "$artifact" ]]; then
    printf 'Expected export artifact is missing or empty: %s\n' "$artifact" >&2
    exit 1
  fi
done
chmod +x -- "$linux_binary"

printf 'Smoke-testing the packaged Linux release...\n'
(
	cd -- "$linux_dir"
	POCKET_CIRCUIT_EXPECT_OUTPUT="RELEASE_RACE_SMOKE PASS" \
		run_godot_checked timeout 180 ./pocket-circuit.x86_64 --headless -- --release-smoke
)

printf 'Inspecting packaged release contents...\n'
pack_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/pocket-circuit-pack-check.XXXXXX")"
pack_check_library_dir="$pack_check_dir/addons/gamestruments/bin"
cleanup_pack_check() {
	rm -f -- "$pack_check_library_dir/libgamestruments_godot.so"
	rmdir -- "$pack_check_library_dir" "$pack_check_dir/addons/gamestruments" "$pack_check_dir/addons" "$pack_check_dir" 2>/dev/null || true
}
trap cleanup_pack_check EXIT
mkdir -p -- "$pack_check_library_dir"
cp -f -- "$linux_library" "$pack_check_library_dir/libgamestruments_godot.so"
(
	cd -- "$pack_check_dir"
	POCKET_CIRCUIT_EXPECT_OUTPUT="PACKAGED_CONTENT_TEST PASS" run_godot_checked timeout 120 "$godot_bin" --headless --main-pack "$linux_pck" --script "$PROJECT_ROOT/tools/inspect_release_pack.gd"
	POCKET_CIRCUIT_EXPECT_OUTPUT="PACKAGED_CONTENT_TEST PASS" run_godot_checked timeout 120 "$godot_bin" --headless --main-pack "$windows_pck" --script "$PROJECT_ROOT/tools/inspect_release_pack.gd"
)
cleanup_pack_check
trap - EXIT

(
  cd -- "$linux_dir"
  LC_ALL=C sha256sum -- pocket-circuit.x86_64 pocket-circuit.pck libgamestruments_godot.so > SHA256SUMS
)
(
  cd -- "$windows_dir"
  LC_ALL=C sha256sum -- pocket-circuit.exe pocket-circuit.pck gamestruments_godot.dll > SHA256SUMS
)
(
	cd -- "$output_root"
  LC_ALL=C sha256sum -- \
    linux/pocket-circuit.x86_64 linux/pocket-circuit.pck linux/libgamestruments_godot.so \
		windows/pocket-circuit.exe windows/pocket-circuit.pck windows/gamestruments_godot.dll > SHA256SUMS
)

for platform_dir in "$linux_dir" "$windows_dir"; do
	entries=("$platform_dir"/*)
	if (( ${#entries[@]} != 4 )); then
		printf 'Export directory contains an unexpected number of files: %s\n' "$platform_dir" >&2
		exit 1
	fi
done
for expected_path in \
	"$linux_binary" "$linux_pck" "$linux_library" "$linux_dir/SHA256SUMS" \
	"$windows_binary" "$windows_pck" "$windows_library" "$windows_dir/SHA256SUMS"; do
	if [[ ! -f "$expected_path" || -L "$expected_path" ]]; then
		printf 'Export directory contains a missing or unsafe expected file: %s\n' "$expected_path" >&2
		exit 1
	fi
done

printf 'Release artifacts and SHA-256 manifests written under %s\n' "$output_root"

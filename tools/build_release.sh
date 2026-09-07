#!/usr/bin/env bash
set -Eeuo pipefail

readonly REQUIRED_GODOT_VERSION="4.7.2"
readonly TEMPLATE_VERSION="4.7.2.stable"
readonly PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

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

if ! command -v python3 >/dev/null 2>&1 || ! command -v sha256sum >/dev/null 2>&1 || ! command -v magick >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1 || ! command -v grep >/dev/null 2>&1 || ! command -v tee >/dev/null 2>&1; then
	printf 'python3, sha256sum, magick, ffprobe, grep, and tee are required.\n' >&2
	exit 1
fi

run_godot_checked() {
	local command_log
	local expected_output="${POCKET_CIRCUIT_EXPECT_OUTPUT:-}"
	command_log="$(mktemp "${TMPDIR:-/tmp}/pocket-circuit-godot.XXXXXX")"
	if ! "$@" 2>&1 | tee "$command_log"; then
		rm -f -- "$command_log"
		return 1
	fi
	if grep -Eq '(^|[[:space:]])(SCRIPT ERROR|ERROR):' "$command_log"; then
		printf 'Godot reported an error despite returning success.\n' >&2
		rm -f -- "$command_log"
		return 1
	fi
	if [[ -n "$expected_output" ]] && ! grep -Fq -- "$expected_output" "$command_log"; then
		printf 'Godot did not report the expected success marker: %s\n' "$expected_output" >&2
		rm -f -- "$command_log"
		return 1
	fi
	rm -f -- "$command_log"
}

python3 "$PROJECT_ROOT/tools/validate_release_config.py"

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
run_godot_checked "$godot_bin" --path "$PROJECT_ROOT" --headless --import

shopt -s nullglob dotglob
tests=("$PROJECT_ROOT"/tests/*.gd)
if (( ${#tests[@]} == 0 )); then
  printf 'No tests/*.gd files found.\n' >&2
  exit 1
fi

for test_path in "${tests[@]}"; do
	test_relative="${test_path#"$PROJECT_ROOT"/}"
	printf 'Running %s...\n' "$test_relative"
	run_godot_checked "$godot_bin" --path "$PROJECT_ROOT" --headless --script "res://$test_relative"
done

printf 'Smoke-testing the boot scene...\n'
run_godot_checked "$godot_bin" --path "$PROJECT_ROOT" --headless --scene res://scenes/boot/boot.tscn --quit-after 300

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
windows_binary="$windows_dir/pocket-circuit.exe"
windows_pck="$windows_dir/pocket-circuit.pck"

# Remove only the known outputs inside the selected output root. Other files
# and directories are never recursively cleaned.
rm -f -- \
	"$linux_binary" "$linux_pck" "$linux_dir/SHA256SUMS" \
	"$windows_binary" "$windows_pck" "$windows_dir/SHA256SUMS" \
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

for artifact in "$linux_binary" "$linux_pck" "$windows_binary" "$windows_pck"; do
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
		run_godot_checked ./pocket-circuit.x86_64 --headless --quit-after 1200 -- --release-smoke
)

printf 'Inspecting packaged release contents...\n'
pack_check_dir="$(mktemp -d "${TMPDIR:-/tmp}/pocket-circuit-pack-check.XXXXXX")"
cleanup_pack_check() {
  rmdir -- "$pack_check_dir" 2>/dev/null || true
}
trap cleanup_pack_check EXIT
(
	cd -- "$pack_check_dir"
	run_godot_checked "$godot_bin" --headless --main-pack "$linux_pck" --script "$PROJECT_ROOT/tools/inspect_release_pack.gd"
	run_godot_checked "$godot_bin" --headless --main-pack "$windows_pck" --script "$PROJECT_ROOT/tools/inspect_release_pack.gd"
)
cleanup_pack_check
trap - EXIT

(
  cd -- "$linux_dir"
  LC_ALL=C sha256sum -- pocket-circuit.x86_64 pocket-circuit.pck > SHA256SUMS
)
(
  cd -- "$windows_dir"
  LC_ALL=C sha256sum -- pocket-circuit.exe pocket-circuit.pck > SHA256SUMS
)
(
	cd -- "$output_root"
  LC_ALL=C sha256sum -- \
    linux/pocket-circuit.x86_64 linux/pocket-circuit.pck \
		windows/pocket-circuit.exe windows/pocket-circuit.pck > SHA256SUMS
)

for platform_dir in "$linux_dir" "$windows_dir"; do
	entries=("$platform_dir"/*)
	if (( ${#entries[@]} != 3 )); then
		printf 'Export directory contains an unexpected number of files: %s\n' "$platform_dir" >&2
		exit 1
	fi
done
for expected_path in \
	"$linux_binary" "$linux_pck" "$linux_dir/SHA256SUMS" \
	"$windows_binary" "$windows_pck" "$windows_dir/SHA256SUMS"; do
	if [[ ! -f "$expected_path" || -L "$expected_path" ]]; then
		printf 'Export directory contains a missing or unsafe expected file: %s\n' "$expected_path" >&2
		exit 1
	fi
done

printf 'Release artifacts and SHA-256 manifests written under %s\n' "$output_root"

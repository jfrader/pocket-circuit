#!/usr/bin/env bash
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

usage() {
  cat >&2 <<'USAGE'
Usage:
  upload_build.sh --upload --steamcmd PATH --account NAME \
    --app-id ID --windows-depot-id ID --linux-depot-id ID \
    --config APP_BUILD_VDF --windows-config WINDOWS_VDF --linux-config LINUX_VDF

The completed VDF must live outside the repository and contain no placeholders.
SteamCMD prompts for password and Steam Guard details; this script never accepts
or stores those credentials.
USAGE
}

confirmed=false
steamcmd=""
account=""
app_id=""
windows_depot_id=""
linux_depot_id=""
config=""
windows_config=""
linux_config=""

while (( $# > 0 )); do
  case "$1" in
    --upload) confirmed=true; shift ;;
    --steamcmd) steamcmd="${2:-}"; shift 2 ;;
    --account) account="${2:-}"; shift 2 ;;
    --app-id) app_id="${2:-}"; shift 2 ;;
    --windows-depot-id) windows_depot_id="${2:-}"; shift 2 ;;
    --linux-depot-id) linux_depot_id="${2:-}"; shift 2 ;;
    --config) config="${2:-}"; shift 2 ;;
    --windows-config) windows_config="${2:-}"; shift 2 ;;
    --linux-config) linux_config="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage; exit 2 ;;
  esac
done

if [[ "$confirmed" != true ]]; then
  printf 'Refusing upload without the explicit --upload acknowledgement.\n' >&2
  exit 2
fi
for value_name in steamcmd account app_id windows_depot_id linux_depot_id config windows_config linux_config; do
  if [[ -z "${!value_name}" ]]; then
    printf 'Missing required value: %s\n' "$value_name" >&2
    usage
    exit 2
  fi
done

for id_name in app_id windows_depot_id linux_depot_id; do
  id_value="${!id_name}"
  if [[ ! "$id_value" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s must be an explicit positive numeric Steam ID.\n' "$id_name" >&2
    exit 2
  fi
done
if [[ "$app_id" == "$windows_depot_id" || "$app_id" == "$linux_depot_id" || "$windows_depot_id" == "$linux_depot_id" ]]; then
  printf 'App and depot IDs must be distinct.\n' >&2
  exit 2
fi

if [[ "$steamcmd" == */* ]]; then
  steamcmd_path="$steamcmd"
else
  steamcmd_path="$(command -v -- "$steamcmd" || true)"
fi
if [[ -z "$steamcmd_path" || ! -x "$steamcmd_path" ]]; then
  printf 'steamcmd is missing or not executable: %s\n' "$steamcmd" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
	printf 'python3 is required to validate Steam VDF structure.\n' >&2
	exit 1
fi
vdf_validator="$SCRIPT_DIR/validate_vdf.py"
if [[ ! -f "$vdf_validator" ]]; then
	printf 'Steam VDF validator is missing: %s\n' "$vdf_validator" >&2
	exit 1
fi
for config_name in config windows_config linux_config; do
  config_value="${!config_name}"
  if [[ ! -f "$config_value" ]]; then
    printf 'Completed config does not exist: %s\n' "$config_value" >&2
    exit 1
  fi
done
config_path="$(realpath -- "$config")"
windows_config_path="$(realpath -- "$windows_config")"
linux_config_path="$(realpath -- "$linux_config")"
config_text="$(<"$config_path")"
windows_config_text="$(<"$windows_config_path")"
linux_config_text="$(<"$linux_config_path")"
all_config_text="$config_text
$windows_config_text
$linux_config_text"

for placeholder in '<STEAM_APP_ID>' '<WINDOWS_DEPOT_ID>' '<LINUX_DEPOT_ID>' '<CONTENT_ROOT>' '<WINDOWS_DEPOT_CONFIG>' '<LINUX_DEPOT_CONFIG>'; do
  if [[ "$all_config_text" == *"$placeholder"* ]]; then
    printf 'Refusing config with unresolved placeholder: %s\n' "$placeholder" >&2
    exit 1
  fi
done
python3 "$vdf_validator" \
	--app-config "$config_path" \
	--app-id "$app_id" \
	--windows-depot-id "$windows_depot_id" \
	--linux-depot-id "$linux_depot_id" \
	--windows-config "$windows_config_path" \
	--linux-config "$linux_config_path"

exec "$steamcmd_path" +login "$account" +run_app_build "$config_path" +quit

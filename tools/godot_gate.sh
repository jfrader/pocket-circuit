#!/usr/bin/env bash

run_godot_checked() (
	set -o pipefail
	local command_log
	local expected_output="${POCKET_CIRCUIT_EXPECT_OUTPUT:-}"
	command_log="$(mktemp "${TMPDIR:-/tmp}/pocket-circuit-godot.XXXXXX")" || return 1
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
)

run_godot_test_checked() (
	local project_root="$1" godot_bin="$2" test_relative="$3"
	local test_path="$project_root/$test_relative"
	local expected_marker fixed_fps
	expected_marker="$(python3 "$project_root/tools/test_success_marker.py" "$test_path")" || return 1
	fixed_fps="$(python3 "$project_root/tools/test_success_marker.py" --fixed-fps "$test_path")" || return 1
	local clock_args=()
	if [[ -n "$fixed_fps" ]]; then
		clock_args=(--fixed-fps "$fixed_fps")
	fi
	# PC_TEST_TIMEOUT (default 1800s) gives headroom on loaded/shared hosts;
	# a real hang is still killed. Serial tests now share this budget.
	local test_timeout="${PC_TEST_TIMEOUT:-1800}"
	POCKET_CIRCUIT_EXPECT_OUTPUT="$expected_marker" run_godot_checked timeout "$test_timeout" "$godot_bin" \
		--path "$project_root" --headless "${clock_args[@]}" --script "res://$test_relative"
)

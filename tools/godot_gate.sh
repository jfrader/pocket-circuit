#!/usr/bin/env bash

# This file's directory, for gate_owner.py; callers source this file.
GODOT_GATE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

run_godot_checked() (
	set -o pipefail
	local command_log
	local expected_output="${POCKET_CIRCUIT_EXPECT_OUTPUT:-}"
	command_log="$(mktemp "${TMPDIR:-/tmp}/pocket-circuit-godot.XXXXXX")" || return 1
	if ! "$@" 2>&1 | tee "$command_log"; then
		rm -f -- "$command_log"
		return 1
	fi
	if grep -Eq '(^|[[:space:]])(SCRIPT ERROR|ERROR|FAIL):|Assertion failed' "$command_log"; then
		printf 'Godot reported a script error or failed assertion despite returning success.\n' >&2
		rm -f -- "$command_log"
		return 1
	fi
	# The marker counts only at the start of an output line, alone or followed
	# by a space and details ("X_TEST PASS checked=3"). Later shutdown output is
	# allowed; "X_TEST PASS_NOT_FINISHED" or "NOT X_TEST PASS" is not.
	if [[ -n "$expected_output" ]]; then
		local line marker_found=false
		while IFS= read -r line || [[ -n "$line" ]]; do
			if [[ "$line" == "$expected_output" || "$line" == "$expected_output "* ]]; then
				marker_found=true
				break
			fi
		done < "$command_log"
		if ! $marker_found; then
			printf 'Godot did not report the expected success marker: %s\n' "$expected_output" >&2
			rm -f -- "$command_log"
			return 1
		fi
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

# PC_GATE_PARALLELISM must be a plain positive integer; xargs -P 0 would mean
# unlimited and anything else would launch no workers at all.
validate_gate_parallelism() {
	if [[ ! "$1" =~ ^[1-9][0-9]*$ ]]; then
		printf 'Gate parallelism must be a positive integer; got: %q\n' "$1" >&2
		return 1
	fi
}

# Runs one test in its own process with a disposable XDG root and TMPDIR inside
# the gate's scratch directory, so tests touching user:// save files can neither
# collide nor reach the player's data, then appends exactly one PASS/FAIL
# record. Once the gate removes its scratch, a late write fails rather than
# recreating anything.
run_test_isolated() (
	local project_root="$1" godot_bin="$2" scratch_dir="$3" results_file="$4" test_relative="$5"
	local test_dir result=0
	test_dir="$(mktemp -d "$scratch_dir/test.XXXXXX")" || return 1
	mkdir -- "$test_dir/data" "$test_dir/config" "$test_dir/cache" "$test_dir/state" "$test_dir/tmp" \
		|| { rm -rf -- "$test_dir"; return 1; }
	XDG_DATA_HOME="$test_dir/data" XDG_CONFIG_HOME="$test_dir/config" XDG_CACHE_HOME="$test_dir/cache" \
		XDG_STATE_HOME="$test_dir/state" TMPDIR="$test_dir/tmp" \
		run_godot_test_checked "$project_root" "$godot_bin" "$test_relative" >"$test_dir/log" 2>&1 || result=1
	if (( result == 0 )); then
		printf 'PASS %s\n' "$test_relative"
		printf 'PASS\t%s\n' "$test_relative" >> "$results_file" || result=1
	else
		printf 'FAIL %s\n' "$test_relative" >&2
		printf 'FAIL\t%s\n' "$test_relative" >> "$results_file"
		sed 's/^/  /' "$test_dir/log" >&2
	fi
	rm -rf -- "$test_dir"
	return "$result"
)

# Runs a command under gate_owner.py, which kills and reaps every process the
# command leaves behind (even below a SIGKILLed worker) before returning. It
# runs in the background so a trapped signal can interrupt the wait.
run_owned() {
	python3 "$GODOT_GATE_DIR/gate_owner.py" "$@" &
	gate_owner_pid=$!
	local status=0
	wait "$gate_owner_pid" || status=$?
	gate_owner_pid=
	return "$status"
}

# Signal trap for run_gate_tests: stop the owner, and with it every test
# process, before exiting so the exit trap removes scratch nothing still uses.
stop_gate_owner() {
	if [[ -n "${gate_owner_pid:-}" ]]; then
		kill -TERM "$gate_owner_pid" 2>/dev/null || true
		wait "$gate_owner_pid" || true
	fi
	exit "$1"
}

# Runs the source test gate: the listed serial tests one at a time, the rest in
# parallel, each isolated by run_test_isolated. Every scheduled test must record
# exactly one result, so a worker that never launched, was killed or recorded
# twice fails the gate, and so does a test leaving processes running or any
# worker error not explained by a recorded test failure. All failures are listed
# before returning non-zero. Results are read only after every process the
# tests started has ended, and all scratch lives in one directory removed on
# exit or on HUP, INT or TERM.
# Usage: run_gate_tests <project-root> <godot-bin> <parallelism> [serial-test...] -- <test...>
run_gate_tests() (
	local project_root="$1" godot_bin="$2" parallelism="$3"
	shift 3
	local serial_tests=() parallel_tests=() failed=()
	while (( $# > 0 )) && [[ "$1" != -- ]]; do
		serial_tests+=("$1")
		shift
	done
	if (( $# == 0 )); then
		printf 'run_gate_tests: missing -- before the test list\n' >&2
		return 2
	fi
	shift
	local scheduled=("$@")
	validate_gate_parallelism "$parallelism" || return 1
	if (( ${#scheduled[@]} == 0 )); then
		printf 'No gate tests were scheduled.\n' >&2
		return 1
	fi
	local -A is_scheduled=() is_serial=()
	local test_relative serial
	for test_relative in "${scheduled[@]}"; do
		if [[ -n "${is_scheduled[$test_relative]:-}" ]]; then
			printf 'Gate test scheduled twice: %s\n' "$test_relative" >&2
			return 1
		fi
		is_scheduled[$test_relative]=1
	done
	for serial in "${serial_tests[@]}"; do
		is_serial[$serial]=1
	done

	local scratch results_file gate_owner_pid=
	scratch="$(mktemp -d "${TMPDIR:-/tmp}/pocket-circuit-gate.XXXXXX")" || return 1
	trap 'rm -rf -- "$scratch"' EXIT
	trap 'stop_gate_owner 129' HUP
	trap 'stop_gate_owner 130' INT
	trap 'stop_gate_owner 143' TERM
	results_file="$scratch/results"
	: > "$results_file" || return 1
	export -f run_godot_checked run_godot_test_checked run_test_isolated

	# Serial tests run alone, outside xargs, but isolated like the others.
	# Status 1 is a failure the test recorded; anything else means its worker
	# died or left processes running.
	local serial_result
	for test_relative in "${scheduled[@]}"; do
		if [[ -z "${is_serial[$test_relative]:-}" ]]; then
			parallel_tests+=("$test_relative")
			continue
		fi
		printf 'Running %s...\n' "$test_relative"
		serial_result=0
		run_owned bash -c 'run_test_isolated "$@"' _ \
			"$project_root" "$godot_bin" "$scratch" "$results_file" "$test_relative" \
			|| serial_result=$?
		if (( serial_result > 1 )); then
			failed+=("serial gate worker for $test_relative did not complete (exit $serial_result)")
		fi
	done

	local xargs_result=0
	if (( ${#parallel_tests[@]} > 0 )); then
		printf 'Running %d gate tests with parallelism %s...\n' "${#parallel_tests[@]}" "$parallelism"
		printf '%s\0' "${parallel_tests[@]}" > "$scratch/parallel-tests" || return 1
		run_owned xargs -0 -a "$scratch/parallel-tests" -P "$parallelism" -I{} bash -c 'run_test_isolated "$@"' _ \
			"$project_root" "$godot_bin" "$scratch" "$results_file" {} \
			|| xargs_result=$?
	fi

	local -A passes=() failures=()
	local outcome
	while IFS=$'\t' read -r outcome test_relative; do
		if [[ -z "$test_relative" || -z "${is_scheduled[$test_relative]:-}" ]]; then
			failed+=("unexpected gate result record: $outcome $test_relative")
		elif [[ "$outcome" == PASS ]]; then
			passes[$test_relative]=$(( ${passes[$test_relative]:-0} + 1 ))
		elif [[ "$outcome" == FAIL ]]; then
			failures[$test_relative]=$(( ${failures[$test_relative]:-0} + 1 ))
		else
			failed+=("unexpected gate result record: $outcome $test_relative")
		fi
	done < "$results_file"

	local pass_count fail_count
	for test_relative in "${scheduled[@]}"; do
		pass_count="${passes[$test_relative]:-0}"
		fail_count="${failures[$test_relative]:-0}"
		if (( pass_count == 1 && fail_count == 0 )); then
			continue
		elif (( pass_count == 0 && fail_count == 1 )); then
			failed+=("$test_relative")
		elif (( pass_count == 0 && fail_count == 0 )); then
			failed+=("$test_relative (no result recorded; its worker never finished)")
		else
			failed+=("$test_relative (duplicate results: $pass_count PASS, $fail_count FAIL)")
		fi
	done
	# xargs exits 123 when a worker returned 1-125, which recorded failures
	# explain; any other non-zero status means workers failed to run or died,
	# or (125 from gate_owner.py) left processes running.
	if (( xargs_result != 0 )) && ! (( xargs_result == 123 && ${#failed[@]} > 0 )); then
		failed+=("parallel gate workers did not all complete (xargs exit $xargs_result)")
	fi

	if (( ${#failed[@]} > 0 )); then
		printf 'Gate tests failed:\n' >&2
		printf '  %s\n' "${failed[@]}" >&2
		return 1
	fi
)

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

# Runs one test in its own process and user-data dir, so tests touching user://
# save files cannot collide, then appends exactly one PASS/FAIL record.
run_test_isolated() (
	local project_root="$1" godot_bin="$2" results_file="$3" test_relative="$4"
	local iso_dir log_file result=0
	iso_dir="$(mktemp -d "${TMPDIR:-/tmp}/pc-test-userdata.XXXXXX")" || return 1
	log_file="$(mktemp "${TMPDIR:-/tmp}/pc-test-log.XXXXXX")" || { rm -rf -- "$iso_dir"; return 1; }
	XDG_DATA_HOME="$iso_dir" run_godot_test_checked "$project_root" "$godot_bin" "$test_relative" >"$log_file" 2>&1 || result=1
	if (( result == 0 )); then
		printf 'PASS %s\n' "$test_relative"
		printf 'PASS\t%s\n' "$test_relative" >> "$results_file" || result=1
	else
		printf 'FAIL %s\n' "$test_relative" >&2
		printf 'FAIL\t%s\n' "$test_relative" >> "$results_file"
		sed 's/^/  /' "$log_file" >&2
	fi
	rm -rf -- "$iso_dir" "$log_file"
	return "$result"
)

# Runs the source test gate: the listed serial tests one at a time, the rest in
# parallel. Every scheduled test must record exactly one result, so a worker
# that never launched, was killed or recorded twice fails the gate, and so does
# any xargs error not explained by a recorded test failure. All failures are
# listed before returning non-zero.
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

	local results_file
	results_file="$(mktemp "${TMPDIR:-/tmp}/pocket-circuit-gate-results.XXXXXX")" || return 1
	for test_relative in "${scheduled[@]}"; do
		if [[ -z "${is_serial[$test_relative]:-}" ]]; then
			parallel_tests+=("$test_relative")
			continue
		fi
		printf 'Running %s...\n' "$test_relative"
		if run_godot_test_checked "$project_root" "$godot_bin" "$test_relative"; then
			printf 'PASS\t%s\n' "$test_relative" >> "$results_file"
		else
			printf 'FAIL\t%s\n' "$test_relative" >> "$results_file"
		fi
	done

	local xargs_result=0
	if (( ${#parallel_tests[@]} > 0 )); then
		printf 'Running %d gate tests with parallelism %s...\n' "${#parallel_tests[@]}" "$parallelism"
		export -f run_godot_checked run_godot_test_checked run_test_isolated
		printf '%s\0' "${parallel_tests[@]}" \
			| xargs -0 -P "$parallelism" -I{} bash -c 'run_test_isolated "$@"' _ \
				"$project_root" "$godot_bin" "$results_file" {} \
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
	rm -f -- "$results_file"

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
	# explain; any other non-zero status means workers failed to run or died.
	if (( xargs_result != 0 )) && ! (( xargs_result == 123 && ${#failed[@]} > 0 )); then
		failed+=("parallel gate workers did not all complete (xargs exit $xargs_result)")
	fi

	if (( ${#failed[@]} > 0 )); then
		printf 'Gate tests failed:\n' >&2
		printf '  %s\n' "${failed[@]}" >&2
		return 1
	fi
)

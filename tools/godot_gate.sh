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

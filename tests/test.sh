#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
GODOT="${GODOT_BIN:-godot}"
TEST_TIMEOUT_SECONDS=${TEST_TIMEOUT_SECONDS:-30}

run_suite() {
    local suite_dir=$1
    local failures=0 found=0
    local test output name status assertions
    shopt -s nullglob
    local tests=("$suite_dir"/*_test.gd)
    shopt -u nullglob
    if (( ${#tests[@]} == 0 )); then
        echo "FAIL: no *_test.gd scripts found in $suite_dir" >&2
        return 1
    fi
    for test in "${tests[@]}"; do
        found=$((found + 1))
        name=$(basename "$test" _test.gd)_test
        output=$(mktemp)
        echo "Running $(basename "$test")..."
        status=0
        timeout --foreground --kill-after=5 "$TEST_TIMEOUT_SECONDS" \
            "$GODOT" --headless --audio-driver Dummy --path "$ROOT_DIR" --script "$test" \
            >"$output" 2>&1 || status=$?
        while IFS= read -r line; do printf '%s\n' "$line"; done < "$output"
        if (( status != 0 )); then
            echo "FAIL: $name exited with status $status" >&2
            failures=$((failures + 1))
        elif grep -Eq '(^|[[:space:]])(ERROR:|SCRIPT ERROR:|FAIL:)' "$output"; then
            echo "FAIL: $name emitted an unexpected engine/test error" >&2
            failures=$((failures + 1))
        elif ! grep -Fxq "PASS gd-audio $name" "$output"; then
            echo "FAIL: $name did not emit its exact pass sentinel" >&2
            failures=$((failures + 1))
        else
            assertions=$(sed -n -E "s/^ASSERTIONS gd-audio $name ([1-9][0-9]*)$/\\1/p" "$output")
            if [[ -z $assertions || $assertions == *$'\n'* ]]; then
                echo "FAIL: $name did not emit one positive assertion-reach count" >&2
                failures=$((failures + 1))
            fi
        fi
        rm -f "$output"
    done
    echo "REACHED gd-audio tests=$found failures=$failures"
    (( failures == 0 ))
}

self_test() {
    local controls=(runtime_error assertion_overwrite parse_failure timeout)
    local control empty_dir
    run_suite "$SCRIPT_DIR/runner_fixtures/pass"
    for control in "${controls[@]}"; do
        local control_timeout=10
        if [[ $control == timeout ]]; then control_timeout=1; fi
        if TEST_TIMEOUT_SECONDS=$control_timeout run_suite "$SCRIPT_DIR/runner_fixtures/$control"; then
            echo "FAIL: runner negative control unexpectedly passed: $control" >&2
            return 1
        fi
        echo "EXPECTED_FAILURE gd-audio runner-control=$control"
    done
    empty_dir=$(mktemp -d)
    if run_suite "$empty_dir"; then
        echo "FAIL: missing-suite negative control unexpectedly passed" >&2
        rm -rf "$empty_dir"
        return 1
    fi
    rm -rf "$empty_dir"
    echo "EXPECTED_FAILURE gd-audio runner-control=missing_suite"
    echo "PASS gd-audio runner_self_test"
}

if [[ ${1:-} == --self-test ]]; then
    self_test
else
    run_suite "$SCRIPT_DIR"
fi

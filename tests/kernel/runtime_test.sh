#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Runtime Utility Tests
# ==============================================================================

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

source "${PROJECT_ROOT}/kernel/kernel.sh"


fail() {

    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}


assert_equals() {

    local expected="${1:-}"
    local actual="${2:-}"
    local message="${3:-Values are not equal.}"


    if [[ "$expected" != "$actual" ]]; then

        printf 'FAIL: %s\n' "$message" >&2
        printf 'Expected: %s\n' "$expected" >&2
        printf 'Actual:   %s\n' "$actual" >&2

        exit 1
    fi
}


stoleus_kernel_initialize


assert_equals \
    "true" \
    "${STOLEUS_RUNTIME_INITIALIZED:-false}" \
    "Runtime subsystem should be initialized."


runtime_timestamp="$(
    stoleus_runtime_now
)"


if [[ ! "$runtime_timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    fail "Runtime UTC timestamp format is incorrect: ${runtime_timestamp}"
fi


runtime_epoch_ms="$(
    stoleus_runtime_now_ms
)"


if [[ ! "$runtime_epoch_ms" =~ ^[0-9]+$ ]]; then
    fail "Runtime epoch-millisecond value should be numeric."
fi


assert_equals \
    "250" \
    "$(stoleus_runtime_duration_ms "1000" "1250")" \
    "Runtime duration calculation is incorrect."


assert_equals \
    "0" \
    "$(stoleus_runtime_duration_ms "1250" "1000")" \
    "Negative Runtime duration should be normalized to zero."


set +e

stoleus_runtime_duration_ms \
    "invalid" \
    "1000" \
    >/dev/null 2>&1

invalid_duration_exit_code=$?

set -e


assert_equals \
    "2" \
    "$invalid_duration_exit_code" \
    "Invalid Runtime duration metadata should return code 2."


assert_equals \
    "$(
        stoleus_runtime_now |
        cut -c 1-10
    )" \
    "$(
        stoleus_execution_now |
        cut -c 1-10
    )" \
    "Execution timestamp wrapper is incompatible with Runtime."


assert_equals \
    "$(
        stoleus_runtime_now |
        cut -c 1-10
    )" \
    "$(
        stoleus_rollback_executor_now |
        cut -c 1-10
    )" \
    "Rollback timestamp wrapper is incompatible with Runtime."


printf '%s\n' \
    "PASS: Runtime Utility tests completed successfully."

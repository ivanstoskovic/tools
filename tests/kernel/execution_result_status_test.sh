#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Execution Result Status Tests
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
stoleus_execution_result_registry_reset


execution_id="execution-test-1"


# ==============================================================================
# Store succeeded, failed, and skipped results.
# ==============================================================================

stoleus_execution_result_registry_append \
    "$execution_id" \
    "execute" \
    "1" \
    "docker" \
    "install" \
    "docker_install" \
    "succeeded" \
    "0" \
    "2026-08-06T20:00:00Z" \
    "2026-08-06T20:00:01Z" \
    "1000"


stoleus_execution_result_registry_append \
    "$execution_id" \
    "execute" \
    "2" \
    "docker" \
    "configure" \
    "docker_configure" \
    "failed" \
    "17" \
    "2026-08-06T20:00:01Z" \
    "2026-08-06T20:00:02Z" \
    "1000"


stoleus_execution_result_registry_append \
    "$execution_id" \
    "dry-run" \
    "3" \
    "docker" \
    "verify" \
    "docker_verify" \
    "skipped" \
    "0" \
    "2026-08-06T20:00:02Z" \
    "2026-08-06T20:00:02Z" \
    "0"


# ==============================================================================
# Field lookup.
# ==============================================================================

assert_equals \
    "docker" \
    "$(stoleus_execution_result_registry_get_field \
        "$execution_id" \
        "1" \
        "plugin-id")" \
    "Execution-result plugin lookup is incorrect."


assert_equals \
    "succeeded" \
    "$(stoleus_execution_result_registry_get_field \
        "$execution_id" \
        "1" \
        "status")" \
    "Execution-result status lookup is incorrect."


# ==============================================================================
# Success predicate.
# ==============================================================================

if ! stoleus_execution_result_registry_is_successful \
    "$execution_id" \
    "1"; then

    fail "Succeeded execution result should be successful."
fi


set +e

stoleus_execution_result_registry_is_successful \
    "$execution_id" \
    "2"

failed_status_exit_code=$?

set -e


assert_equals \
    "1" \
    "$failed_status_exit_code" \
    "Failed execution result should return predicate code 1."


set +e

stoleus_execution_result_registry_is_successful \
    "$execution_id" \
    "3"

skipped_status_exit_code=$?

set -e


assert_equals \
    "1" \
    "$skipped_status_exit_code" \
    "Skipped execution result should return predicate code 1."


# ==============================================================================
# Missing results.
# ==============================================================================

set +e

stoleus_execution_result_registry_is_successful \
    "$execution_id" \
    "99" \
    >/dev/null 2>&1

missing_result_exit_code=$?

set -e


assert_equals \
    "6" \
    "$missing_result_exit_code" \
    "Unknown execution result should return code 6."


# ==============================================================================
# Invalid arguments.
# ==============================================================================

set +e

stoleus_execution_result_registry_is_successful \
    "" \
    "1" \
    >/dev/null 2>&1

missing_execution_id_exit_code=$?

set -e


assert_equals \
    "2" \
    "$missing_execution_id_exit_code" \
    "Missing execution ID should return code 2."


set +e

stoleus_execution_result_registry_get_field \
    "$execution_id" \
    "0" \
    "status" \
    >/dev/null 2>&1

invalid_step_exit_code=$?

set -e


assert_equals \
    "6" \
    "$invalid_step_exit_code" \
    "Invalid execution step should return code 6."


printf '%s\n' \
    "PASS: Execution Result Status tests completed successfully."

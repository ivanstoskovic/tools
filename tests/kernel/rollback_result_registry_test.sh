#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Rollback Result Registry Tests
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


session_id="rollback-session-test"


# ==============================================================================
# Empty Registry.
# ==============================================================================

assert_equals \
    "0" \
    "$(stoleus_rollback_result_registry_get_count)" \
    "Rollback Result Registry should initially be empty."


# ==============================================================================
# Append results.
# ==============================================================================

stoleus_rollback_result_registry_append \
    "$session_id" \
    "execute" \
    "1" \
    "8" \
    "docker" \
    "docker_restore_configuration" \
    "succeeded" \
    "0" \
    "2026-08-07T00:00:00Z" \
    "2026-08-07T00:00:01Z" \
    "1000"


stoleus_rollback_result_registry_append \
    "$session_id" \
    "execute" \
    "2" \
    "7" \
    "docker" \
    "docker_remove" \
    "failed" \
    "19" \
    "2026-08-07T00:00:01Z" \
    "2026-08-07T00:00:02Z" \
    "1000"


stoleus_rollback_result_registry_append \
    "$session_id" \
    "dry-run" \
    "3" \
    "4" \
    "chrony" \
    "chrony_remove" \
    "skipped" \
    "0" \
    "2026-08-07T00:00:02Z" \
    "2026-08-07T00:00:02Z" \
    "0"


assert_equals \
    "3" \
    "$(stoleus_rollback_result_registry_get_count)" \
    "Rollback Result Registry count is incorrect."


assert_equals \
    "failed" \
    "$(stoleus_rollback_result_registry_get_field \
        "$session_id" \
        "2" \
        "status")" \
    "Rollback result status lookup is incorrect."


assert_equals \
    "docker_remove" \
    "$(stoleus_rollback_result_registry_get_field \
        "$session_id" \
        "2" \
        "rollback-function")" \
    "Rollback result function lookup is incorrect."


expected_list="$(
    printf '%s\n' \
        $'1\t8\tdocker\tdocker_restore_configuration\tsucceeded\t0' \
        $'2\t7\tdocker\tdocker_remove\tfailed\t19' \
        $'3\t4\tchrony\tchrony_remove\tskipped\t0'
)"


assert_equals \
    "$expected_list" \
    "$(stoleus_rollback_result_registry_list)" \
    "Rollback Result Registry listing is incorrect."


# ==============================================================================
# Detailed fields.
# ==============================================================================

detailed_first="$(
    stoleus_metadata_collection_get_key_by_index \
        "$STOLEUS_ROLLBACK_RESULT_COLLECTION_ID" \
        "0"
)"


assert_equals \
    "${session_id}@1" \
    "$detailed_first" \
    "Rollback result primary key is incorrect."


# ==============================================================================
# Duplicate results are rejected.
# ==============================================================================

set +e

stoleus_rollback_result_registry_append \
    "$session_id" \
    "execute" \
    "1" \
    "8" \
    "docker" \
    "docker_remove" \
    "succeeded" \
    "0" \
    "2026-08-07T00:00:00Z" \
    "2026-08-07T00:00:01Z" \
    "1000" \
    >/dev/null 2>&1

duplicate_exit_code=$?

set -e


assert_equals \
    "8" \
    "$duplicate_exit_code" \
    "Duplicate rollback result should return code 8."


# ==============================================================================
# Invalid mode and status are rejected.
# ==============================================================================

set +e

stoleus_rollback_result_registry_append \
    "other-session" \
    "preview" \
    "1" \
    "8" \
    "docker" \
    "docker_remove" \
    "succeeded" \
    "0" \
    "2026-08-07T00:00:00Z" \
    "2026-08-07T00:00:01Z" \
    "1000" \
    >/dev/null 2>&1

invalid_mode_exit_code=$?

set -e


assert_equals \
    "6" \
    "$invalid_mode_exit_code" \
    "Invalid rollback-result mode should return code 6."


set +e

stoleus_rollback_result_registry_append \
    "other-session" \
    "execute" \
    "1" \
    "8" \
    "docker" \
    "docker_remove" \
    "unknown" \
    "0" \
    "2026-08-07T00:00:00Z" \
    "2026-08-07T00:00:01Z" \
    "1000" \
    >/dev/null 2>&1

invalid_status_exit_code=$?

set -e


assert_equals \
    "6" \
    "$invalid_status_exit_code" \
    "Invalid rollback-result status should return code 6."


# ==============================================================================
# Invalid step metadata is rejected.
# ==============================================================================

set +e

stoleus_rollback_result_registry_append \
    "other-session" \
    "execute" \
    "0" \
    "8" \
    "docker" \
    "docker_remove" \
    "succeeded" \
    "0" \
    "2026-08-07T00:00:00Z" \
    "2026-08-07T00:00:01Z" \
    "1000" \
    >/dev/null 2>&1

invalid_step_exit_code=$?

set -e


assert_equals \
    "2" \
    "$invalid_step_exit_code" \
    "Invalid rollback-result step should return code 2."


# ==============================================================================
# Reset clears all results.
# ==============================================================================

stoleus_rollback_result_registry_reset


assert_equals \
    "0" \
    "$(stoleus_rollback_result_registry_get_count)" \
    "Rollback Result Registry reset should clear all results."


printf '%s\n' \
    "PASS: Rollback Result Registry tests completed successfully."

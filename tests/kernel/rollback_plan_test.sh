#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Rollback Plan Registry Tests
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


# ==============================================================================
# Empty plan.
# ==============================================================================

assert_equals \
    "0" \
    "$(stoleus_rollback_plan_get_count)" \
    "Rollback Plan should initially be empty."


# ==============================================================================
# Append rollback steps.
# ==============================================================================

stoleus_rollback_plan_append \
    "1" \
    "8" \
    "docker" \
    "docker_restore_configuration"


stoleus_rollback_plan_append \
    "2" \
    "7" \
    "docker" \
    "docker_remove"


stoleus_rollback_plan_append \
    "3" \
    "4" \
    "chrony" \
    "chrony_remove"


assert_equals \
    "3" \
    "$(stoleus_rollback_plan_get_count)" \
    "Rollback Plan count is incorrect."


if ! stoleus_rollback_plan_contains "1"; then
    fail "Rollback Plan step 1 should exist."
fi


if stoleus_rollback_plan_contains "9"; then
    fail "Rollback Plan step 9 should not exist."
fi


assert_equals \
    "8" \
    "$(stoleus_rollback_plan_get_field \
        "1" \
        "execution-step")" \
    "Execution-step lookup is incorrect."


assert_equals \
    "docker_restore_configuration" \
    "$(stoleus_rollback_plan_get_field \
        "1" \
        "rollback-function")" \
    "Rollback-function lookup is incorrect."


expected_list="$(
    printf '%s\n' \
        $'1\t8\tdocker\tdocker_restore_configuration' \
        $'2\t7\tdocker\tdocker_remove' \
        $'3\t4\tchrony\tchrony_remove'
)"


assert_equals \
    "$expected_list" \
    "$(stoleus_rollback_plan_list)" \
    "Rollback Plan listing is incorrect."


# ==============================================================================
# Duplicate rollback steps are rejected.
# ==============================================================================

set +e

stoleus_rollback_plan_append \
    "1" \
    "3" \
    "chrony" \
    "chrony_restore" \
    >/dev/null 2>&1

duplicate_exit_code=$?

set -e


assert_equals \
    "8" \
    "$duplicate_exit_code" \
    "Duplicate rollback step should return conflict code 8."


# ==============================================================================
# Invalid rollback-step values are rejected.
# ==============================================================================

for invalid_value in \
    "" \
    "0" \
    "-1" \
    "1.5" \
    "step-one"; do

    set +e

    stoleus_rollback_plan_append \
        "$invalid_value" \
        "3" \
        "chrony" \
        "chrony_remove" \
        >/dev/null 2>&1

    invalid_exit_code=$?

    set -e


    if [[ -z "$invalid_value" ]]; then
        expected_exit_code="2"
    else
        expected_exit_code="6"
    fi


    assert_equals \
        "$expected_exit_code" \
        "$invalid_exit_code" \
        "Invalid rollback-step '${invalid_value}' returned the wrong code."
done


# ==============================================================================
# Invalid execution-step values are rejected.
# ==============================================================================

for invalid_value in \
    "" \
    "0" \
    "-4" \
    "2.5" \
    "execution-three"; do

    set +e

    stoleus_rollback_plan_append \
        "4" \
        "$invalid_value" \
        "chrony" \
        "chrony_remove" \
        >/dev/null 2>&1

    invalid_exit_code=$?

    set -e


    if [[ -z "$invalid_value" ]]; then
        expected_exit_code="2"
    else
        expected_exit_code="6"
    fi


    assert_equals \
        "$expected_exit_code" \
        "$invalid_exit_code" \
        "Invalid execution-step '${invalid_value}' returned the wrong code."
done


# ==============================================================================
# Invalid plugin and function metadata are rejected.
# ==============================================================================

set +e

stoleus_rollback_plan_append \
    "4" \
    "3" \
    "Docker Plugin" \
    "docker_remove" \
    >/dev/null 2>&1

invalid_plugin_exit_code=$?

set -e


assert_equals \
    "6" \
    "$invalid_plugin_exit_code" \
    "Invalid rollback-plan plugin ID should return code 6."


set +e

stoleus_rollback_plan_append \
    "4" \
    "3" \
    "docker" \
    "docker-remove()" \
    >/dev/null 2>&1

invalid_function_exit_code=$?

set -e


assert_equals \
    "6" \
    "$invalid_function_exit_code" \
    "Invalid rollback function should return code 6."


# ==============================================================================
# Freeze makes the plan immutable.
# ==============================================================================

stoleus_rollback_plan_freeze


if ! stoleus_rollback_plan_is_frozen; then
    fail "Rollback Plan should be frozen."
fi


set +e

stoleus_rollback_plan_append \
    "4" \
    "3" \
    "docker" \
    "docker_remove" \
    >/dev/null 2>&1

frozen_write_exit_code=$?

set -e


assert_equals \
    "8" \
    "$frozen_write_exit_code" \
    "Frozen Rollback Plan should reject writes."


# ==============================================================================
# Reset clears records and restores mutability.
# ==============================================================================

stoleus_rollback_plan_reset


assert_equals \
    "0" \
    "$(stoleus_rollback_plan_get_count)" \
    "Rollback Plan reset should clear all records."


if stoleus_rollback_plan_is_frozen; then
    fail "Rollback Plan should not remain frozen after reset."
fi


stoleus_rollback_plan_append \
    "1" \
    "2" \
    "docker" \
    "docker_remove"


assert_equals \
    "1" \
    "$(stoleus_rollback_plan_get_count)" \
    "Rollback Plan should accept writes after reset."


# ==============================================================================
# API registration.
# ==============================================================================

set +e

rollback_plan_api_visibility="$(
    stoleus_api_get_field \
        "stoleus_rollback_plan_list" \
        "visibility" \
        2>/dev/null
)"

rollback_plan_api_lookup_exit_code=$?

set -e


assert_equals \
    "0" \
    "$rollback_plan_api_lookup_exit_code" \
    "Rollback Plan public API should be registered."


assert_equals \
    "public" \
    "$rollback_plan_api_visibility" \
    "Rollback Plan API visibility is incorrect."


printf '%s\n' \
    "PASS: Rollback Plan Registry tests completed successfully."

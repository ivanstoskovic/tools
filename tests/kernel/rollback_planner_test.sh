#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Rollback Planner Tests
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
stoleus_rollback_planner_initialize

execution_id="execution-rollback-test"
other_execution_id="execution-other-test"


# ==============================================================================
# Rollback mappings.
# ==============================================================================

stoleus_rollback_registry_register \
    "docker" \
    "install" \
    "docker_remove"


stoleus_rollback_registry_register \
    "docker" \
    "configure" \
    "docker_restore_configuration"


stoleus_rollback_registry_register \
    "chrony" \
    "install" \
    "chrony_remove"


# ==============================================================================
# Execution results.
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
    "succeeded" \
    "0" \
    "2026-08-06T20:00:01Z" \
    "2026-08-06T20:00:02Z" \
    "1000"


stoleus_execution_result_registry_append \
    "$execution_id" \
    "execute" \
    "3" \
    "docker" \
    "verify" \
    "docker_verify" \
    "succeeded" \
    "0" \
    "2026-08-06T20:00:02Z" \
    "2026-08-06T20:00:03Z" \
    "1000"


stoleus_execution_result_registry_append \
    "$execution_id" \
    "execute" \
    "4" \
    "chrony" \
    "install" \
    "chrony_install" \
    "failed" \
    "17" \
    "2026-08-06T20:00:03Z" \
    "2026-08-06T20:00:04Z" \
    "1000"


# A different execution must not appear in this rollback plan.
stoleus_execution_result_registry_append \
    "$other_execution_id" \
    "execute" \
    "1" \
    "chrony" \
    "install" \
    "chrony_install" \
    "succeeded" \
    "0" \
    "2026-08-06T21:00:00Z" \
    "2026-08-06T21:00:01Z" \
    "1000"


# ==============================================================================
# Build rollback plan.
# ==============================================================================

stoleus_rollback_planner_build \
    "$execution_id"


if ! stoleus_rollback_planner_is_built; then
    fail "Rollback Planner should report a built plan."
fi


if ! stoleus_rollback_plan_is_frozen; then
    fail "Rollback Plan should be frozen after planning."
fi


assert_equals \
    "$execution_id" \
    "$(stoleus_rollback_planner_get_execution_id)" \
    "Rollback Planner execution ID is incorrect."


assert_equals \
    "2" \
    "$(stoleus_rollback_plan_get_count)" \
    "Rollback Plan should contain two reversible successful actions."


expected_plan="$(
    printf '%s\n' \
        $'1\t2\tdocker\tdocker_restore_configuration' \
        $'2\t1\tdocker\tdocker_remove'
)"


assert_equals \
    "$expected_plan" \
    "$(stoleus_rollback_plan_list)" \
    "Rollback Plan order or content is incorrect."


# ==============================================================================
# Rebuild is rejected.
# ==============================================================================

set +e

stoleus_rollback_planner_build \
    "$execution_id" \
    >/dev/null 2>&1

rebuild_exit_code=$?

set -e


assert_equals \
    "8" \
    "$rebuild_exit_code" \
    "Rebuilding a frozen Rollback Plan should return code 8."


# ==============================================================================
# Reset permits a new build.
# ==============================================================================

stoleus_rollback_planner_reset


if stoleus_rollback_planner_is_built; then
    fail "Rollback Planner should not remain built after reset."
fi


if stoleus_rollback_plan_is_frozen; then
    fail "Rollback Plan should not remain frozen after planner reset."
fi


# ==============================================================================
# Empty rollback plan is valid and frozen.
# ==============================================================================

stoleus_execution_result_registry_reset


stoleus_execution_result_registry_append \
    "$execution_id" \
    "execute" \
    "1" \
    "docker" \
    "verify" \
    "docker_verify" \
    "succeeded" \
    "0" \
    "2026-08-06T22:00:00Z" \
    "2026-08-06T22:00:01Z" \
    "1000"


stoleus_execution_result_registry_append \
    "$execution_id" \
    "execute" \
    "2" \
    "chrony" \
    "install" \
    "chrony_install" \
    "failed" \
    "17" \
    "2026-08-06T22:00:01Z" \
    "2026-08-06T22:00:02Z" \
    "1000"


stoleus_rollback_planner_build \
    "$execution_id"


assert_equals \
    "0" \
    "$(stoleus_rollback_plan_get_count)" \
    "Nonreversible execution should produce an empty Rollback Plan."


if ! stoleus_rollback_plan_is_frozen; then
    fail "Empty Rollback Plan should still be frozen."
fi


# ==============================================================================
# Missing execution ID.
# ==============================================================================

stoleus_rollback_planner_reset


set +e

stoleus_rollback_planner_build \
    "" \
    >/dev/null 2>&1

missing_id_exit_code=$?

set -e


assert_equals \
    "2" \
    "$missing_id_exit_code" \
    "Missing rollback execution ID should return code 2."


printf '%s\n' \
    "PASS: Rollback Planner tests completed successfully."

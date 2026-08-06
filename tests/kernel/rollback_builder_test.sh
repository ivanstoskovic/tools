#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Rollback Plan Builder Tests
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
stoleus_rollback_builder_initialize


# ==============================================================================
# Initial state.
# ==============================================================================

if stoleus_rollback_builder_is_active; then
    fail "Rollback Builder should not initially be active."
fi


if stoleus_rollback_builder_is_finalized; then
    fail "Rollback Builder should not initially be finalized."
fi


assert_equals \
    "0" \
    "$(stoleus_rollback_builder_get_count)" \
    "Rollback Builder should initially contain no actions."


# ==============================================================================
# Add before begin is rejected.
# ==============================================================================

set +e

stoleus_rollback_builder_add \
    "2" \
    "docker" \
    "docker_remove" \
    >/dev/null 2>&1

inactive_add_exit_code=$?

set -e


assert_equals \
    "8" \
    "$inactive_add_exit_code" \
    "Adding before builder begin should return code 8."


# ==============================================================================
# Begin build.
# ==============================================================================

stoleus_rollback_builder_begin


if ! stoleus_rollback_builder_is_active; then
    fail "Rollback Builder should be active after begin."
fi


# ==============================================================================
# Automatic sequencing.
# ==============================================================================

stoleus_rollback_builder_add \
    "8" \
    "docker" \
    "docker_restore_configuration"


stoleus_rollback_builder_add \
    "7" \
    "docker" \
    "docker_remove"


stoleus_rollback_builder_add \
    "4" \
    "chrony" \
    "chrony_remove"


expected_plan="$(
    printf '%s\n' \
        $'1\t8\tdocker\tdocker_restore_configuration' \
        $'2\t7\tdocker\tdocker_remove' \
        $'3\t4\tchrony\tchrony_remove'
)"


assert_equals \
    "$expected_plan" \
    "$(stoleus_rollback_plan_list)" \
    "Rollback Builder sequencing is incorrect."


assert_equals \
    "3" \
    "$(stoleus_rollback_builder_get_count)" \
    "Rollback Builder count is incorrect."


# ==============================================================================
# A second begin while active is rejected.
# ==============================================================================

set +e

stoleus_rollback_builder_begin \
    >/dev/null 2>&1

duplicate_begin_exit_code=$?

set -e


assert_equals \
    "8" \
    "$duplicate_begin_exit_code" \
    "Beginning an active builder should return code 8."


# ==============================================================================
# Finalize freezes the plan.
# ==============================================================================

stoleus_rollback_builder_finalize


if stoleus_rollback_builder_is_active; then
    fail "Rollback Builder should not remain active after finalization."
fi


if ! stoleus_rollback_builder_is_finalized; then
    fail "Rollback Builder should be finalized."
fi


if ! stoleus_rollback_plan_is_frozen; then
    fail "Rollback Plan should be frozen after builder finalization."
fi


# ==============================================================================
# Mutations after finalization are rejected.
# ==============================================================================

set +e

stoleus_rollback_builder_add \
    "3" \
    "docker" \
    "docker_remove" \
    >/dev/null 2>&1

finalized_add_exit_code=$?

set -e


assert_equals \
    "8" \
    "$finalized_add_exit_code" \
    "Finalized builder should reject additional actions."


set +e

stoleus_rollback_builder_finalize \
    >/dev/null 2>&1

duplicate_finalize_exit_code=$?

set -e


assert_equals \
    "8" \
    "$duplicate_finalize_exit_code" \
    "Repeated builder finalization should return code 8."


set +e

stoleus_rollback_builder_begin \
    >/dev/null 2>&1

begin_without_reset_exit_code=$?

set -e


assert_equals \
    "8" \
    "$begin_without_reset_exit_code" \
    "Finalized builder should require reset before another build."


# ==============================================================================
# Reset clears state and permits another build.
# ==============================================================================

stoleus_rollback_builder_reset


if stoleus_rollback_builder_is_active; then
    fail "Rollback Builder should not be active after reset."
fi


if stoleus_rollback_builder_is_finalized; then
    fail "Rollback Builder should not remain finalized after reset."
fi


if stoleus_rollback_plan_is_frozen; then
    fail "Rollback Plan should not remain frozen after builder reset."
fi


assert_equals \
    "0" \
    "$(stoleus_rollback_builder_get_count)" \
    "Rollback Builder reset should clear the plan."


stoleus_rollback_builder_begin


stoleus_rollback_builder_add \
    "2" \
    "docker" \
    "docker_remove"


stoleus_rollback_builder_finalize


expected_rebuilt_plan="$(
    printf '%s\n' \
        $'1\t2\tdocker\tdocker_remove'
)"


assert_equals \
    "$expected_rebuilt_plan" \
    "$(stoleus_rollback_plan_list)" \
    "Rollback Builder did not restart sequencing after reset."


# ==============================================================================
# Empty plans may be finalized.
# ==============================================================================

stoleus_rollback_builder_reset
stoleus_rollback_builder_begin
stoleus_rollback_builder_finalize


assert_equals \
    "0" \
    "$(stoleus_rollback_builder_get_count)" \
    "Empty finalized Rollback Plan should remain valid."


if ! stoleus_rollback_plan_is_frozen; then
    fail "Empty Rollback Plan should be frozen after finalization."
fi


printf '%s\n' \
    "PASS: Rollback Plan Builder tests completed successfully."

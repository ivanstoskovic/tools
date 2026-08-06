#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Rollback Registry Tests
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
# Empty Registry.
# ==============================================================================

assert_equals \
    "0" \
    "$(stoleus_rollback_registry_get_count)" \
    "Rollback Registry should initially be empty."


# ==============================================================================
# Register rollback actions.
# ==============================================================================

stoleus_rollback_registry_register \
    "chrony" \
    "install" \
    "chrony_remove"


stoleus_rollback_registry_register \
    "chrony" \
    "configure" \
    "chrony_restore_configuration"


stoleus_rollback_registry_register \
    "docker" \
    "upgrade" \
    "docker_restore_previous_version"


assert_equals \
    "3" \
    "$(stoleus_rollback_registry_get_count)" \
    "Rollback Registry count is incorrect."


if ! stoleus_rollback_registry_contains \
    "chrony" \
    "install"; then

    fail "Chrony install rollback should exist."
fi


if stoleus_rollback_registry_contains \
    "chrony" \
    "verify"; then

    fail "Chrony verify rollback should not exist."
fi


assert_equals \
    "chrony_remove" \
    "$(stoleus_rollback_registry_get_function \
        "chrony" \
        "install")" \
    "Chrony install rollback function is incorrect."


assert_equals \
    "configure" \
    "$(stoleus_rollback_registry_get_field \
        "chrony" \
        "configure" \
        "forward-stage")" \
    "Rollback forward-stage field lookup is incorrect."


expected_list="$(
    printf '%s\n' \
        $'chrony\tinstall\tchrony_remove' \
        $'chrony\tconfigure\tchrony_restore_configuration' \
        $'docker\tupgrade\tdocker_restore_previous_version'
)"


assert_equals \
    "$expected_list" \
    "$(stoleus_rollback_registry_list)" \
    "Rollback Registry listing is incorrect."


# ==============================================================================
# Duplicate mappings are rejected.
# ==============================================================================

set +e

stoleus_rollback_registry_register \
    "chrony" \
    "install" \
    "chrony_remove_again" \
    >/dev/null 2>&1

duplicate_exit_code=$?

set -e


assert_equals \
    "8" \
    "$duplicate_exit_code" \
    "Duplicate rollback action should return conflict code 8."


# ==============================================================================
# Invalid metadata is rejected.
# ==============================================================================

set +e

stoleus_rollback_registry_register \
    "Chrony Plugin" \
    "install" \
    "chrony_remove" \
    >/dev/null 2>&1

invalid_plugin_exit_code=$?

set -e


assert_equals \
    "6" \
    "$invalid_plugin_exit_code" \
    "Invalid rollback plugin ID should return code 6."


set +e

stoleus_rollback_registry_register \
    "chrony" \
    "enable" \
    "chrony_disable" \
    >/dev/null 2>&1

invalid_stage_exit_code=$?

set -e


assert_equals \
    "6" \
    "$invalid_stage_exit_code" \
    "Unsupported rollback stage should return code 6."


set +e

stoleus_rollback_registry_register \
    "chrony" \
    "remove" \
    "invalid-function()" \
    >/dev/null 2>&1

invalid_function_exit_code=$?

set -e


assert_equals \
    "6" \
    "$invalid_function_exit_code" \
    "Invalid rollback function should return code 6."


# ==============================================================================
# Freeze makes the Registry immutable.
# ==============================================================================

stoleus_rollback_registry_freeze


if ! stoleus_rollback_registry_is_frozen; then
    fail "Rollback Registry should be frozen."
fi


set +e

stoleus_rollback_registry_register \
    "docker" \
    "install" \
    "docker_remove" \
    >/dev/null 2>&1

frozen_write_exit_code=$?

set -e


assert_equals \
    "8" \
    "$frozen_write_exit_code" \
    "Frozen Rollback Registry should reject writes."


# ==============================================================================
# Reset clears records and permits registration again.
# ==============================================================================

stoleus_rollback_registry_reset


assert_equals \
    "0" \
    "$(stoleus_rollback_registry_get_count)" \
    "Rollback Registry reset should clear all records."


if stoleus_rollback_registry_is_frozen; then
    fail "Rollback Registry should not remain frozen after reset."
fi


stoleus_rollback_registry_register \
    "docker" \
    "install" \
    "docker_remove"


assert_equals \
    "1" \
    "$(stoleus_rollback_registry_get_count)" \
    "Rollback Registry should accept writes after reset."


# ==============================================================================
# API registration.
# ==============================================================================

set +e

rollback_api_visibility="$(
    stoleus_api_get_field \
        "stoleus_rollback_registry_get_function" \
        "visibility" \
        2>/dev/null
)"

rollback_api_lookup_exit_code=$?

set -e


assert_equals \
    "0" \
    "$rollback_api_lookup_exit_code" \
    "Rollback Registry public API should be registered."


assert_equals \
    "public" \
    "$rollback_api_visibility" \
    "Rollback Registry lookup API visibility is incorrect."


printf '%s\n' \
    "PASS: Rollback Registry tests completed successfully."

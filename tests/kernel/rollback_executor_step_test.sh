#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Rollback Executor Single-Step Tests
# ==============================================================================

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

TEST_TEMP_ROOT="$(
    mktemp -d
)"

trap 'rm -rf -- "$TEST_TEMP_ROOT"' EXIT


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


mkdir -p \
    "${TEST_TEMP_ROOT}/modules/example"


cat > "${TEST_TEMP_ROOT}/modules/example/manifest.sh" <<'MANIFEST'
#!/usr/bin/env bash

stoleus_plugin_begin "example"

stoleus_plugin_description \
    "Example rollback executor plugin."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_lifecycle \
    "install" \
    "example_install"

stoleus_plugin_end
MANIFEST


cat > "${TEST_TEMP_ROOT}/modules/example/implementation.sh" <<'IMPLEMENTATION'
#!/usr/bin/env bash

example_install() {

    return 0
}


example_restore_configuration() {

    printf '%s\n' \
        "restore-configuration" \
        >> "$STOLEUS_ROLLBACK_EXECUTOR_STEP_LOG"

    return 0
}


example_failed_rollback() {

    printf '%s\n' \
        "failed-rollback" \
        >> "$STOLEUS_ROLLBACK_EXECUTOR_STEP_LOG"

    return 23
}
IMPLEMENTATION


export STOLEUS_ROLLBACK_EXECUTOR_STEP_LOG="${TEST_TEMP_ROOT}/rollback.log"

: > "$STOLEUS_ROLLBACK_EXECUTOR_STEP_LOG"


source "${PROJECT_ROOT}/kernel/kernel.sh"


stoleus_kernel_initialize


# ==============================================================================
# Configure the test plugin Registry.
# ==============================================================================

STOLEUS_DISCOVERY_ROOT_CATEGORIES=()
STOLEUS_DISCOVERY_ROOT_PATHS=()


stoleus_discovery_reset
stoleus_definition_reset
stoleus_registry_reset
stoleus_resolver_reset
stoleus_plugin_reset
stoleus_lifecycle_reset


stoleus_discovery_add_root \
    "modules" \
    "${TEST_TEMP_ROOT}/modules"


stoleus_kernel_bootstrap


# ==============================================================================
# Create a frozen rollback plan.
# ==============================================================================

prepare_rollback_plan() {

    local rollback_function="${1:-example_restore_configuration}"


    stoleus_rollback_builder_reset
    stoleus_rollback_builder_begin

    stoleus_rollback_builder_add \
        "7" \
        "example" \
        "$rollback_function"

    stoleus_rollback_builder_finalize
}


prepare_executor() {

    local session_id="${1:-rollback-step-session}"


    stoleus_rollback_result_registry_reset
    stoleus_rollback_executor_reset

    stoleus_rollback_executor_begin \
        "$session_id"
}


# ==============================================================================
# Successful rollback execution.
# ==============================================================================

prepare_rollback_plan \
    "example_restore_configuration"

prepare_executor \
    "rollback-success-session"


stoleus_rollback_executor_execute_step \
    "1" \
    "execute"


assert_equals \
    "restore-configuration" \
    "$(cat "$STOLEUS_ROLLBACK_EXECUTOR_STEP_LOG")" \
    "Rollback function was not invoked."


assert_equals \
    "1" \
    "$(stoleus_rollback_result_registry_get_count)" \
    "Successful rollback should create one result."


assert_equals \
    "succeeded" \
    "$(stoleus_rollback_result_registry_get_field \
        "rollback-success-session" \
        "1" \
        "status")" \
    "Successful rollback result status is incorrect."


assert_equals \
    "0" \
    "$(stoleus_rollback_result_registry_get_field \
        "rollback-success-session" \
        "1" \
        "exit-code")" \
    "Successful rollback exit code is incorrect."


assert_equals \
    "7" \
    "$(stoleus_rollback_result_registry_get_field \
        "rollback-success-session" \
        "1" \
        "execution-step")" \
    "Original execution-step reference is incorrect."


duration_ms="$(
    stoleus_rollback_result_registry_get_field \
        "rollback-success-session" \
        "1" \
        "duration-ms"
)"


if [[ ! "$duration_ms" =~ ^[0-9]+$ ]]; then
    fail "Rollback duration should be numeric."
fi


stoleus_rollback_executor_finish


# ==============================================================================
# Dry-run records skipped and does not invoke the function.
# ==============================================================================

: > "$STOLEUS_ROLLBACK_EXECUTOR_STEP_LOG"

stoleus_rollback_builder_reset
prepare_rollback_plan \
    "example_restore_configuration"

prepare_executor \
    "rollback-dry-run-session"


stoleus_rollback_executor_execute_step \
    "1" \
    "dry-run"


if [[ -s "$STOLEUS_ROLLBACK_EXECUTOR_STEP_LOG" ]]; then
    fail "Dry-run must not invoke the rollback function."
fi


assert_equals \
    "skipped" \
    "$(stoleus_rollback_result_registry_get_field \
        "rollback-dry-run-session" \
        "1" \
        "status")" \
    "Dry-run rollback status is incorrect."


assert_equals \
    "0" \
    "$(stoleus_rollback_result_registry_get_field \
        "rollback-dry-run-session" \
        "1" \
        "exit-code")" \
    "Dry-run rollback exit code is incorrect."


stoleus_rollback_executor_finish


# ==============================================================================
# Failed rollback preserves function exit code.
# ==============================================================================

: > "$STOLEUS_ROLLBACK_EXECUTOR_STEP_LOG"

stoleus_rollback_builder_reset
prepare_rollback_plan \
    "example_failed_rollback"

prepare_executor \
    "rollback-failure-session"


set +e

stoleus_rollback_executor_execute_step \
    "1" \
    "execute"

failed_rollback_exit_code=$?

set -e


assert_equals \
    "23" \
    "$failed_rollback_exit_code" \
    "Failed rollback should preserve the function exit code."


assert_equals \
    "failed" \
    "$(stoleus_rollback_result_registry_get_field \
        "rollback-failure-session" \
        "1" \
        "status")" \
    "Failed rollback result status is incorrect."


assert_equals \
    "23" \
    "$(stoleus_rollback_result_registry_get_field \
        "rollback-failure-session" \
        "1" \
        "exit-code")" \
    "Failed rollback result exit code is incorrect."


stoleus_rollback_executor_finish


# ==============================================================================
# Executor must be running.
# ==============================================================================

stoleus_rollback_executor_reset


set +e

stoleus_rollback_executor_execute_step \
    "1" \
    "execute" \
    >/dev/null 2>&1

idle_executor_exit_code=$?

set -e


assert_equals \
    "8" \
    "$idle_executor_exit_code" \
    "Idle Rollback Executor should reject step execution."


# ==============================================================================
# Invalid mode is rejected.
# ==============================================================================

prepare_executor \
    "rollback-invalid-mode-session"


set +e

stoleus_rollback_executor_execute_step \
    "1" \
    "preview" \
    >/dev/null 2>&1

invalid_mode_exit_code=$?

set -e


assert_equals \
    "2" \
    "$invalid_mode_exit_code" \
    "Invalid rollback execution mode should return code 2."


# ==============================================================================
# Unknown plan step is rejected.
# ==============================================================================

set +e

stoleus_rollback_executor_execute_step \
    "99" \
    "execute" \
    >/dev/null 2>&1

unknown_step_exit_code=$?

set -e


assert_equals \
    "6" \
    "$unknown_step_exit_code" \
    "Unknown rollback-plan step should return code 6."


# ==============================================================================
# Unfrozen plan is rejected.
# ==============================================================================

stoleus_rollback_executor_finish
stoleus_rollback_executor_reset
stoleus_rollback_executor_begin \
    "rollback-unfrozen-session"

stoleus_rollback_builder_reset
stoleus_rollback_builder_begin


set +e

stoleus_rollback_executor_execute_step \
    "1" \
    "execute" \
    >/dev/null 2>&1

unfrozen_plan_exit_code=$?

set -e


assert_equals \
    "6" \
    "$unfrozen_plan_exit_code" \
    "Unfrozen Rollback Plan should return code 6."


printf '%s\n' \
    "PASS: Rollback Executor Single-Step tests completed successfully."

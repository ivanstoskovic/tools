#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Rollback Executor Failure Policy Tests
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
    "Rollback failure-policy test plugin."

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


example_rollback_first() {

    printf '%s\n' "first" \
        >> "$STOLEUS_ROLLBACK_POLICY_TEST_LOG"

    return 0
}


example_rollback_failure() {

    printf '%s\n' "failure" \
        >> "$STOLEUS_ROLLBACK_POLICY_TEST_LOG"

    return 31
}


example_rollback_last() {

    printf '%s\n' "last" \
        >> "$STOLEUS_ROLLBACK_POLICY_TEST_LOG"

    return 0
}
IMPLEMENTATION


export STOLEUS_ROLLBACK_POLICY_TEST_LOG="${TEST_TEMP_ROOT}/rollback-policy.log"

: > "$STOLEUS_ROLLBACK_POLICY_TEST_LOG"


source "${PROJECT_ROOT}/kernel/kernel.sh"


stoleus_kernel_initialize


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


build_policy_plan() {

    stoleus_rollback_builder_reset
    stoleus_rollback_builder_begin

    stoleus_rollback_builder_add \
        "8" \
        "example" \
        "example_rollback_first"

    stoleus_rollback_builder_add \
        "7" \
        "example" \
        "example_rollback_failure"

    stoleus_rollback_builder_add \
        "6" \
        "example" \
        "example_rollback_last"

    stoleus_rollback_builder_finalize
}


reset_policy_runtime() {

    stoleus_rollback_executor_reset
    stoleus_rollback_result_registry_reset

    : > "$STOLEUS_ROLLBACK_POLICY_TEST_LOG"
}


# ==============================================================================
# Default stop policy.
# ==============================================================================

build_policy_plan


set +e

stoleus_rollback_executor_execute_plan

stop_exit_code=$?

set -e


assert_equals \
    "31" \
    "$stop_exit_code" \
    "Stop policy should preserve the first failure code."


expected_stop_log="$(
    printf '%s\n' \
        "first" \
        "failure"
)"


assert_equals \
    "$expected_stop_log" \
    "$(cat "$STOLEUS_ROLLBACK_POLICY_TEST_LOG")" \
    "Stop policy should not execute later rollback steps."


assert_equals \
    "2" \
    "$(stoleus_rollback_result_registry_get_count)" \
    "Stop policy should record only attempted steps."


IFS=$'\t' read -r \
    stop_session_id \
    stop_mode \
    stop_policy \
    stop_running \
    stop_completed \
    stop_failed_count \
    stop_status_exit_code \
    <<< "$(stoleus_rollback_executor_get_status)"


assert_equals \
    "stop" \
    "$stop_policy" \
    "Default Rollback Executor policy is incorrect."


assert_equals \
    "1" \
    "$stop_failed_count" \
    "Stop-policy failed-step count is incorrect."


assert_equals \
    "31" \
    "$stop_status_exit_code" \
    "Stop-policy status exit code is incorrect."


# ==============================================================================
# Continue policy.
# ==============================================================================

reset_policy_runtime

stoleus_rollback_builder_reset
build_policy_plan


set +e

stoleus_rollback_executor_execute_plan \
    --failure-policy continue

continue_exit_code=$?

set -e


assert_equals \
    "31" \
    "$continue_exit_code" \
    "Continue policy should return the first failure code."


expected_continue_log="$(
    printf '%s\n' \
        "first" \
        "failure" \
        "last"
)"


assert_equals \
    "$expected_continue_log" \
    "$(cat "$STOLEUS_ROLLBACK_POLICY_TEST_LOG")" \
    "Continue policy should execute all rollback steps."


assert_equals \
    "3" \
    "$(stoleus_rollback_result_registry_get_count)" \
    "Continue policy should record every rollback step."


IFS=$'\t' read -r \
    continue_session_id \
    continue_mode \
    continue_policy \
    continue_running \
    continue_completed \
    continue_failed_count \
    continue_status_exit_code \
    <<< "$(stoleus_rollback_executor_get_status)"


assert_equals \
    "continue" \
    "$continue_policy" \
    "Continue Rollback Executor policy is incorrect."


assert_equals \
    "false" \
    "$continue_running" \
    "Continue execution should not remain running."


assert_equals \
    "true" \
    "$continue_completed" \
    "Continue execution should complete after all steps."


assert_equals \
    "1" \
    "$continue_failed_count" \
    "Continue failed-step count is incorrect."


assert_equals \
    "31" \
    "$continue_status_exit_code" \
    "Continue status should retain the first failure code."


# ==============================================================================
# Equals-style option.
# ==============================================================================

reset_policy_runtime

stoleus_rollback_builder_reset
build_policy_plan


set +e

stoleus_rollback_executor_execute_plan \
    --failure-policy=continue

equals_exit_code=$?

set -e


assert_equals \
    "31" \
    "$equals_exit_code" \
    "Equals-style continue option is incorrect."


assert_equals \
    "3" \
    "$(stoleus_rollback_result_registry_get_count)" \
    "Equals-style continue should execute all steps."


# ==============================================================================
# Invalid and duplicate policies.
# ==============================================================================

reset_policy_runtime

stoleus_rollback_builder_reset
build_policy_plan


set +e

stoleus_rollback_executor_execute_plan \
    --failure-policy ignore \
    >/dev/null 2>&1

invalid_policy_exit_code=$?

set -e


assert_equals \
    "2" \
    "$invalid_policy_exit_code" \
    "Invalid rollback failure policy should return code 2."


if stoleus_rollback_executor_is_running ||
   stoleus_rollback_executor_is_completed; then

    fail "Invalid policy must not transition executor state."
fi


set +e

stoleus_rollback_executor_execute_plan \
    --failure-policy stop \
    --failure-policy continue \
    >/dev/null 2>&1

duplicate_policy_exit_code=$?

set -e


assert_equals \
    "2" \
    "$duplicate_policy_exit_code" \
    "Duplicate rollback failure policies should return code 2."


printf '%s\n' \
    "PASS: Rollback Executor Failure Policy tests completed successfully."

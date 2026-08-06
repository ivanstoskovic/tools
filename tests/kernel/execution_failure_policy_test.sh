#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Execution Failure Policy Tests
# ==============================================================================

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

source "${PROJECT_ROOT}/kernel/kernel.sh"


declare -a EXECUTED_PLUGINS=()


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


prepare_plan() {

    stoleus_execution_reset

    EXECUTED_PLUGINS=()

    STOLEUS_PLANNING_INITIALIZED="true"
    STOLEUS_PLANNING_REQUEST_CREATED="true"
    STOLEUS_PLANNING_REQUEST_TARGET="target"
    STOLEUS_PLANNING_REQUEST_OPERATION="setup"
    STOLEUS_PLANNING_REQUEST_ARGUMENTS=()

    STOLEUS_PLAN_FROZEN="true"

    STOLEUS_PLAN_STEP_PLUGIN_IDS=(
        "first"
        "failing"
        "last"
    )

    STOLEUS_PLAN_STEP_REGISTRY_INDEXES=(
        "0"
        "1"
        "2"
    )

    STOLEUS_PLAN_STEP_STAGES=(
        "install"
        "configure"
        "verify"
    )

    STOLEUS_PLAN_STEP_FUNCTIONS=(
        "first_install"
        "failing_configure"
        "last_verify"
    )

    STOLEUS_PLAN_STEP_RECEIVES_ARGUMENTS=(
        "false"
        "false"
        "false"
    )

    STOLEUS_LIFECYCLE_INITIALIZED="true"
}


stoleus_kernel_initialize


stoleus_lifecycle_invoke() {

    local plugin_id="${1:-}"


    EXECUTED_PLUGINS+=("$plugin_id")


    if [[ "$plugin_id" == "failing" ]]; then
        return 17
    fi


    return 0
}


# ==============================================================================
# Default stop policy.
# ==============================================================================

prepare_plan


set +e

stoleus_execution_execute_plan

stop_exit_code=$?

set -e


assert_equals \
    "17" \
    "$stop_exit_code" \
    "Stop policy should preserve the failing lifecycle exit code."


expected_stop_plugins="$(
    printf '%s\n' \
        "first" \
        "failing"
)"


assert_equals \
    "$expected_stop_plugins" \
    "$(printf '%s\n' "${EXECUTED_PLUGINS[@]}")" \
    "Stop policy should not execute steps after failure."


assert_equals \
    "2" \
    "$(stoleus_execution_result_registry_get_count)" \
    "Stop policy should record only attempted steps."


stop_session="$(
    stoleus_execution_get_session
)"


IFS=$'\t' read -r \
    stop_execution_id \
    stop_mode \
    stop_policy \
    stop_status \
    stop_target \
    stop_operation \
    stop_started_at \
    stop_finished_at \
    stop_current_step \
    stop_total_steps \
    stop_failed_step_count \
    stop_session_exit_code \
    <<< "$stop_session"


assert_equals \
    "stop" \
    "$stop_policy" \
    "Default failure policy is incorrect."


assert_equals \
    "failed" \
    "$stop_status" \
    "Stop-policy session should fail."


assert_equals \
    "1" \
    "$stop_failed_step_count" \
    "Stop-policy failed-step count is incorrect."


assert_equals \
    "17" \
    "$stop_session_exit_code" \
    "Stop-policy session exit code is incorrect."


# ==============================================================================
# Continue policy.
# ==============================================================================

prepare_plan


set +e

stoleus_execution_execute_plan \
    --failure-policy continue

continue_exit_code=$?

set -e


assert_equals \
    "17" \
    "$continue_exit_code" \
    "Continue policy should return the first failing exit code."


expected_continue_plugins="$(
    printf '%s\n' \
        "first" \
        "failing" \
        "last"
)"


assert_equals \
    "$expected_continue_plugins" \
    "$(printf '%s\n' "${EXECUTED_PLUGINS[@]}")" \
    "Continue policy should execute all remaining steps."


assert_equals \
    "3" \
    "$(stoleus_execution_result_registry_get_count)" \
    "Continue policy should record all attempted steps."


expected_continue_results="$(
    printf '%s\n' \
        $'1\tfirst\tinstall\tfirst_install\tsucceeded\t0' \
        $'2\tfailing\tconfigure\tfailing_configure\tfailed\t17' \
        $'3\tlast\tverify\tlast_verify\tsucceeded\t0'
)"


assert_equals \
    "$expected_continue_results" \
    "$(stoleus_execution_get_results)" \
    "Continue-policy result output is incorrect."


continue_session="$(
    stoleus_execution_get_session
)"


IFS=$'\t' read -r \
    continue_execution_id \
    continue_mode \
    continue_policy \
    continue_status \
    continue_target \
    continue_operation \
    continue_started_at \
    continue_finished_at \
    continue_current_step \
    continue_total_steps \
    continue_failed_step_count \
    continue_session_exit_code \
    <<< "$continue_session"


assert_equals \
    "continue" \
    "$continue_policy" \
    "Continue session policy is incorrect."


assert_equals \
    "failed" \
    "$continue_status" \
    "Continue session must remain failed when any step fails."


assert_equals \
    "3" \
    "$continue_current_step" \
    "Continue session should finish on the last step."


assert_equals \
    "1" \
    "$continue_failed_step_count" \
    "Continue failed-step count is incorrect."


assert_equals \
    "17" \
    "$continue_session_exit_code" \
    "Continue session should retain the first failure code."


# ==============================================================================
# Equals-style option parsing.
# ==============================================================================

prepare_plan


set +e

stoleus_execution_execute_plan \
    --failure-policy=continue

equals_style_exit_code=$?

set -e


assert_equals \
    "17" \
    "$equals_style_exit_code" \
    "Equals-style failure-policy parsing is incorrect."


assert_equals \
    "3" \
    "${#EXECUTED_PLUGINS[@]}" \
    "Equals-style continue policy should execute all steps."


# ==============================================================================
# Invalid policies are rejected before execution.
# ==============================================================================

prepare_plan


set +e

stoleus_execution_execute_plan \
    --failure-policy ignore \
    >/dev/null 2>&1

invalid_policy_exit_code=$?

set -e


assert_equals \
    "2" \
    "$invalid_policy_exit_code" \
    "Invalid failure policy should return code 2."


assert_equals \
    "false" \
    "${STOLEUS_EXECUTION_STARTED:-false}" \
    "Invalid policy must not start execution."


# ==============================================================================
# Duplicate policy options are rejected.
# ==============================================================================

prepare_plan


set +e

stoleus_execution_execute_plan \
    --failure-policy stop \
    --failure-policy continue \
    >/dev/null 2>&1

duplicate_policy_exit_code=$?

set -e


assert_equals \
    "2" \
    "$duplicate_policy_exit_code" \
    "Duplicate failure-policy options should return code 2."


printf '%s\n' \
    "PASS: Execution Failure Policy tests completed successfully."

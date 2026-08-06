#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Execution Session Tests
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
stoleus_execution_reset


# ==============================================================================
# Create a deterministic frozen two-step plan.
# ==============================================================================

STOLEUS_PLANNING_INITIALIZED="true"
STOLEUS_PLANNING_REQUEST_CREATED="true"
STOLEUS_PLANNING_REQUEST_TARGET="example-target"
STOLEUS_PLANNING_REQUEST_OPERATION="setup"
STOLEUS_PLANNING_REQUEST_ARGUMENTS=("argument-one")

STOLEUS_PLAN_FROZEN="true"

STOLEUS_PLAN_STEP_PLUGIN_IDS=(
    "dependency"
    "example-target"
)

STOLEUS_PLAN_STEP_REGISTRY_INDEXES=(
    "0"
    "1"
)

STOLEUS_PLAN_STEP_STAGES=(
    "install"
    "configure"
)

STOLEUS_PLAN_STEP_FUNCTIONS=(
    "dependency_install"
    "target_configure"
)

STOLEUS_PLAN_STEP_RECEIVES_ARGUMENTS=(
    "false"
    "true"
)

STOLEUS_LIFECYCLE_INITIALIZED="true"


# Replace Lifecycle dispatch only inside this test process.
stoleus_lifecycle_invoke() {

    return 0
}


# ==============================================================================
# No session exists before execution.
# ==============================================================================

set +e

stoleus_execution_get_session \
    >/dev/null 2>&1

missing_session_exit_code=$?

set -e


assert_equals \
    "6" \
    "$missing_session_exit_code" \
    "Session lookup before execution should return code 6."


# ==============================================================================
# Successful session.
# ==============================================================================

stoleus_execution_execute_plan


session="$(
    stoleus_execution_get_session
)"


IFS=$'\t' read -r \
    execution_id \
    status \
    target \
    operation \
    started_at \
    finished_at \
    current_step \
    total_steps \
    exit_code \
    <<< "$session"


if [[ -z "$execution_id" ]]; then
    fail "Execution session ID should not be empty."
fi


assert_equals \
    "succeeded" \
    "$status" \
    "Successful execution session status is incorrect."


assert_equals \
    "example-target" \
    "$target" \
    "Execution session target is incorrect."


assert_equals \
    "setup" \
    "$operation" \
    "Execution session operation is incorrect."


if [[ -z "$started_at" || -z "$finished_at" ]]; then
    fail "Execution session timestamps should be populated."
fi


assert_equals \
    "2" \
    "$current_step" \
    "Execution session current step is incorrect."


assert_equals \
    "2" \
    "$total_steps" \
    "Execution session total step count is incorrect."


assert_equals \
    "0" \
    "$exit_code" \
    "Successful execution session exit code is incorrect."


# ==============================================================================
# Reset clears the completed session.
# ==============================================================================

stoleus_execution_reset


assert_equals \
    "not-started" \
    "$STOLEUS_EXECUTION_SESSION_STATUS" \
    "Execution reset should clear session status."


if [[ -n "$STOLEUS_EXECUTION_SESSION_ID" ]]; then
    fail "Execution reset should clear session ID."
fi


# ==============================================================================
# Failed session records the failing step and exit code.
# ==============================================================================

STOLEUS_PLANNING_INITIALIZED="true"
STOLEUS_PLANNING_REQUEST_CREATED="true"
STOLEUS_PLANNING_REQUEST_TARGET="example-target"
STOLEUS_PLANNING_REQUEST_OPERATION="setup"

STOLEUS_PLAN_FROZEN="true"

STOLEUS_PLAN_STEP_PLUGIN_IDS=(
    "dependency"
    "example-target"
)

STOLEUS_PLAN_STEP_REGISTRY_INDEXES=(
    "0"
    "1"
)

STOLEUS_PLAN_STEP_STAGES=(
    "install"
    "configure"
)

STOLEUS_PLAN_STEP_FUNCTIONS=(
    "dependency_install"
    "target_configure"
)

STOLEUS_PLAN_STEP_RECEIVES_ARGUMENTS=(
    "false"
    "true"
)

STOLEUS_LIFECYCLE_INITIALIZED="true"


stoleus_lifecycle_invoke() {

    local plugin_id="${1:-}"


    if [[ "$plugin_id" == "example-target" ]]; then
        return 17
    fi


    return 0
}


set +e

stoleus_execution_execute_plan

failed_execution_exit_code=$?

set -e


assert_equals \
    "17" \
    "$failed_execution_exit_code" \
    "Failed execution should preserve the lifecycle exit code."


failed_session="$(
    stoleus_execution_get_session
)"


IFS=$'\t' read -r \
    failed_execution_id \
    failed_status \
    failed_target \
    failed_operation \
    failed_started_at \
    failed_finished_at \
    failed_current_step \
    failed_total_steps \
    failed_exit_code \
    <<< "$failed_session"


assert_equals \
    "failed" \
    "$failed_status" \
    "Failed execution session status is incorrect."


assert_equals \
    "2" \
    "$failed_current_step" \
    "Failed session should identify the failing step."


assert_equals \
    "17" \
    "$failed_exit_code" \
    "Failed session exit code is incorrect."


printf '%s\n' \
    "PASS: Execution Session tests completed successfully."

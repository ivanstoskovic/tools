#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Execution Dry-Run Tests
# ==============================================================================

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

source "${PROJECT_ROOT}/kernel/kernel.sh"


LIFECYCLE_CALL_COUNT=0


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

    STOLEUS_PLANNING_INITIALIZED="true"
    STOLEUS_PLANNING_REQUEST_CREATED="true"
    STOLEUS_PLANNING_REQUEST_TARGET="docker"
    STOLEUS_PLANNING_REQUEST_OPERATION="setup"
    STOLEUS_PLANNING_REQUEST_ARGUMENTS=("production")

    STOLEUS_PLAN_FROZEN="true"

    STOLEUS_PLAN_STEP_PLUGIN_IDS=(
        "package-manager"
        "docker"
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
        "package_manager_install"
        "docker_configure"
    )

    STOLEUS_PLAN_STEP_RECEIVES_ARGUMENTS=(
        "false"
        "true"
    )

    STOLEUS_LIFECYCLE_INITIALIZED="true"
}


stoleus_kernel_initialize


stoleus_lifecycle_invoke() {

    LIFECYCLE_CALL_COUNT="$((LIFECYCLE_CALL_COUNT + 1))"

    return 0
}


# ==============================================================================
# Dry-run traverses the plan without invoking Lifecycle.
# ==============================================================================

prepare_plan


stoleus_execution_execute_plan \
    --dry-run


assert_equals \
    "0" \
    "$LIFECYCLE_CALL_COUNT" \
    "Dry-run must not invoke lifecycle functions."


expected_results="$(
    printf '%s\n' \
        $'1\tpackage-manager\tinstall\tpackage_manager_install\tskipped\t0' \
        $'2\tdocker\tconfigure\tdocker_configure\tskipped\t0'
)"


assert_equals \
    "$expected_results" \
    "$(stoleus_execution_get_results)" \
    "Dry-run results are incorrect."


session="$(
    stoleus_execution_get_session
)"


IFS=$'\t' read -r \
    execution_id \
    mode \
    failure_policy \
    status \
    target \
    operation \
    started_at \
    finished_at \
    current_step \
    total_steps \
    failed_step_count \
    exit_code \
    <<< "$session"


if [[ -z "$execution_id" ]]; then
    fail "Dry-run execution ID should not be empty."
fi


assert_equals \
    "dry-run" \
    "$mode" \
    "Dry-run session mode is incorrect."


assert_equals \
    "stop" \
    "$failure_policy" \
    "Dry-run default failure policy is incorrect."




assert_equals \
    "succeeded" \
    "$status" \
    "Dry-run session status is incorrect."


assert_equals \
    "docker" \
    "$target" \
    "Dry-run session target is incorrect."


assert_equals \
    "setup" \
    "$operation" \
    "Dry-run session operation is incorrect."


assert_equals \
    "2" \
    "$current_step" \
    "Dry-run current step is incorrect."


assert_equals \
    "2" \
    "$total_steps" \
    "Dry-run total step count is incorrect."


assert_equals \
    "0" \
    "$exit_code" \
    "Dry-run session exit code is incorrect."


# ==============================================================================
# Repeated execution remains forbidden.
# ==============================================================================

set +e

stoleus_execution_execute_plan \
    --dry-run \
    >/dev/null 2>&1

repeat_exit_code=$?

set -e


assert_equals \
    "8" \
    "$repeat_exit_code" \
    "Repeated dry-run should return conflict code 8."


# ==============================================================================
# Unsupported arguments are rejected before execution starts.
# ==============================================================================

prepare_plan


set +e

stoleus_execution_execute_plan \
    --preview \
    >/dev/null 2>&1

unsupported_exit_code=$?

set -e


assert_equals \
    "2" \
    "$unsupported_exit_code" \
    "Unsupported execution arguments should return code 2."


assert_equals \
    "false" \
    "${STOLEUS_EXECUTION_STARTED:-false}" \
    "Invalid arguments must not start execution."


# ==============================================================================
# Normal execution remains unchanged.
# ==============================================================================

prepare_plan
LIFECYCLE_CALL_COUNT=0


stoleus_execution_execute_plan


assert_equals \
    "2" \
    "$LIFECYCLE_CALL_COUNT" \
    "Normal execution should invoke every lifecycle function."


expected_execute_results="$(
    printf '%s\n' \
        $'1\tpackage-manager\tinstall\tpackage_manager_install\tsucceeded\t0' \
        $'2\tdocker\tconfigure\tdocker_configure\tsucceeded\t0'
)"


assert_equals \
    "$expected_execute_results" \
    "$(stoleus_execution_get_results)" \
    "Normal execution results changed after dry-run support."


printf '%s\n' \
    "PASS: Execution Dry-Run tests completed successfully."

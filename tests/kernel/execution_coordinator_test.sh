#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Execution Coordinator Tests
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


prepare_running_session() {

    stoleus_execution_reset

    STOLEUS_PLANNING_REQUEST_TARGET="example"
    STOLEUS_PLANNING_REQUEST_OPERATION="install"
    STOLEUS_PLAN_STEP_PLUGIN_IDS=("example")


    stoleus_execution_start_session \
        "execute" \
        "stop"
}


stoleus_kernel_initialize


# ==============================================================================
# Coordinator is loaded and initialized.
# ==============================================================================

assert_equals \
    "true" \
    "${STOLEUS_EXECUTION_COORDINATOR_INITIALIZED:-false}" \
    "Execution Coordinator should be initialized."


# ==============================================================================
# Successful finalization.
# ==============================================================================

prepare_running_session


stoleus_execution_coordinator_finalize_success


assert_equals \
    "true" \
    "${STOLEUS_EXECUTION_COMPLETED:-false}" \
    "Successful coordination should mark execution completed."


assert_equals \
    "true" \
    "${STOLEUS_EXECUTION_SUCCEEDED:-false}" \
    "Successful coordination should mark execution succeeded."


assert_equals \
    "succeeded" \
    "$STOLEUS_EXECUTION_SESSION_STATUS" \
    "Successful session status is incorrect."


assert_equals \
    "0" \
    "$STOLEUS_EXECUTION_SESSION_EXIT_CODE" \
    "Successful session exit code is incorrect."


# ==============================================================================
# Failed finalization.
# ==============================================================================

prepare_running_session


stoleus_execution_coordinator_finalize_failure \
    "17"


assert_equals \
    "true" \
    "${STOLEUS_EXECUTION_COMPLETED:-false}" \
    "Failed coordination should mark execution completed."


assert_equals \
    "false" \
    "${STOLEUS_EXECUTION_SUCCEEDED:-true}" \
    "Failed coordination should mark execution unsuccessful."


assert_equals \
    "failed" \
    "$STOLEUS_EXECUTION_SESSION_STATUS" \
    "Failed session status is incorrect."


assert_equals \
    "17" \
    "$STOLEUS_EXECUTION_SESSION_EXIT_CODE" \
    "Failed session exit code is incorrect."


# ==============================================================================
# Invalid failure code.
# ==============================================================================

prepare_running_session


set +e

stoleus_execution_coordinator_finalize_failure \
    "0" \
    >/dev/null 2>&1

invalid_failure_code=$?

set -e


assert_equals \
    "2" \
    "$invalid_failure_code" \
    "Zero failure code should be rejected."


assert_equals \
    "running" \
    "$STOLEUS_EXECUTION_SESSION_STATUS" \
    "Rejected finalization must leave the session running."


# ==============================================================================
# Finalization requires a running session.
# ==============================================================================

stoleus_execution_complete_session \
    "failed" \
    "17"


set +e

stoleus_execution_coordinator_finalize_success \
    >/dev/null 2>&1

completed_session_exit_code=$?

set -e


assert_equals \
    "8" \
    "$completed_session_exit_code" \
    "Completed sessions should reject further coordination."


printf '%s\n' \
    "PASS: Execution Coordinator tests completed successfully."

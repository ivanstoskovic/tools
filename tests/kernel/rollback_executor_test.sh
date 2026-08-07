#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Rollback Executor State Tests
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


# ==============================================================================
# Uninitialized transitions are rejected.
# ==============================================================================

set +e

stoleus_rollback_executor_begin \
    "rollback-session-before-init" \
    >/dev/null 2>&1

begin_before_initialize_exit_code=$?

set -e


assert_equals \
    "6" \
    "$begin_before_initialize_exit_code" \
    "Beginning before initialization should return code 6."


set +e

stoleus_rollback_executor_finish \
    >/dev/null 2>&1

finish_before_initialize_exit_code=$?

set -e


assert_equals \
    "6" \
    "$finish_before_initialize_exit_code" \
    "Finishing before initialization should return code 6."


set +e

stoleus_rollback_executor_reset \
    >/dev/null 2>&1

reset_before_initialize_exit_code=$?

set -e


assert_equals \
    "6" \
    "$reset_before_initialize_exit_code" \
    "Resetting before initialization should return code 6."


# ==============================================================================
# Initialization is idempotent.
# ==============================================================================

stoleus_kernel_initialize


stoleus_rollback_executor_initialize
stoleus_rollback_executor_initialize


assert_equals \
    "true" \
    "${STOLEUS_ROLLBACK_EXECUTOR_INITIALIZED:-false}" \
    "Rollback Executor should be initialized."


if stoleus_rollback_executor_is_running; then
    fail "Rollback Executor should not initially be running."
fi


if stoleus_rollback_executor_is_completed; then
    fail "Rollback Executor should not initially be completed."
fi


# ==============================================================================
# Session ID is unavailable before begin.
# ==============================================================================

set +e

stoleus_rollback_executor_get_session_id \
    >/dev/null 2>&1

missing_session_exit_code=$?

set -e


assert_equals \
    "6" \
    "$missing_session_exit_code" \
    "Session lookup before begin should return code 6."


# ==============================================================================
# Missing session ID is rejected.
# ==============================================================================

set +e

stoleus_rollback_executor_begin \
    "" \
    >/dev/null 2>&1

missing_begin_session_exit_code=$?

set -e


assert_equals \
    "2" \
    "$missing_begin_session_exit_code" \
    "Beginning without a session ID should return code 2."


# ==============================================================================
# Begin transitions executor to running.
# ==============================================================================

session_id="rollback-session-001"


stoleus_rollback_executor_begin \
    "$session_id"


if ! stoleus_rollback_executor_is_running; then
    fail "Rollback Executor should be running after begin."
fi


if stoleus_rollback_executor_is_completed; then
    fail "Rollback Executor should not be completed while running."
fi


assert_equals \
    "$session_id" \
    "$(stoleus_rollback_executor_get_session_id)" \
    "Rollback Executor session ID is incorrect."


# ==============================================================================
# Duplicate begin is rejected.
# ==============================================================================

set +e

stoleus_rollback_executor_begin \
    "rollback-session-002" \
    >/dev/null 2>&1

duplicate_begin_exit_code=$?

set -e


assert_equals \
    "8" \
    "$duplicate_begin_exit_code" \
    "Beginning while running should return code 8."


assert_equals \
    "$session_id" \
    "$(stoleus_rollback_executor_get_session_id)" \
    "Rejected duplicate begin must not replace the active session ID."


# ==============================================================================
# Reset while running is rejected.
# ==============================================================================

set +e

stoleus_rollback_executor_reset \
    >/dev/null 2>&1

running_reset_exit_code=$?

set -e


assert_equals \
    "8" \
    "$running_reset_exit_code" \
    "Resetting while running should return code 8."


if ! stoleus_rollback_executor_is_running; then
    fail "Rejected reset must not stop the running executor."
fi


# ==============================================================================
# Finish transitions executor to completed.
# ==============================================================================

stoleus_rollback_executor_finish


if stoleus_rollback_executor_is_running; then
    fail "Rollback Executor should not remain running after finish."
fi


if ! stoleus_rollback_executor_is_completed; then
    fail "Rollback Executor should be completed after finish."
fi


assert_equals \
    "$session_id" \
    "$(stoleus_rollback_executor_get_session_id)" \
    "Completed executor should preserve its session ID."


# ==============================================================================
# Duplicate finish is rejected.
# ==============================================================================

set +e

stoleus_rollback_executor_finish \
    >/dev/null 2>&1

duplicate_finish_exit_code=$?

set -e


assert_equals \
    "8" \
    "$duplicate_finish_exit_code" \
    "Finishing a completed executor should return code 8."


# ==============================================================================
# Completed executor requires reset before another begin.
# ==============================================================================

set +e

stoleus_rollback_executor_begin \
    "rollback-session-002" \
    >/dev/null 2>&1

begin_after_completion_exit_code=$?

set -e


assert_equals \
    "8" \
    "$begin_after_completion_exit_code" \
    "Completed executor should reject begin before reset."


# ==============================================================================
# Reset clears completed state and session identity.
# ==============================================================================

stoleus_rollback_executor_reset


if stoleus_rollback_executor_is_running; then
    fail "Rollback Executor should not be running after reset."
fi


if stoleus_rollback_executor_is_completed; then
    fail "Rollback Executor should not remain completed after reset."
fi


if [[ -n "${STOLEUS_ROLLBACK_EXECUTOR_SESSION_ID:-}" ]]; then
    fail "Rollback Executor reset should clear the session ID."
fi


# ==============================================================================
# Reset is idempotent while idle.
# ==============================================================================

stoleus_rollback_executor_reset


assert_equals \
    "false" \
    "${STOLEUS_ROLLBACK_EXECUTOR_RUNNING:-false}" \
    "Repeated reset should preserve idle running state."


assert_equals \
    "false" \
    "${STOLEUS_ROLLBACK_EXECUTOR_COMPLETED:-false}" \
    "Repeated reset should preserve idle completed state."


# ==============================================================================
# A new session may start after reset.
# ==============================================================================

second_session_id="rollback-session-002"


stoleus_rollback_executor_begin \
    "$second_session_id"


assert_equals \
    "$second_session_id" \
    "$(stoleus_rollback_executor_get_session_id)" \
    "Rollback Executor did not accept a new session after reset."


stoleus_rollback_executor_finish


printf '%s\n' \
    "PASS: Rollback Executor State tests completed successfully."

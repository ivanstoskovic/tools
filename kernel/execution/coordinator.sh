#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Execution Coordinator
# ==============================================================================
#
# Purpose:
#     Coordinate final execution state transitions without performing forward
#     step execution itself.
#
# Current responsibilities:
#
#     - finalize successful forward execution;
#     - finalize failed forward execution;
#     - preserve the original forward failure exit code.
#
# Future responsibilities:
#
#     - automatic rollback orchestration;
#     - rollback-status propagation;
#     - retry and recovery coordination;
#     - resumable execution coordination.
#
# Internal API:
#
#     stoleus_execution_coordinator_initialize
#     stoleus_execution_coordinator_finalize_success
#     stoleus_execution_coordinator_finalize_failure
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_EXECUTION_COORDINATOR_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_EXECUTION_COORDINATOR_LOADED="true"


# ==============================================================================
# stoleus_execution_coordinator_require_running_session
# ==============================================================================

stoleus_execution_coordinator_require_running_session() {

    if [[ "${STOLEUS_EXECUTION_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Execution subsystem must be initialized before coordination." \
            >&2

        return 6
    fi


    if [[ "${STOLEUS_EXECUTION_SESSION_STATUS:-not-started}" != "running" ]]; then

        printf '%s\n' \
            "ERROR: Execution Coordinator requires a running execution session." \
            >&2

        return 8
    fi


    return 0
}


# ==============================================================================
# stoleus_execution_coordinator_run_automatic_rollback
# ==============================================================================

stoleus_execution_coordinator_run_automatic_rollback() {

    local rollback_plan_count=0
    local rollback_exit_code=0


    STOLEUS_EXECUTION_SESSION_ROLLBACK_ATTEMPTED="true"


    stoleus_rollback_planner_reset || {
        rollback_exit_code=$?
        STOLEUS_EXECUTION_SESSION_ROLLBACK_STATUS="failed"
        STOLEUS_EXECUTION_SESSION_ROLLBACK_EXIT_CODE="$rollback_exit_code"
        return 0
    }


    stoleus_rollback_planner_build \
        "$STOLEUS_EXECUTION_SESSION_ID" || {

        rollback_exit_code=$?
        STOLEUS_EXECUTION_SESSION_ROLLBACK_STATUS="failed"
        STOLEUS_EXECUTION_SESSION_ROLLBACK_EXIT_CODE="$rollback_exit_code"

        return 0
    }


    rollback_plan_count="$(
        stoleus_rollback_plan_get_count
    )" || {

        rollback_exit_code=$?
        STOLEUS_EXECUTION_SESSION_ROLLBACK_STATUS="failed"
        STOLEUS_EXECUTION_SESSION_ROLLBACK_EXIT_CODE="$rollback_exit_code"

        return 0
    }


    if (( rollback_plan_count == 0 )); then

        STOLEUS_EXECUTION_SESSION_ROLLBACK_STATUS="empty"
        STOLEUS_EXECUTION_SESSION_ROLLBACK_EXIT_CODE=0

        return 0
    fi


    stoleus_rollback_executor_reset || {

        rollback_exit_code=$?
        STOLEUS_EXECUTION_SESSION_ROLLBACK_STATUS="failed"
        STOLEUS_EXECUTION_SESSION_ROLLBACK_EXIT_CODE="$rollback_exit_code"

        return 0
    }


    if stoleus_rollback_executor_execute_plan; then

        STOLEUS_EXECUTION_SESSION_ROLLBACK_STATUS="succeeded"
        STOLEUS_EXECUTION_SESSION_ROLLBACK_EXIT_CODE=0

    else
        rollback_exit_code=$?

        STOLEUS_EXECUTION_SESSION_ROLLBACK_STATUS="failed"
        STOLEUS_EXECUTION_SESSION_ROLLBACK_EXIT_CODE="$rollback_exit_code"
    fi


    return 0
}


# ==============================================================================
# stoleus_execution_coordinator_finalize_success
# ==============================================================================

stoleus_execution_coordinator_finalize_success() {

    stoleus_execution_coordinator_require_running_session || return $?


    STOLEUS_EXECUTION_COMPLETED="true"
    STOLEUS_EXECUTION_SUCCEEDED="true"


    stoleus_execution_complete_session \
        "succeeded" \
        "0" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_execution_coordinator_finalize_failure
# ==============================================================================
#
# Arguments:
#
#     $1 = original forward-execution failure code
#
# The original forward failure code remains authoritative. Future rollback
# failures must be recorded separately and must not replace this value.
# ==============================================================================

stoleus_execution_coordinator_finalize_failure() {

    local forward_exit_code="${1:-}"


    stoleus_execution_coordinator_require_running_session || return $?


    if [[ -z "$forward_exit_code" ||
          ! "$forward_exit_code" =~ ^[1-9][0-9]*$ ]]; then

        printf '%s\n' \
            "ERROR: Failure finalization requires a nonzero numeric exit code." \
            >&2

        return 2
    fi


    if [[ "${STOLEUS_EXECUTION_SESSION_AUTOMATIC_ROLLBACK:-false}" == "true" ]] &&
       [[ "${STOLEUS_EXECUTION_SESSION_MODE:-execute}" == "execute" ]]; then

        stoleus_execution_coordinator_run_automatic_rollback || return $?
    fi


    STOLEUS_EXECUTION_COMPLETED="true"
    STOLEUS_EXECUTION_SUCCEEDED="false"


    stoleus_execution_complete_session \
        "failed" \
        "$forward_exit_code" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_execution_coordinator_initialize
# ==============================================================================

stoleus_execution_coordinator_initialize() {

    if [[ "${STOLEUS_EXECUTION_COORDINATOR_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    STOLEUS_EXECUTION_COORDINATOR_INITIALIZED="true"


    return 0
}

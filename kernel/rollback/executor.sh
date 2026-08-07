#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Rollback Executor
# ==============================================================================
#
# Purpose:
#     Own the lifecycle and state transitions of one rollback execution session.
#
# State machine:
#
#     initialized
#         ↓ begin
#     running
#         ↓ finish
#     completed
#         ↓ reset
#     initialized
#
# This phase does not execute rollback-plan actions.
#
# Internal API:
#
#     stoleus_rollback_executor_initialize
#     stoleus_rollback_executor_reset
#     stoleus_rollback_executor_begin
#     stoleus_rollback_executor_finish
#     stoleus_rollback_executor_is_running
#     stoleus_rollback_executor_is_completed
#     stoleus_rollback_executor_get_session_id
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_ROLLBACK_EXECUTOR_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_ROLLBACK_EXECUTOR_SUBSYSTEM_LOADED="true"


# ==============================================================================
# State
# ==============================================================================

STOLEUS_ROLLBACK_EXECUTOR_INITIALIZED="false"
STOLEUS_ROLLBACK_EXECUTOR_RUNNING="false"
STOLEUS_ROLLBACK_EXECUTOR_COMPLETED="false"
STOLEUS_ROLLBACK_EXECUTOR_SESSION_ID=""
STOLEUS_ROLLBACK_EXECUTOR_MODE="execute"
STOLEUS_ROLLBACK_EXECUTOR_FAILURE_POLICY="stop"
STOLEUS_ROLLBACK_EXECUTOR_FAILED_STEP_COUNT=0
STOLEUS_ROLLBACK_EXECUTOR_EXIT_CODE=0


# ==============================================================================
# stoleus_rollback_executor_reset
# ==============================================================================

stoleus_rollback_executor_reset() {

    if [[ "${STOLEUS_ROLLBACK_EXECUTOR_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Rollback Executor must be initialized before reset." >&2

        return 6
    fi


    if stoleus_rollback_executor_is_running; then

        printf '%s\n' \
            "ERROR: Running Rollback Executor cannot be reset." >&2

        return 8
    fi


    STOLEUS_ROLLBACK_EXECUTOR_RUNNING="false"
    STOLEUS_ROLLBACK_EXECUTOR_COMPLETED="false"
    STOLEUS_ROLLBACK_EXECUTOR_SESSION_ID=""
    STOLEUS_ROLLBACK_EXECUTOR_MODE="execute"
    STOLEUS_ROLLBACK_EXECUTOR_FAILURE_POLICY="stop"
    STOLEUS_ROLLBACK_EXECUTOR_FAILED_STEP_COUNT=0
    STOLEUS_ROLLBACK_EXECUTOR_EXIT_CODE=0


    return 0
}


# ==============================================================================
# stoleus_rollback_executor_is_running
# ==============================================================================

stoleus_rollback_executor_is_running() {

    [[ "${STOLEUS_ROLLBACK_EXECUTOR_RUNNING:-false}" == "true" ]]
}


# ==============================================================================
# stoleus_rollback_executor_is_completed
# ==============================================================================

stoleus_rollback_executor_is_completed() {

    [[ "${STOLEUS_ROLLBACK_EXECUTOR_COMPLETED:-false}" == "true" ]]
}


# ==============================================================================
# stoleus_rollback_executor_begin
# ==============================================================================

stoleus_rollback_executor_begin() {

    local rollback_session_id="${1:-}"
    local mode="${2:-execute}"
    local failure_policy="${3:-stop}"


    if [[ "${STOLEUS_ROLLBACK_EXECUTOR_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Rollback Executor must be initialized before begin." >&2

        return 6
    fi


    if [[ -z "$rollback_session_id" ]]; then

        printf '%s\n' \
            "ERROR: Rollback Executor begin requires a session ID." >&2

        return 2
    fi


    case "$mode" in

        execute|dry-run)
            ;;

        *)

            printf '%s\n' \
                "ERROR: Unsupported rollback execution mode: ${mode}" >&2

            return 2

            ;;
    esac


    case "$failure_policy" in

        stop|continue)
            ;;

        *)

            printf '%s\n' \
                "ERROR: Unsupported rollback failure policy: ${failure_policy}" \
                >&2

            return 2

            ;;
    esac


    if stoleus_rollback_executor_is_running; then

        printf '%s\n' \
            "ERROR: Rollback Executor is already running." >&2

        return 8
    fi


    if stoleus_rollback_executor_is_completed; then

        printf '%s\n' \
            "ERROR: Completed Rollback Executor must be reset before another session." \
            >&2

        return 8
    fi


    STOLEUS_ROLLBACK_EXECUTOR_SESSION_ID="$rollback_session_id"
    STOLEUS_ROLLBACK_EXECUTOR_MODE="$mode"
    STOLEUS_ROLLBACK_EXECUTOR_FAILURE_POLICY="$failure_policy"
    STOLEUS_ROLLBACK_EXECUTOR_FAILED_STEP_COUNT=0
    STOLEUS_ROLLBACK_EXECUTOR_EXIT_CODE=0

    STOLEUS_ROLLBACK_EXECUTOR_RUNNING="true"
    STOLEUS_ROLLBACK_EXECUTOR_COMPLETED="false"


    return 0
}


# ==============================================================================
# stoleus_rollback_executor_finish
# ==============================================================================

stoleus_rollback_executor_finish() {

    if [[ "${STOLEUS_ROLLBACK_EXECUTOR_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Rollback Executor must be initialized before finish." >&2

        return 6
    fi


    if ! stoleus_rollback_executor_is_running; then

        printf '%s\n' \
            "ERROR: Rollback Executor is not running." >&2

        return 8
    fi


    STOLEUS_ROLLBACK_EXECUTOR_RUNNING="false"
    STOLEUS_ROLLBACK_EXECUTOR_COMPLETED="true"


    return 0
}


# ==============================================================================
# stoleus_rollback_executor_get_session_id
# ==============================================================================

stoleus_rollback_executor_get_session_id() {

    if [[ -z "${STOLEUS_ROLLBACK_EXECUTOR_SESSION_ID:-}" ]]; then

        printf '%s\n' \
            "ERROR: Rollback Executor has no session ID." >&2

        return 6
    fi


    printf '%s\n' \
        "$STOLEUS_ROLLBACK_EXECUTOR_SESSION_ID"

    return 0
}


# ==============================================================================
# stoleus_rollback_executor_get_status
# ==============================================================================
#
# Output fields:
#
#     session-id
#     mode
#     failure-policy
#     running
#     completed
#     failed-step-count
#     exit-code
# ==============================================================================

stoleus_rollback_executor_get_status() {

    if [[ -z "${STOLEUS_ROLLBACK_EXECUTOR_SESSION_ID:-}" ]]; then

        printf '%s\n' \
            "ERROR: Rollback Executor has no active or completed session." >&2

        return 6
    fi


    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$STOLEUS_ROLLBACK_EXECUTOR_SESSION_ID" \
        "$STOLEUS_ROLLBACK_EXECUTOR_MODE" \
        "$STOLEUS_ROLLBACK_EXECUTOR_FAILURE_POLICY" \
        "$STOLEUS_ROLLBACK_EXECUTOR_RUNNING" \
        "$STOLEUS_ROLLBACK_EXECUTOR_COMPLETED" \
        "$STOLEUS_ROLLBACK_EXECUTOR_FAILED_STEP_COUNT" \
        "$STOLEUS_ROLLBACK_EXECUTOR_EXIT_CODE"

    return 0
}


# ==============================================================================
# stoleus_rollback_executor_now
# ==============================================================================
#
# Output:
#
#     UTC timestamp in YYYY-MM-DDTHH:MM:SSZ format.
# ==============================================================================

stoleus_rollback_executor_now() {

    stoleus_runtime_now

    return $?
}


# ==============================================================================
# stoleus_rollback_executor_now_ms
# ==============================================================================
#
# Output:
#
#     Milliseconds since the Unix epoch.
# ==============================================================================

stoleus_rollback_executor_now_ms() {

    stoleus_runtime_now_ms

    return $?
}


# ==============================================================================
# stoleus_rollback_executor_require_plan
# ==============================================================================

stoleus_rollback_executor_require_plan() {

    if [[ "${STOLEUS_ROLLBACK_PLAN_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Rollback Plan must be initialized before rollback execution." \
            >&2

        return 6
    fi


    if ! stoleus_rollback_plan_is_frozen; then

        printf '%s\n' \
            "ERROR: Rollback execution requires a frozen Rollback Plan." >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_rollback_executor_execute_step
# ==============================================================================
#
# Arguments:
#
#     $1 = rollback step number
#     $2 = execution mode: execute or dry-run
#
# Return:
#
#     0              rollback succeeded or was skipped in dry-run
#     nonzero        rollback function or validation failure code
# ==============================================================================

stoleus_rollback_executor_execute_step() {

    local rollback_step="${1:-}"
    local mode="${2:-execute}"

    local execution_step=""
    local plugin_id=""
    local rollback_function=""
    local registry_index=""

    local started_at=""
    local finished_at=""
    local started_ms=0
    local finished_ms=0
    local duration_ms=0

    local status=""
    local exit_code=0


    if [[ "${STOLEUS_ROLLBACK_EXECUTOR_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Rollback Executor must be initialized before step execution." \
            >&2

        return 6
    fi


    if ! stoleus_rollback_executor_is_running; then

        printf '%s\n' \
            "ERROR: Rollback Executor must be running before executing a step." \
            >&2

        return 8
    fi


    if [[ -z "$rollback_step" ||
          ! "$rollback_step" =~ ^[1-9][0-9]*$ ]]; then

        printf '%s\n' \
            "ERROR: Rollback step must be a positive integer." >&2

        return 2
    fi


    case "$mode" in

        execute|dry-run)
            ;;

        *)

            printf '%s\n' \
                "ERROR: Unsupported rollback execution mode: ${mode}" >&2

            return 2

            ;;
    esac


    stoleus_rollback_executor_require_plan || return $?


    execution_step="$(
        stoleus_rollback_plan_get_field \
            "$rollback_step" \
            "execution-step"
    )" || return $?


    plugin_id="$(
        stoleus_rollback_plan_get_field \
            "$rollback_step" \
            "plugin-id"
    )" || return $?


    rollback_function="$(
        stoleus_rollback_plan_get_field \
            "$rollback_step" \
            "rollback-function"
    )" || return $?


    registry_index="$(
        stoleus_registry_get_index \
            "$plugin_id"
    )" || return $?


    started_at="$(
        stoleus_rollback_executor_now
    )" || return $?


    started_ms="$(
        stoleus_rollback_executor_now_ms
    )" || return $?


    if [[ "$mode" == "dry-run" ]]; then

        status="skipped"
        exit_code=0

    else

        if stoleus_lifecycle_invoke_function \
            "$plugin_id" \
            "$registry_index" \
            "$rollback_function"; then

            exit_code=0
            status="succeeded"

        else
            exit_code=$?
            status="failed"
        fi
    fi


    finished_at="$(
        stoleus_rollback_executor_now
    )" || return $?


    finished_ms="$(
        stoleus_rollback_executor_now_ms
    )" || return $?


    duration_ms="$(
        stoleus_runtime_duration_ms             "$started_ms"             "$finished_ms"
    )" || return $?


    stoleus_rollback_result_registry_append \
        "$STOLEUS_ROLLBACK_EXECUTOR_SESSION_ID" \
        "$mode" \
        "$rollback_step" \
        "$execution_step" \
        "$plugin_id" \
        "$rollback_function" \
        "$status" \
        "$exit_code" \
        "$started_at" \
        "$finished_at" \
        "$duration_ms" ||
        return $?


    return "$exit_code"
}


# ==============================================================================
# stoleus_rollback_executor_create_session_id
# ==============================================================================

stoleus_rollback_executor_create_session_id() {

    local timestamp=""


    timestamp="$(
        date -u '+%Y%m%dT%H%M%S%N'
    )" || return $?


    printf 'rollback-%s-%s\n' \
        "$timestamp" \
        "$$"

    return 0
}


# ==============================================================================
# stoleus_rollback_executor_execute_plan
# ==============================================================================
#
# Supported arguments:
#
#     no arguments    execute rollback functions
#     --dry-run       traverse plan and record skipped results
#
# Failure behavior:
#
#     Stop immediately after the first failed rollback step.
# ==============================================================================

stoleus_rollback_executor_execute_plan() {

    local mode="execute"
    local failure_policy="stop"

    local dry_run_seen="false"
    local failure_policy_seen="false"

    local argument=""
    local policy_value=""

    local rollback_session_id=""
    local rollback_step_count=0
    local rollback_step=0

    local step_exit_code=0
    local first_failure_exit_code=0
    local failed_step_count=0


    # --------------------------------------------------------------------------
    # Parse options.
    # --------------------------------------------------------------------------
    while (( $# > 0 )); do

        argument="$1"

        case "$argument" in

            --dry-run)

                if [[ "$dry_run_seen" == "true" ]]; then

                    printf '%s\n' \
                        "ERROR: --dry-run may be supplied only once." >&2

                    return 2
                fi


                dry_run_seen="true"
                mode="dry-run"

                shift

                ;;


            --failure-policy)

                if [[ "$failure_policy_seen" == "true" ]]; then

                    printf '%s\n' \
                        "ERROR: --failure-policy may be supplied only once." \
                        >&2

                    return 2
                fi


                if (( $# < 2 )); then

                    printf '%s\n' \
                        "ERROR: --failure-policy requires a value." >&2

                    return 2
                fi


                policy_value="$2"

                case "$policy_value" in

                    stop|continue)
                        failure_policy="$policy_value"
                        ;;

                    *)

                        printf '%s\n' \
                            "ERROR: Unsupported rollback failure policy: ${policy_value}" \
                            >&2

                        return 2

                        ;;
                esac


                failure_policy_seen="true"

                shift 2

                ;;


            --failure-policy=*)

                if [[ "$failure_policy_seen" == "true" ]]; then

                    printf '%s\n' \
                        "ERROR: --failure-policy may be supplied only once." \
                        >&2

                    return 2
                fi


                policy_value="${argument#--failure-policy=}"

                case "$policy_value" in

                    stop|continue)
                        failure_policy="$policy_value"
                        ;;

                    *)

                        printf '%s\n' \
                            "ERROR: Unsupported rollback failure policy: ${policy_value}" \
                            >&2

                        return 2

                        ;;
                esac


                failure_policy_seen="true"

                shift

                ;;


            *)

                printf '%s\n' \
                    "ERROR: Unsupported rollback execution argument: ${argument}" \
                    >&2

                return 2

                ;;
        esac
    done


    if [[ "${STOLEUS_ROLLBACK_EXECUTOR_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Rollback Executor must be initialized before plan execution." \
            >&2

        return 6
    fi


    if stoleus_rollback_executor_is_running; then

        printf '%s\n' \
            "ERROR: Rollback Executor is already running." >&2

        return 8
    fi


    if stoleus_rollback_executor_is_completed; then

        printf '%s\n' \
            "ERROR: Completed Rollback Executor must be reset before another execution." \
            >&2

        return 8
    fi


    stoleus_rollback_executor_require_plan || return $?


    rollback_step_count="$(
        stoleus_rollback_plan_get_count
    )" || return $?


    if (( rollback_step_count == 0 )); then

        printf '%s\n' \
            "ERROR: Rollback execution requires a non-empty Rollback Plan." \
            >&2

        return 6
    fi


    rollback_session_id="$(
        stoleus_rollback_executor_create_session_id
    )" || return $?


    stoleus_rollback_result_registry_reset || return $?


    stoleus_rollback_executor_begin \
        "$rollback_session_id" \
        "$mode" \
        "$failure_policy" ||
        return $?


    for ((rollback_step = 1; rollback_step <= rollback_step_count; rollback_step++)); do

        if stoleus_rollback_executor_execute_step \
            "$rollback_step" \
            "$mode"; then

            step_exit_code=0

        else
            step_exit_code=$?
        fi


        if (( step_exit_code == 0 )); then
            continue
        fi


        failed_step_count="$((failed_step_count + 1))"

        STOLEUS_ROLLBACK_EXECUTOR_FAILED_STEP_COUNT="$failed_step_count"


        if (( first_failure_exit_code == 0 )); then
            first_failure_exit_code="$step_exit_code"
        fi


        STOLEUS_ROLLBACK_EXECUTOR_EXIT_CODE="$first_failure_exit_code"


        if [[ "$failure_policy" == "continue" ]]; then
            continue
        fi


        stoleus_rollback_executor_finish || return $?


        return "$first_failure_exit_code"
    done


    STOLEUS_ROLLBACK_EXECUTOR_FAILED_STEP_COUNT="$failed_step_count"
    STOLEUS_ROLLBACK_EXECUTOR_EXIT_CODE="$first_failure_exit_code"


    stoleus_rollback_executor_finish || return $?


    if (( first_failure_exit_code != 0 )); then
        return "$first_failure_exit_code"
    fi


    return 0
}


# ==============================================================================
# stoleus_rollback_executor_get_results
# ==============================================================================

stoleus_rollback_executor_get_results() {

    stoleus_rollback_result_registry_list

    return $?
}


# ==============================================================================
# stoleus_rollback_executor_get_detailed_results
# ==============================================================================

stoleus_rollback_executor_get_detailed_results() {

    stoleus_rollback_result_registry_list_detailed

    return $?
}


# ==============================================================================
# stoleus_rollback_executor_initialize
# ==============================================================================

stoleus_rollback_executor_initialize() {

    if [[ "${STOLEUS_ROLLBACK_EXECUTOR_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    STOLEUS_ROLLBACK_EXECUTOR_INITIALIZED="true"
    STOLEUS_ROLLBACK_EXECUTOR_RUNNING="false"
    STOLEUS_ROLLBACK_EXECUTOR_COMPLETED="false"
    STOLEUS_ROLLBACK_EXECUTOR_SESSION_ID=""
    STOLEUS_ROLLBACK_EXECUTOR_MODE="execute"
    STOLEUS_ROLLBACK_EXECUTOR_FAILURE_POLICY="stop"
    STOLEUS_ROLLBACK_EXECUTOR_FAILED_STEP_COUNT=0
    STOLEUS_ROLLBACK_EXECUTOR_EXIT_CODE=0


    return 0
}

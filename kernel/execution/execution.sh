#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Execution Subsystem
# ==============================================================================
#
# Purpose:
#     Execute an immutable ExecutionPlan in its exact planned order.
#
# Processing flow:
#
#     Frozen ExecutionPlan
#         ↓
#     Step iteration
#         ↓
#     Lifecycle Dispatcher
#         ↓
#     Plugin implementation
#         ↓
#     Execution result
#
# The Execution subsystem does not:
#
#     - discover plugins;
#     - parse manifests;
#     - mutate Registry metadata;
#     - resolve dependencies;
#     - detect cycles;
#     - choose lifecycle stages;
#     - reorder plan steps.
#
# Public API:
#
#     stoleus_execution_initialize
#     stoleus_execution_execute_plan
#     stoleus_execution_get_results
#     stoleus_execution_reset
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_EXECUTION_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_EXECUTION_SUBSYSTEM_LOADED="true"


source "${STOLEUS_KERNEL_ROOT}/execution/result_registry.sh"


# ==============================================================================
# Execution Result State
# ==============================================================================
#
# All arrays use the same numeric index.
# ==============================================================================

declare -a STOLEUS_EXECUTION_RESULT_STEP_NUMBERS=()
declare -a STOLEUS_EXECUTION_RESULT_PLUGIN_IDS=()
declare -a STOLEUS_EXECUTION_RESULT_STAGES=()
declare -a STOLEUS_EXECUTION_RESULT_FUNCTIONS=()
declare -a STOLEUS_EXECUTION_RESULT_STATUSES=()
declare -a STOLEUS_EXECUTION_RESULT_EXIT_CODES=()


# ==============================================================================
# Execution Session State
# ==============================================================================
#
# One process owns at most one active or completed execution session. Calling
# stoleus_execution_reset clears the session and permits another plan execution.
# ==============================================================================

STOLEUS_EXECUTION_SESSION_ID=""
STOLEUS_EXECUTION_SESSION_MODE="execute"
STOLEUS_EXECUTION_SESSION_FAILURE_POLICY="stop"
STOLEUS_EXECUTION_SESSION_FAILED_STEP_COUNT=0
STOLEUS_EXECUTION_SESSION_STATUS="not-started"
STOLEUS_EXECUTION_SESSION_TARGET=""
STOLEUS_EXECUTION_SESSION_OPERATION=""
STOLEUS_EXECUTION_SESSION_STARTED_AT=""
STOLEUS_EXECUTION_SESSION_FINISHED_AT=""
STOLEUS_EXECUTION_SESSION_CURRENT_STEP=0
STOLEUS_EXECUTION_SESSION_TOTAL_STEPS=0
STOLEUS_EXECUTION_SESSION_EXIT_CODE=0

STOLEUS_EXECUTION_SESSION_GENERATION=0


# ==============================================================================
# stoleus_execution_reset
# ==============================================================================

stoleus_execution_reset() {

    # Compatibility projection. The Execution Result Registry is authoritative.
    STOLEUS_EXECUTION_RESULT_STEP_NUMBERS=()
    STOLEUS_EXECUTION_RESULT_PLUGIN_IDS=()
    STOLEUS_EXECUTION_RESULT_STAGES=()
    STOLEUS_EXECUTION_RESULT_FUNCTIONS=()
    STOLEUS_EXECUTION_RESULT_STATUSES=()
    STOLEUS_EXECUTION_RESULT_EXIT_CODES=()

    stoleus_execution_result_registry_reset || return $?

    STOLEUS_EXECUTION_STARTED="false"
    STOLEUS_EXECUTION_COMPLETED="false"
    STOLEUS_EXECUTION_SUCCEEDED="false"

    STOLEUS_EXECUTION_SESSION_ID=""
    STOLEUS_EXECUTION_SESSION_MODE="execute"
    STOLEUS_EXECUTION_SESSION_FAILURE_POLICY="stop"
    STOLEUS_EXECUTION_SESSION_STATUS="not-started"
    STOLEUS_EXECUTION_SESSION_TARGET=""
    STOLEUS_EXECUTION_SESSION_OPERATION=""
    STOLEUS_EXECUTION_SESSION_STARTED_AT=""
    STOLEUS_EXECUTION_SESSION_FINISHED_AT=""
    STOLEUS_EXECUTION_SESSION_CURRENT_STEP=0
    STOLEUS_EXECUTION_SESSION_TOTAL_STEPS=0
    STOLEUS_EXECUTION_SESSION_FAILED_STEP_COUNT=0
    STOLEUS_EXECUTION_SESSION_EXIT_CODE=0


    return 0
}


# ==============================================================================
# stoleus_execution_require_plan
# ==============================================================================

stoleus_execution_require_plan() {

    if [[ "${STOLEUS_PLANNING_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Planning must be initialized before execution." >&2

        return 6
    fi


    if ! stoleus_planning_is_plan_frozen; then

        printf '%s\n' \
            "ERROR: Execution requires a frozen ExecutionPlan." >&2

        return 6
    fi


    if (( ${#STOLEUS_PLAN_STEP_PLUGIN_IDS[@]} == 0 )); then

        printf '%s\n' \
            "ERROR: ExecutionPlan contains no steps." >&2

        return 6
    fi


    if [[ "${STOLEUS_LIFECYCLE_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Lifecycle subsystem must be initialized before execution." \
            >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_execution_now
# ==============================================================================
#
# Output:
#
#     UTC timestamp in YYYY-MM-DDTHH:MM:SSZ format
# ==============================================================================

stoleus_execution_now() {

    date -u '+%Y-%m-%dT%H:%M:%SZ'

    return $?
}


# ==============================================================================
# stoleus_execution_now_ms
# ==============================================================================
#
# Output:
#
#     Milliseconds since the Unix epoch.
#
# Git Bash and GNU date support %3N. A one-second precision fallback is used
# when millisecond formatting is unavailable.
# ==============================================================================

stoleus_execution_now_ms() {

    local timestamp=""


    if timestamp="$(date +%s%3N 2>/dev/null)" &&
       [[ "$timestamp" =~ ^[0-9]+$ ]]; then

        printf '%s\n' "$timestamp"

        return 0
    fi


    timestamp="$(date +%s)" || return $?


    printf '%s\n' "$((timestamp * 1000))"

    return 0
}


# ==============================================================================
# stoleus_execution_create_session_id
# ==============================================================================

stoleus_execution_create_session_id() {

    local timestamp=""


    STOLEUS_EXECUTION_SESSION_GENERATION="$((\
STOLEUS_EXECUTION_SESSION_GENERATION + 1\
))"


    timestamp="$(
        date -u '+%Y%m%dT%H%M%SZ'
    )" || return $?


    printf 'execution-%s-%s-%s\n' \
        "$timestamp" \
        "$$" \
        "$STOLEUS_EXECUTION_SESSION_GENERATION"

    return 0
}


# ==============================================================================
# stoleus_execution_start_session
# ==============================================================================

stoleus_execution_start_session() {

    local execution_mode="${1:-execute}"
    local failure_policy="${2:-stop}"


    case "$execution_mode" in

        execute|dry-run)
            ;;

        *)

            printf '%s\n' \
                "ERROR: Unsupported execution mode: ${execution_mode}" >&2

            return 2

            ;;
    esac


    case "$failure_policy" in

        stop|continue)
            ;;

        *)

            printf '%s\n' \
                "ERROR: Unsupported execution failure policy: ${failure_policy}" \
                >&2

            return 2

            ;;
    esac


    if [[ "${STOLEUS_EXECUTION_SESSION_STATUS:-not-started}" != "not-started" ]]; then

        printf '%s\n' \
            "ERROR: Execution session has already been started." >&2

        return 8
    fi


    STOLEUS_EXECUTION_SESSION_ID="$(
        stoleus_execution_create_session_id
    )" || return $?


    STOLEUS_EXECUTION_SESSION_MODE="$execution_mode"
    STOLEUS_EXECUTION_SESSION_FAILURE_POLICY="$failure_policy"
    STOLEUS_EXECUTION_SESSION_STATUS="running"

    STOLEUS_EXECUTION_SESSION_TARGET="${STOLEUS_PLANNING_REQUEST_TARGET:-}"
    STOLEUS_EXECUTION_SESSION_OPERATION="${STOLEUS_PLANNING_REQUEST_OPERATION:-}"

    STOLEUS_EXECUTION_SESSION_STARTED_AT="$(
        stoleus_execution_now
    )" || return $?

    STOLEUS_EXECUTION_SESSION_FINISHED_AT=""
    STOLEUS_EXECUTION_SESSION_CURRENT_STEP=0
    STOLEUS_EXECUTION_SESSION_TOTAL_STEPS="${#STOLEUS_PLAN_STEP_PLUGIN_IDS[@]}"
    STOLEUS_EXECUTION_SESSION_FAILED_STEP_COUNT=0
    STOLEUS_EXECUTION_SESSION_EXIT_CODE=0


    return 0
}


# ==============================================================================
# stoleus_execution_complete_session
# ==============================================================================
#
# Arguments:
#
#     $1 = final status: succeeded or failed
#     $2 = final exit code
# ==============================================================================

stoleus_execution_complete_session() {

    local final_status="${1:-}"
    local exit_code="${2:-}"


    case "$final_status" in

        succeeded|failed)
            ;;

        *)

            printf '%s\n' \
                "ERROR: Unsupported execution-session final status: ${final_status}" \
                >&2

            return 2

            ;;
    esac


    if [[ -z "$exit_code" ||
          ! "$exit_code" =~ ^[0-9]+$ ]]; then

        printf '%s\n' \
            "ERROR: Execution-session completion requires a numeric exit code." \
            >&2

        return 2
    fi


    if [[ "${STOLEUS_EXECUTION_SESSION_STATUS:-not-started}" != "running" ]]; then

        printf '%s\n' \
            "ERROR: Only a running execution session can be completed." >&2

        return 8
    fi


    STOLEUS_EXECUTION_SESSION_STATUS="$final_status"
    STOLEUS_EXECUTION_SESSION_FINISHED_AT="$(
        stoleus_execution_now
    )" || return $?

    STOLEUS_EXECUTION_SESSION_EXIT_CODE="$exit_code"


    return 0
}


# ==============================================================================
# stoleus_execution_get_session
# ==============================================================================
#
# Output fields:
#
#     execution-id
#     status
#     target-plugin
#     operation
#     started-at
#     finished-at
#     current-step
#     total-steps
#     exit-code
# ==============================================================================

stoleus_execution_get_session() {

    if [[ -z "${STOLEUS_EXECUTION_SESSION_ID:-}" ]]; then

        printf '%s\n' \
            "ERROR: No execution session exists." >&2

        return 6
    fi


    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$STOLEUS_EXECUTION_SESSION_ID" \
        "$STOLEUS_EXECUTION_SESSION_MODE" \
        "$STOLEUS_EXECUTION_SESSION_FAILURE_POLICY" \
        "$STOLEUS_EXECUTION_SESSION_STATUS" \
        "$STOLEUS_EXECUTION_SESSION_TARGET" \
        "$STOLEUS_EXECUTION_SESSION_OPERATION" \
        "$STOLEUS_EXECUTION_SESSION_STARTED_AT" \
        "$STOLEUS_EXECUTION_SESSION_FINISHED_AT" \
        "$STOLEUS_EXECUTION_SESSION_CURRENT_STEP" \
        "$STOLEUS_EXECUTION_SESSION_TOTAL_STEPS" \
        "$STOLEUS_EXECUTION_SESSION_FAILED_STEP_COUNT" \
        "$STOLEUS_EXECUTION_SESSION_EXIT_CODE"

    return 0
}


# ==============================================================================
# stoleus_execution_record_result
# ==============================================================================
#
# Arguments:
#
#     $1 = step number
#     $2 = plugin ID
#     $3 = lifecycle stage
#     $4 = lifecycle function
#     $5 = status
#     $6 = exit code
# ==============================================================================

stoleus_execution_record_result() {

    local step_number="${1:-}"
    local plugin_id="${2:-}"
    local lifecycle_stage="${3:-}"
    local lifecycle_function="${4:-}"
    local status="${5:-}"
    local exit_code="${6:-}"
    local started_at="${7:-}"
    local finished_at="${8:-}"
    local duration_ms="${9:-}"


    stoleus_execution_result_registry_append \
        "${STOLEUS_EXECUTION_SESSION_ID:-}" \
        "${STOLEUS_EXECUTION_SESSION_MODE:-execute}" \
        "$step_number" \
        "$plugin_id" \
        "$lifecycle_stage" \
        "$lifecycle_function" \
        "$status" \
        "$exit_code" \
        "$started_at" \
        "$finished_at" \
        "$duration_ms" ||
        return $?


    # --------------------------------------------------------------------------
    # Compatibility projection.
    # --------------------------------------------------------------------------
    STOLEUS_EXECUTION_RESULT_STEP_NUMBERS+=("$step_number")
    STOLEUS_EXECUTION_RESULT_PLUGIN_IDS+=("$plugin_id")
    STOLEUS_EXECUTION_RESULT_STAGES+=("$lifecycle_stage")
    STOLEUS_EXECUTION_RESULT_FUNCTIONS+=("$lifecycle_function")
    STOLEUS_EXECUTION_RESULT_STATUSES+=("$status")
    STOLEUS_EXECUTION_RESULT_EXIT_CODES+=("$exit_code")


    return 0
}


# ==============================================================================
# stoleus_execution_execute_step
# ==============================================================================
#
# Purpose:
#     Execute exactly one frozen plan step.
#
# Arguments:
#
#     $1 = zero-based plan-step index
# ==============================================================================

stoleus_execution_execute_step() {

    local step_index="${1:-}"
    local execution_mode="${2:-execute}"

    local step_number=""
    local plugin_id=""
    local registry_index=""
    local lifecycle_stage=""
    local lifecycle_function=""
    local receives_arguments="false"

    local started_at=""
    local finished_at=""
    local started_ms=0
    local finished_ms=0
    local duration_ms=0

    local exit_code=0


    if [[ -z "$step_index" ||
          ! "$step_index" =~ ^[0-9]+$ ]]; then

        printf '%s\n' \
            "ERROR: Execution step index must be numeric." >&2

        return 2
    fi


    case "$execution_mode" in

        execute|dry-run)
            ;;

        *)

            printf '%s\n' \
                "ERROR: Unsupported execution mode: ${execution_mode}" >&2

            return 2

            ;;
    esac


    step_number="$((step_index + 1))"
    plugin_id="${STOLEUS_PLAN_STEP_PLUGIN_IDS[$step_index]:-}"
    registry_index="${STOLEUS_PLAN_STEP_REGISTRY_INDEXES[$step_index]:-}"
    lifecycle_stage="${STOLEUS_PLAN_STEP_STAGES[$step_index]:-}"
    lifecycle_function="${STOLEUS_PLAN_STEP_FUNCTIONS[$step_index]:-}"
    receives_arguments="${STOLEUS_PLAN_STEP_RECEIVES_ARGUMENTS[$step_index]:-false}"

    started_at="$(stoleus_execution_now)" || return $?
    started_ms="$(stoleus_execution_now_ms)" || return $?


    if [[ -z "$plugin_id" ||
          -z "$registry_index" ||
          -z "$lifecycle_stage" ||
          -z "$lifecycle_function" ]]; then

        finished_at="$(stoleus_execution_now)" || return $?
        finished_ms="$(stoleus_execution_now_ms)" || return $?
        duration_ms="$((finished_ms - started_ms))"

        (( duration_ms < 0 )) && duration_ms=0


        printf '%s\n' \
            "ERROR: ExecutionPlan step ${step_number} contains incomplete metadata." \
            >&2


        stoleus_execution_record_result \
            "$step_number" \
            "$plugin_id" \
            "$lifecycle_stage" \
            "$lifecycle_function" \
            "failed" \
            "6" \
            "$started_at" \
            "$finished_at" \
            "$duration_ms" ||
            return $?


        return 6
    fi


    if [[ "$execution_mode" == "dry-run" ]]; then

        finished_at="$(stoleus_execution_now)" || return $?
        finished_ms="$(stoleus_execution_now_ms)" || return $?
        duration_ms="$((finished_ms - started_ms))"

        (( duration_ms < 0 )) && duration_ms=0


        stoleus_execution_record_result \
            "$step_number" \
            "$plugin_id" \
            "$lifecycle_stage" \
            "$lifecycle_function" \
            "skipped" \
            "0" \
            "$started_at" \
            "$finished_at" \
            "$duration_ms" ||
            return $?


        return 0
    fi


    if [[ "$receives_arguments" == "true" ]]; then

        if stoleus_lifecycle_invoke \
            "$plugin_id" \
            "$registry_index" \
            "$lifecycle_stage" \
            "$lifecycle_function" \
            "${STOLEUS_PLANNING_REQUEST_ARGUMENTS[@]}"; then

            exit_code=0

        else
            exit_code=$?
        fi

    else

        if stoleus_lifecycle_invoke \
            "$plugin_id" \
            "$registry_index" \
            "$lifecycle_stage" \
            "$lifecycle_function"; then

            exit_code=0

        else
            exit_code=$?
        fi
    fi


    finished_at="$(stoleus_execution_now)" || return $?
    finished_ms="$(stoleus_execution_now_ms)" || return $?
    duration_ms="$((finished_ms - started_ms))"

    (( duration_ms < 0 )) && duration_ms=0


    if (( exit_code == 0 )); then

        stoleus_execution_record_result \
            "$step_number" \
            "$plugin_id" \
            "$lifecycle_stage" \
            "$lifecycle_function" \
            "succeeded" \
            "0" \
            "$started_at" \
            "$finished_at" \
            "$duration_ms" ||
            return $?


        return 0
    fi


    stoleus_execution_record_result \
        "$step_number" \
        "$plugin_id" \
        "$lifecycle_stage" \
        "$lifecycle_function" \
        "failed" \
        "$exit_code" \
        "$started_at" \
        "$finished_at" \
        "$duration_ms" ||
        return $?


    return "$exit_code"
}


# ==============================================================================
# stoleus_execution_execute_plan
# ==============================================================================
#
# Purpose:
#     Execute the complete frozen plan in deterministic order.
#
# Behavior:
#
#     - every step runs at most once;
#     - execution stops at the first failed step;
#     - the failing lifecycle exit code is preserved;
#     - repeated execution without reset is rejected.
# ==============================================================================

stoleus_execution_execute_plan() {

    local execution_mode="execute"
    local failure_policy="stop"

    local dry_run_seen="false"
    local failure_policy_seen="false"

    local argument=""
    local policy_value=""

    local step_index=0
    local exit_code=0
    local first_failure_exit_code=0
    local failed_step_count=0


    # --------------------------------------------------------------------------
    # Parse execution options.
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
                execution_mode="dry-run"

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
                            "ERROR: Unsupported execution failure policy: ${policy_value}" \
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
                            "ERROR: Unsupported execution failure policy: ${policy_value}" \
                            >&2

                        return 2

                        ;;
                esac


                failure_policy_seen="true"

                shift

                ;;


            *)

                printf '%s\n' \
                    "ERROR: Unsupported execution argument: ${argument}" >&2

                return 2

                ;;
        esac
    done


    if [[ "${STOLEUS_EXECUTION_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Execution subsystem must be initialized before execution." \
            >&2

        return 6
    fi


    if [[ "${STOLEUS_EXECUTION_STARTED:-false}" == "true" ]]; then

        printf '%s\n' \
            "ERROR: ExecutionPlan has already been executed in this process." \
            >&2

        return 8
    fi


    stoleus_execution_require_plan || return $?


    STOLEUS_EXECUTION_STARTED="true"


    stoleus_execution_start_session \
        "$execution_mode" \
        "$failure_policy" ||
        return $?


    # --------------------------------------------------------------------------
    # Execute every frozen step in plan order.
    # --------------------------------------------------------------------------
    for step_index in "${!STOLEUS_PLAN_STEP_PLUGIN_IDS[@]}"; do

        STOLEUS_EXECUTION_SESSION_CURRENT_STEP="$((step_index + 1))"


        if stoleus_execution_execute_step \
            "$step_index" \
            "$execution_mode"; then

            exit_code=0

        else
            exit_code=$?
        fi


        if (( exit_code == 0 )); then
            continue
        fi


        failed_step_count="$((failed_step_count + 1))"

        STOLEUS_EXECUTION_SESSION_FAILED_STEP_COUNT="$failed_step_count"


        if (( first_failure_exit_code == 0 )); then
            first_failure_exit_code="$exit_code"
        fi


        if [[ "$failure_policy" == "continue" ]]; then
            continue
        fi


        STOLEUS_EXECUTION_COMPLETED="true"
        STOLEUS_EXECUTION_SUCCEEDED="false"


        stoleus_execution_complete_session \
            "failed" \
            "$first_failure_exit_code" ||
            return $?


        return "$first_failure_exit_code"
    done


    STOLEUS_EXECUTION_COMPLETED="true"


    if (( failed_step_count > 0 )); then

        STOLEUS_EXECUTION_SUCCEEDED="false"


        stoleus_execution_complete_session \
            "failed" \
            "$first_failure_exit_code" ||
            return $?


        return "$first_failure_exit_code"
    fi


    STOLEUS_EXECUTION_SUCCEEDED="true"


    stoleus_execution_complete_session \
        "succeeded" \
        "0" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_execution_get_results
# ==============================================================================
#
# Output format:
#
#     step-number
#     plugin-id
#     lifecycle-stage
#     lifecycle-function
#     status
#     exit-code
#
# Fields are separated by tabs.
# ==============================================================================

stoleus_execution_get_results() {

    stoleus_execution_result_registry_list

    return $?
}


# ==============================================================================
# stoleus_execution_get_detailed_results
# ==============================================================================

stoleus_execution_get_detailed_results() {

    stoleus_execution_result_registry_list_detailed

    return $?
}


# ==============================================================================
# stoleus_execution_initialize
# ==============================================================================

stoleus_execution_initialize() {

    if [[ "${STOLEUS_EXECUTION_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_execution_result_registry_initialize || return $?
    stoleus_execution_reset || return $?


    STOLEUS_EXECUTION_INITIALIZED="true"


    return 0
}

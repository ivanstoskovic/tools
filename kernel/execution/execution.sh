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
# stoleus_execution_reset
# ==============================================================================

stoleus_execution_reset() {

    STOLEUS_EXECUTION_RESULT_STEP_NUMBERS=()
    STOLEUS_EXECUTION_RESULT_PLUGIN_IDS=()
    STOLEUS_EXECUTION_RESULT_STAGES=()
    STOLEUS_EXECUTION_RESULT_FUNCTIONS=()
    STOLEUS_EXECUTION_RESULT_STATUSES=()
    STOLEUS_EXECUTION_RESULT_EXIT_CODES=()

    STOLEUS_EXECUTION_STARTED="false"
    STOLEUS_EXECUTION_COMPLETED="false"
    STOLEUS_EXECUTION_SUCCEEDED="false"


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

    local step_number=""
    local plugin_id=""
    local registry_index=""
    local lifecycle_stage=""
    local lifecycle_function=""
    local receives_arguments="false"

    local exit_code=0


    if [[ -z "$step_index" || ! "$step_index" =~ ^[0-9]+$ ]]; then

        printf '%s\n' \
            "ERROR: Execution step index must be numeric." >&2

        return 2
    fi


    step_number="$((step_index + 1))"
    plugin_id="${STOLEUS_PLAN_STEP_PLUGIN_IDS[$step_index]:-}"
    registry_index="${STOLEUS_PLAN_STEP_REGISTRY_INDEXES[$step_index]:-}"
    lifecycle_stage="${STOLEUS_PLAN_STEP_STAGES[$step_index]:-}"
    lifecycle_function="${STOLEUS_PLAN_STEP_FUNCTIONS[$step_index]:-}"
    receives_arguments="${STOLEUS_PLAN_STEP_RECEIVES_ARGUMENTS[$step_index]:-false}"


    if [[ -z "$plugin_id" ||
          -z "$registry_index" ||
          -z "$lifecycle_stage" ||
          -z "$lifecycle_function" ]]; then

        printf '%s\n' \
            "ERROR: ExecutionPlan step ${step_number} contains incomplete metadata." \
            >&2

        stoleus_execution_record_result \
            "$step_number" \
            "$plugin_id" \
            "$lifecycle_stage" \
            "$lifecycle_function" \
            "failed" \
            "6"

        return 6
    fi


    # --------------------------------------------------------------------------
    # Invoke the lifecycle function inside an `if` condition.
    #
    # Bash suppresses automatic `set -e` termination for commands evaluated as
    # an if-condition. This lets us capture and preserve the lifecycle return
    # code without modifying the caller's shell options.
    #
    # Target-plugin steps receive the original ExecutionRequest arguments.
    # Dependency-plugin steps receive no target-specific arguments.
    # --------------------------------------------------------------------------
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


    if (( exit_code == 0 )); then

        stoleus_execution_record_result \
            "$step_number" \
            "$plugin_id" \
            "$lifecycle_stage" \
            "$lifecycle_function" \
            "succeeded" \
            "0"

        return 0
    fi


    stoleus_execution_record_result \
        "$step_number" \
        "$plugin_id" \
        "$lifecycle_stage" \
        "$lifecycle_function" \
        "failed" \
        "$exit_code"


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

    local step_index=0
    local exit_code=0


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


    # --------------------------------------------------------------------------
    # Execute every frozen plan step in exact plan order.
    #
    # Using an `if` condition allows a nonzero lifecycle result to be captured
    # safely without changing the shell's global errexit setting.
    # --------------------------------------------------------------------------
    for step_index in "${!STOLEUS_PLAN_STEP_PLUGIN_IDS[@]}"; do

        if stoleus_execution_execute_step "$step_index"; then

            exit_code=0

        else

            exit_code=$?
        fi


        if (( exit_code != 0 )); then

            STOLEUS_EXECUTION_COMPLETED="true"
            STOLEUS_EXECUTION_SUCCEEDED="false"

            return "$exit_code"
        fi
    done


    STOLEUS_EXECUTION_COMPLETED="true"
    STOLEUS_EXECUTION_SUCCEEDED="true"


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

    local result_index=0


    for result_index in "${!STOLEUS_EXECUTION_RESULT_STEP_NUMBERS[@]}"; do

        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "${STOLEUS_EXECUTION_RESULT_STEP_NUMBERS[$result_index]}" \
            "${STOLEUS_EXECUTION_RESULT_PLUGIN_IDS[$result_index]}" \
            "${STOLEUS_EXECUTION_RESULT_STAGES[$result_index]}" \
            "${STOLEUS_EXECUTION_RESULT_FUNCTIONS[$result_index]}" \
            "${STOLEUS_EXECUTION_RESULT_STATUSES[$result_index]}" \
            "${STOLEUS_EXECUTION_RESULT_EXIT_CODES[$result_index]}"
    done


    return 0
}


# ==============================================================================
# stoleus_execution_initialize
# ==============================================================================

stoleus_execution_initialize() {

    if [[ "${STOLEUS_EXECUTION_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_execution_reset || return $?


    STOLEUS_EXECUTION_INITIALIZED="true"

    return 0
}

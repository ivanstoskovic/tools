#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Rollback Planner
# ==============================================================================
#
# Purpose:
#     Transform successful execution results and registered compensating actions
#     into an immutable rollback plan.
#
# Processing:
#
#     Execution Result Registry
#              +
#     Rollback Registry
#              ↓
#     Reverse result traversal
#              ↓
#     Successful and reversible steps
#              ↓
#     Frozen Rollback Plan
#
# Internal API:
#
#     stoleus_rollback_planner_initialize
#     stoleus_rollback_planner_reset
#     stoleus_rollback_planner_build
#     stoleus_rollback_planner_is_built
#     stoleus_rollback_planner_get_execution_id
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_ROLLBACK_PLANNER_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_ROLLBACK_PLANNER_SUBSYSTEM_LOADED="true"


# ==============================================================================
# State
# ==============================================================================

STOLEUS_ROLLBACK_PLANNER_EXECUTION_ID=""
STOLEUS_ROLLBACK_PLANNER_BUILT="false"


# ==============================================================================
# stoleus_rollback_planner_reset
# ==============================================================================

stoleus_rollback_planner_reset() {

    stoleus_rollback_plan_reset || return $?


    STOLEUS_ROLLBACK_PLANNER_EXECUTION_ID=""
    STOLEUS_ROLLBACK_PLANNER_BUILT="false"


    return 0
}


# ==============================================================================
# stoleus_rollback_planner_is_built
# ==============================================================================

stoleus_rollback_planner_is_built() {

    [[ "${STOLEUS_ROLLBACK_PLANNER_BUILT:-false}" == "true" ]]
}


# ==============================================================================
# stoleus_rollback_planner_get_execution_id
# ==============================================================================

stoleus_rollback_planner_get_execution_id() {

    if ! stoleus_rollback_planner_is_built; then

        printf '%s\n' \
            "ERROR: No rollback plan has been built." >&2

        return 6
    fi


    printf '%s\n' \
        "$STOLEUS_ROLLBACK_PLANNER_EXECUTION_ID"

    return 0
}


# ==============================================================================
# stoleus_rollback_planner_require_dependencies
# ==============================================================================

stoleus_rollback_planner_require_dependencies() {

    if [[ "${STOLEUS_EXECUTION_RESULT_REGISTRY_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Execution Result Registry must be initialized before rollback planning." \
            >&2

        return 6
    fi


    if [[ "${STOLEUS_ROLLBACK_REGISTRY_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Rollback Registry must be initialized before rollback planning." \
            >&2

        return 6
    fi


    if [[ "${STOLEUS_ROLLBACK_PLAN_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Rollback Plan must be initialized before rollback planning." \
            >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_rollback_planner_build
# ==============================================================================

stoleus_rollback_planner_build() {

    local execution_id="${1:-}"

    local result_count=0
    local result_index=0
    local result_key=""

    local result_execution_id=""
    local execution_step=""
    local plugin_id=""
    local forward_stage=""
    local rollback_function=""

    local success_exit_code=0
    local contains_exit_code=0

    local rollback_step=0


    if [[ -z "$execution_id" ]]; then

        printf '%s\n' \
            "ERROR: Rollback planning requires an execution ID." >&2

        return 2
    fi


    if stoleus_rollback_planner_is_built ||
       stoleus_rollback_plan_is_frozen; then

        printf '%s\n' \
            "ERROR: A rollback plan has already been built. Reset the Rollback Planner before rebuilding." \
            >&2

        return 8
    fi


    stoleus_rollback_planner_require_dependencies || return $?


    stoleus_rollback_plan_reset || return $?


    result_count="$(
        stoleus_execution_result_registry_get_count
    )" || return $?


    # --------------------------------------------------------------------------
    # Reverse traversal preserves rollback ordering:
    #
    #     last successful forward step
    #                 ↓
    #     first rollback step
    # --------------------------------------------------------------------------
    for ((result_index = result_count - 1; result_index >= 0; result_index--)); do

        result_key="$(
            stoleus_metadata_collection_get_key_by_index \
                "$STOLEUS_EXECUTION_RESULT_COLLECTION_ID" \
                "$result_index"
        )" || return $?


        result_execution_id="$(
            stoleus_metadata_collection_get_field \
                "$STOLEUS_EXECUTION_RESULT_COLLECTION_ID" \
                "$result_key" \
                "execution-id"
        )" || return $?


        if [[ "$result_execution_id" != "$execution_id" ]]; then
            continue
        fi


        execution_step="$(
            stoleus_metadata_collection_get_field \
                "$STOLEUS_EXECUTION_RESULT_COLLECTION_ID" \
                "$result_key" \
                "step-number"
        )" || return $?


        if stoleus_execution_result_registry_is_successful \
            "$execution_id" \
            "$execution_step"; then

            success_exit_code=0

        else
            success_exit_code=$?
        fi


        if (( success_exit_code == 1 )); then
            continue
        fi


        if (( success_exit_code != 0 )); then
            return "$success_exit_code"
        fi


        plugin_id="$(
            stoleus_metadata_collection_get_field \
                "$STOLEUS_EXECUTION_RESULT_COLLECTION_ID" \
                "$result_key" \
                "plugin-id"
        )" || return $?


        forward_stage="$(
            stoleus_metadata_collection_get_field \
                "$STOLEUS_EXECUTION_RESULT_COLLECTION_ID" \
                "$result_key" \
                "stage"
        )" || return $?


        if stoleus_rollback_registry_contains \
            "$plugin_id" \
            "$forward_stage"; then

            contains_exit_code=0

        else
            contains_exit_code=$?
        fi


        if (( contains_exit_code == 1 )); then
            continue
        fi


        if (( contains_exit_code != 0 )); then
            return "$contains_exit_code"
        fi


        rollback_function="$(
            stoleus_rollback_registry_get_function \
                "$plugin_id" \
                "$forward_stage"
        )" || return $?


        rollback_step="$((rollback_step + 1))"


        stoleus_rollback_plan_append \
            "$rollback_step" \
            "$execution_step" \
            "$plugin_id" \
            "$rollback_function" ||
            return $?
    done


    stoleus_rollback_plan_freeze || return $?


    STOLEUS_ROLLBACK_PLANNER_EXECUTION_ID="$execution_id"
    STOLEUS_ROLLBACK_PLANNER_BUILT="true"


    return 0
}


# ==============================================================================
# stoleus_rollback_planner_initialize
# ==============================================================================

stoleus_rollback_planner_initialize() {

    if [[ "${STOLEUS_ROLLBACK_PLANNER_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_rollback_planner_reset || return $?


    STOLEUS_ROLLBACK_PLANNER_INITIALIZED="true"


    return 0
}

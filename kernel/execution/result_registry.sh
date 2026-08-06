#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Execution Result Registry
# ==============================================================================
#
# Purpose:
#     Store immutable-in-session execution step results in the generic Metadata
#     Collection engine.
#
# One record contains:
#
#     result-id
#     execution-id
#     mode
#     step-number
#     plugin-id
#     stage
#     function
#     status
#     exit-code
#     started-at
#     finished-at
#     duration-ms
#
# This module is internal to the Execution subsystem.
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_EXECUTION_RESULT_REGISTRY_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_EXECUTION_RESULT_REGISTRY_LOADED="true"


# ==============================================================================
# Constants
# ==============================================================================

readonly STOLEUS_EXECUTION_RESULT_COLLECTION_ID="execution-results"


# ==============================================================================
# stoleus_execution_result_registry_create
# ==============================================================================

stoleus_execution_result_registry_create() {

    if stoleus_metadata_collection_exists \
        "$STOLEUS_EXECUTION_RESULT_COLLECTION_ID"; then

        return 0
    fi


    stoleus_metadata_collection_create \
        "$STOLEUS_EXECUTION_RESULT_COLLECTION_ID" \
        "result-id" \
        "result-id" \
        "execution-id" \
        "mode" \
        "step-number" \
        "plugin-id" \
        "stage" \
        "function" \
        "status" \
        "exit-code" \
        "started-at" \
        "finished-at" \
        "duration-ms" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_execution_result_registry_reset
# ==============================================================================

stoleus_execution_result_registry_reset() {

    stoleus_metadata_collection_reset \
        "$STOLEUS_EXECUTION_RESULT_COLLECTION_ID" ||
        return $?


    stoleus_execution_result_registry_create || return $?


    return 0
}


# ==============================================================================
# stoleus_execution_result_registry_append
# ==============================================================================

stoleus_execution_result_registry_append() {

    local execution_id="${1:-}"
    local execution_mode="${2:-}"
    local step_number="${3:-}"
    local plugin_id="${4:-}"
    local lifecycle_stage="${5:-}"
    local lifecycle_function="${6:-}"
    local status="${7:-}"
    local exit_code="${8:-}"
    local started_at="${9:-}"
    local finished_at="${10:-}"
    local duration_ms="${11:-}"

    local result_id=""


    if [[ -z "$execution_id" ||
          -z "$execution_mode" ||
          -z "$step_number" ||
          ! "$step_number" =~ ^[0-9]+$ ||
          -z "$status" ||
          -z "$exit_code" ||
          ! "$exit_code" =~ ^[0-9]+$ ||
          -z "$started_at" ||
          -z "$finished_at" ||
          -z "$duration_ms" ||
          ! "$duration_ms" =~ ^[0-9]+$ ]]; then

        printf '%s\n' \
            "ERROR: Execution Result Registry received incomplete result metadata." \
            >&2

        return 2
    fi


    case "$execution_mode" in

        execute|dry-run)
            ;;

        *)

            printf '%s\n' \
                "ERROR: Invalid execution-result mode: ${execution_mode}" >&2

            return 6

            ;;
    esac


    case "$status" in

        succeeded|failed|skipped)
            ;;

        *)

            printf '%s\n' \
                "ERROR: Invalid execution-result status: ${status}" >&2

            return 6

            ;;
    esac


    result_id="${execution_id}@${step_number}"


    if stoleus_metadata_collection_contains \
        "$STOLEUS_EXECUTION_RESULT_COLLECTION_ID" \
        "$result_id"; then

        printf '%s\n' \
            "ERROR: Duplicate execution result: ${result_id}" >&2

        return 8
    fi


    stoleus_metadata_collection_append \
        "$STOLEUS_EXECUTION_RESULT_COLLECTION_ID" \
        "$result_id" \
        "$execution_id" \
        "$execution_mode" \
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


    return 0
}


# ==============================================================================
# stoleus_execution_result_registry_get_count
# ==============================================================================

stoleus_execution_result_registry_get_count() {

    stoleus_metadata_collection_get_count \
        "$STOLEUS_EXECUTION_RESULT_COLLECTION_ID"

    return $?
}


# ==============================================================================
# stoleus_execution_result_registry_list
# ==============================================================================

stoleus_execution_result_registry_list() {

    stoleus_metadata_collection_list \
        "$STOLEUS_EXECUTION_RESULT_COLLECTION_ID" \
        "step-number" \
        "plugin-id" \
        "stage" \
        "function" \
        "status" \
        "exit-code"

    return $?
}


# ==============================================================================
# stoleus_execution_result_registry_list_detailed
# ==============================================================================

stoleus_execution_result_registry_list_detailed() {

    stoleus_metadata_collection_list \
        "$STOLEUS_EXECUTION_RESULT_COLLECTION_ID" \
        "result-id" \
        "execution-id" \
        "mode" \
        "step-number" \
        "plugin-id" \
        "stage" \
        "function" \
        "status" \
        "exit-code" \
        "started-at" \
        "finished-at" \
        "duration-ms"

    return $?
}


# ==============================================================================
# stoleus_execution_result_registry_initialize
# ==============================================================================

stoleus_execution_result_registry_initialize() {

    if [[ "${STOLEUS_EXECUTION_RESULT_REGISTRY_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_execution_result_registry_reset || return $?


    STOLEUS_EXECUTION_RESULT_REGISTRY_INITIALIZED="true"


    return 0
}

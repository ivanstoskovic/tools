#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Rollback Result Registry
# ==============================================================================
#
# Purpose:
#     Store structured results produced while executing a frozen Rollback Plan.
#
# Record model:
#
#     rollback-result-id
#     rollback-session-id
#     mode
#     rollback-step
#     execution-step
#     plugin-id
#     rollback-function
#     status
#     exit-code
#     started-at
#     finished-at
#     duration-ms
#
# Internal API:
#
#     stoleus_rollback_result_registry_initialize
#     stoleus_rollback_result_registry_reset
#     stoleus_rollback_result_registry_append
#     stoleus_rollback_result_registry_get_field
#     stoleus_rollback_result_registry_get_count
#     stoleus_rollback_result_registry_list
#     stoleus_rollback_result_registry_list_detailed
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_ROLLBACK_RESULT_REGISTRY_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_ROLLBACK_RESULT_REGISTRY_LOADED="true"


# ==============================================================================
# Constants
# ==============================================================================

readonly STOLEUS_ROLLBACK_RESULT_COLLECTION_ID="rollback-results"


# ==============================================================================
# stoleus_rollback_result_registry_create
# ==============================================================================

stoleus_rollback_result_registry_create() {

    if stoleus_metadata_collection_exists \
        "$STOLEUS_ROLLBACK_RESULT_COLLECTION_ID"; then

        return 0
    fi


    stoleus_metadata_collection_create \
        "$STOLEUS_ROLLBACK_RESULT_COLLECTION_ID" \
        "rollback-result-id" \
        "rollback-result-id" \
        "rollback-session-id" \
        "mode" \
        "rollback-step" \
        "execution-step" \
        "plugin-id" \
        "rollback-function" \
        "status" \
        "exit-code" \
        "started-at" \
        "finished-at" \
        "duration-ms" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_rollback_result_registry_reset
# ==============================================================================

stoleus_rollback_result_registry_reset() {

    stoleus_metadata_collection_reset \
        "$STOLEUS_ROLLBACK_RESULT_COLLECTION_ID" ||
        return $?


    stoleus_rollback_result_registry_create || return $?


    return 0
}


# ==============================================================================
# stoleus_rollback_result_registry_append
# ==============================================================================

stoleus_rollback_result_registry_append() {

    local rollback_session_id="${1:-}"
    local mode="${2:-}"
    local rollback_step="${3:-}"
    local execution_step="${4:-}"
    local plugin_id="${5:-}"
    local rollback_function="${6:-}"
    local status="${7:-}"
    local exit_code="${8:-}"
    local started_at="${9:-}"
    local finished_at="${10:-}"
    local duration_ms="${11:-}"

    local rollback_result_id=""


    if [[ -z "$rollback_session_id" ||
          -z "$rollback_step" ||
          ! "$rollback_step" =~ ^[1-9][0-9]*$ ||
          -z "$execution_step" ||
          ! "$execution_step" =~ ^[1-9][0-9]*$ ||
          -z "$plugin_id" ||
          -z "$rollback_function" ||
          -z "$exit_code" ||
          ! "$exit_code" =~ ^[0-9]+$ ||
          -z "$started_at" ||
          -z "$finished_at" ||
          -z "$duration_ms" ||
          ! "$duration_ms" =~ ^[0-9]+$ ]]; then

        printf '%s\n' \
            "ERROR: Rollback Result Registry received incomplete result metadata." \
            >&2

        return 2
    fi


    case "$mode" in

        execute|dry-run)
            ;;

        *)

            printf '%s\n' \
                "ERROR: Invalid rollback-result mode: ${mode}" >&2

            return 6

            ;;
    esac


    case "$status" in

        succeeded|failed|skipped)
            ;;

        *)

            printf '%s\n' \
                "ERROR: Invalid rollback-result status: ${status}" >&2

            return 6

            ;;
    esac


    stoleus_rollback_registry_validate_plugin_id \
        "$plugin_id" ||
        return $?


    stoleus_rollback_registry_validate_function \
        "$rollback_function" ||
        return $?


    rollback_result_id="${rollback_session_id}@${rollback_step}"


    if stoleus_metadata_collection_contains \
        "$STOLEUS_ROLLBACK_RESULT_COLLECTION_ID" \
        "$rollback_result_id"; then

        printf '%s\n' \
            "ERROR: Duplicate rollback result: ${rollback_result_id}" >&2

        return 8
    fi


    stoleus_metadata_collection_append \
        "$STOLEUS_ROLLBACK_RESULT_COLLECTION_ID" \
        "$rollback_result_id" \
        "$rollback_session_id" \
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


    return 0
}


# ==============================================================================
# stoleus_rollback_result_registry_get_field
# ==============================================================================

stoleus_rollback_result_registry_get_field() {

    local rollback_session_id="${1:-}"
    local rollback_step="${2:-}"
    local field_name="${3:-}"

    local rollback_result_id=""


    if [[ -z "$rollback_session_id" ||
          -z "$rollback_step" ||
          -z "$field_name" ]]; then

        printf '%s\n' \
            "ERROR: Rollback result lookup requires session ID, step, and field name." \
            >&2

        return 2
    fi


    if [[ ! "$rollback_step" =~ ^[1-9][0-9]*$ ]]; then

        printf '%s\n' \
            "ERROR: Rollback result step must be a positive integer: ${rollback_step}" \
            >&2

        return 6
    fi


    rollback_result_id="${rollback_session_id}@${rollback_step}"


    if ! stoleus_metadata_collection_contains \
        "$STOLEUS_ROLLBACK_RESULT_COLLECTION_ID" \
        "$rollback_result_id"; then

        printf '%s\n' \
            "ERROR: Unknown rollback result: ${rollback_result_id}" >&2

        return 6
    fi


    stoleus_metadata_collection_get_field \
        "$STOLEUS_ROLLBACK_RESULT_COLLECTION_ID" \
        "$rollback_result_id" \
        "$field_name"

    return $?
}


# ==============================================================================
# stoleus_rollback_result_registry_get_count
# ==============================================================================

stoleus_rollback_result_registry_get_count() {

    stoleus_metadata_collection_get_count \
        "$STOLEUS_ROLLBACK_RESULT_COLLECTION_ID"

    return $?
}


# ==============================================================================
# stoleus_rollback_result_registry_list
# ==============================================================================

stoleus_rollback_result_registry_list() {

    stoleus_metadata_collection_list \
        "$STOLEUS_ROLLBACK_RESULT_COLLECTION_ID" \
        "rollback-step" \
        "execution-step" \
        "plugin-id" \
        "rollback-function" \
        "status" \
        "exit-code"

    return $?
}


# ==============================================================================
# stoleus_rollback_result_registry_list_detailed
# ==============================================================================

stoleus_rollback_result_registry_list_detailed() {

    stoleus_metadata_collection_list \
        "$STOLEUS_ROLLBACK_RESULT_COLLECTION_ID" \
        "rollback-result-id" \
        "rollback-session-id" \
        "mode" \
        "rollback-step" \
        "execution-step" \
        "plugin-id" \
        "rollback-function" \
        "status" \
        "exit-code" \
        "started-at" \
        "finished-at" \
        "duration-ms"

    return $?
}


# ==============================================================================
# stoleus_rollback_result_registry_initialize
# ==============================================================================

stoleus_rollback_result_registry_initialize() {

    if [[ "${STOLEUS_ROLLBACK_RESULT_REGISTRY_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_rollback_result_registry_reset || return $?


    STOLEUS_ROLLBACK_RESULT_REGISTRY_INITIALIZED="true"


    return 0
}

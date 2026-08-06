#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Rollback Plan Registry
# ==============================================================================
#
# Purpose:
#     Store an immutable rollback plan produced from successful execution
#     results and rollback-action mappings.
#
# Record model:
#
#     rollback-step
#     execution-step
#     plugin-id
#     rollback-function
#
# This subsystem stores rollback-plan records only. It does not:
#
#     - inspect execution results;
#     - resolve rollback actions;
#     - build rollback plans;
#     - invoke rollback functions.
#
# Internal API:
#
#     stoleus_rollback_plan_initialize
#     stoleus_rollback_plan_reset
#     stoleus_rollback_plan_append
#     stoleus_rollback_plan_contains
#     stoleus_rollback_plan_get_field
#     stoleus_rollback_plan_get_count
#     stoleus_rollback_plan_list
#     stoleus_rollback_plan_freeze
#     stoleus_rollback_plan_is_frozen
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_ROLLBACK_PLAN_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_ROLLBACK_PLAN_SUBSYSTEM_LOADED="true"


# ==============================================================================
# Constants
# ==============================================================================

readonly STOLEUS_ROLLBACK_PLAN_COLLECTION_ID="rollback-plan"


# ==============================================================================
# stoleus_rollback_plan_validate_positive_integer
# ==============================================================================

stoleus_rollback_plan_validate_positive_integer() {

    local field_name="${1:-}"
    local value="${2:-}"


    if [[ -z "$field_name" || -z "$value" ]]; then

        printf '%s\n' \
            "ERROR: Rollback Plan integer validation requires field name and value." \
            >&2

        return 2
    fi


    if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then

        printf '%s\n' \
            "ERROR: Rollback Plan field '${field_name}' must be a positive integer: ${value}" \
            >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_rollback_plan_create_collection
# ==============================================================================

stoleus_rollback_plan_create_collection() {

    if stoleus_metadata_collection_exists \
        "$STOLEUS_ROLLBACK_PLAN_COLLECTION_ID"; then

        return 0
    fi


    stoleus_metadata_collection_create \
        "$STOLEUS_ROLLBACK_PLAN_COLLECTION_ID" \
        "rollback-step" \
        "rollback-step" \
        "execution-step" \
        "plugin-id" \
        "rollback-function" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_rollback_plan_reset
# ==============================================================================

stoleus_rollback_plan_reset() {

    stoleus_metadata_collection_reset \
        "$STOLEUS_ROLLBACK_PLAN_COLLECTION_ID" ||
        return $?


    stoleus_rollback_plan_create_collection || return $?


    STOLEUS_ROLLBACK_PLAN_READY="false"


    return 0
}


# ==============================================================================
# stoleus_rollback_plan_is_frozen
# ==============================================================================

stoleus_rollback_plan_is_frozen() {

    if ! stoleus_metadata_collection_exists \
        "$STOLEUS_ROLLBACK_PLAN_COLLECTION_ID"; then

        return 1
    fi


    stoleus_metadata_collection_is_frozen \
        "$STOLEUS_ROLLBACK_PLAN_COLLECTION_ID"
}


# ==============================================================================
# stoleus_rollback_plan_freeze
# ==============================================================================

stoleus_rollback_plan_freeze() {

    if stoleus_rollback_plan_is_frozen; then
        return 0
    fi


    stoleus_metadata_collection_freeze \
        "$STOLEUS_ROLLBACK_PLAN_COLLECTION_ID" ||
        return $?


    STOLEUS_ROLLBACK_PLAN_READY="true"


    return 0
}


# ==============================================================================
# stoleus_rollback_plan_contains
# ==============================================================================

stoleus_rollback_plan_contains() {

    local rollback_step="${1:-}"


    if [[ -z "$rollback_step" ]]; then
        return 2
    fi


    stoleus_metadata_collection_contains \
        "$STOLEUS_ROLLBACK_PLAN_COLLECTION_ID" \
        "$rollback_step"
}


# ==============================================================================
# stoleus_rollback_plan_append
# ==============================================================================

stoleus_rollback_plan_append() {

    local rollback_step="${1:-}"
    local execution_step="${2:-}"
    local plugin_id="${3:-}"
    local rollback_function="${4:-}"


    if stoleus_rollback_plan_is_frozen; then

        printf '%s\n' \
            "ERROR: Rollback Plan is immutable after it is frozen." >&2

        return 8
    fi


    stoleus_rollback_plan_validate_positive_integer \
        "rollback-step" \
        "$rollback_step" ||
        return $?


    stoleus_rollback_plan_validate_positive_integer \
        "execution-step" \
        "$execution_step" ||
        return $?


    stoleus_rollback_registry_validate_plugin_id \
        "$plugin_id" ||
        return $?


    stoleus_rollback_registry_validate_function \
        "$rollback_function" ||
        return $?


    if stoleus_rollback_plan_contains "$rollback_step"; then

        printf '%s\n' \
            "ERROR: Duplicate rollback plan step: ${rollback_step}" >&2

        return 8
    fi


    stoleus_metadata_collection_append \
        "$STOLEUS_ROLLBACK_PLAN_COLLECTION_ID" \
        "$rollback_step" \
        "$execution_step" \
        "$plugin_id" \
        "$rollback_function" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_rollback_plan_get_field
# ==============================================================================

stoleus_rollback_plan_get_field() {

    local rollback_step="${1:-}"
    local field_name="${2:-}"


    if [[ -z "$rollback_step" || -z "$field_name" ]]; then

        printf '%s\n' \
            "ERROR: Rollback Plan lookup requires rollback step and field name." \
            >&2

        return 2
    fi


    stoleus_metadata_collection_get_field \
        "$STOLEUS_ROLLBACK_PLAN_COLLECTION_ID" \
        "$rollback_step" \
        "$field_name"

    return $?
}


# ==============================================================================
# stoleus_rollback_plan_get_count
# ==============================================================================

stoleus_rollback_plan_get_count() {

    stoleus_metadata_collection_get_count \
        "$STOLEUS_ROLLBACK_PLAN_COLLECTION_ID"

    return $?
}


# ==============================================================================
# stoleus_rollback_plan_list
# ==============================================================================

stoleus_rollback_plan_list() {

    stoleus_metadata_collection_list \
        "$STOLEUS_ROLLBACK_PLAN_COLLECTION_ID" \
        "rollback-step" \
        "execution-step" \
        "plugin-id" \
        "rollback-function"

    return $?
}


# ==============================================================================
# stoleus_rollback_plan_initialize
# ==============================================================================

stoleus_rollback_plan_initialize() {

    if [[ "${STOLEUS_ROLLBACK_PLAN_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_rollback_plan_reset || return $?


    STOLEUS_ROLLBACK_PLAN_INITIALIZED="true"


    return 0
}

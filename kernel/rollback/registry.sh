#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Rollback Registry
# ==============================================================================
#
# Purpose:
#     Store validated mappings from a plugin lifecycle stage to a compensating
#     rollback function.
#
# Record model:
#
#     rollback-key
#     plugin-id
#     forward-stage
#     rollback-function
#
# Example:
#
#     chrony@install
#     chrony
#     install
#     chrony_remove
#
# This subsystem does not:
#
#     - discover rollback declarations;
#     - import plugin manifests;
#     - build rollback plans;
#     - execute rollback functions;
#     - infer compensating behavior automatically.
#
# Internal API:
#
#     stoleus_rollback_registry_initialize
#     stoleus_rollback_registry_reset
#     stoleus_rollback_registry_register
#     stoleus_rollback_registry_contains
#     stoleus_rollback_registry_get_function
#     stoleus_rollback_registry_get_field
#     stoleus_rollback_registry_get_count
#     stoleus_rollback_registry_list
#     stoleus_rollback_registry_freeze
#     stoleus_rollback_registry_is_frozen
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_ROLLBACK_REGISTRY_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_ROLLBACK_REGISTRY_SUBSYSTEM_LOADED="true"


# ==============================================================================
# Constants
# ==============================================================================

readonly STOLEUS_ROLLBACK_REGISTRY_COLLECTION_ID="rollback-actions"


# ==============================================================================
# stoleus_rollback_registry_validate_plugin_id
# ==============================================================================

stoleus_rollback_registry_validate_plugin_id() {

    local plugin_id="${1:-}"


    if [[ -z "$plugin_id" ]]; then

        printf '%s\n' \
            "ERROR: Rollback registration requires a plugin ID." >&2

        return 2
    fi


    if [[ ! "$plugin_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid rollback plugin ID: ${plugin_id}" >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_rollback_registry_validate_stage
# ==============================================================================

stoleus_rollback_registry_validate_stage() {

    local forward_stage="${1:-}"


    if [[ -z "$forward_stage" ]]; then

        printf '%s\n' \
            "ERROR: Rollback registration requires a forward lifecycle stage." \
            >&2

        return 2
    fi


    case "$forward_stage" in

        install|configure|verify|upgrade|remove)
            return 0
            ;;

        *)

            printf '%s\n' \
                "ERROR: Unsupported rollback forward stage: ${forward_stage}" \
                >&2

            return 6

            ;;
    esac
}


# ==============================================================================
# stoleus_rollback_registry_validate_function
# ==============================================================================

stoleus_rollback_registry_validate_function() {

    local rollback_function="${1:-}"


    if [[ -z "$rollback_function" ]]; then

        printf '%s\n' \
            "ERROR: Rollback registration requires a function reference." \
            >&2

        return 2
    fi


    if [[ ! "$rollback_function" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid rollback function reference: ${rollback_function}" \
            >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_rollback_registry_create_collection
# ==============================================================================

stoleus_rollback_registry_create_collection() {

    if stoleus_metadata_collection_exists \
        "$STOLEUS_ROLLBACK_REGISTRY_COLLECTION_ID"; then

        return 0
    fi


    stoleus_metadata_collection_create \
        "$STOLEUS_ROLLBACK_REGISTRY_COLLECTION_ID" \
        "rollback-key" \
        "rollback-key" \
        "plugin-id" \
        "forward-stage" \
        "rollback-function" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_rollback_registry_reset
# ==============================================================================

stoleus_rollback_registry_reset() {

    stoleus_metadata_collection_reset \
        "$STOLEUS_ROLLBACK_REGISTRY_COLLECTION_ID" ||
        return $?


    stoleus_rollback_registry_create_collection || return $?


    STOLEUS_ROLLBACK_REGISTRY_READY="false"


    return 0
}


# ==============================================================================
# stoleus_rollback_registry_is_frozen
# ==============================================================================

stoleus_rollback_registry_is_frozen() {

    if ! stoleus_metadata_collection_exists \
        "$STOLEUS_ROLLBACK_REGISTRY_COLLECTION_ID"; then

        return 1
    fi


    stoleus_metadata_collection_is_frozen \
        "$STOLEUS_ROLLBACK_REGISTRY_COLLECTION_ID"
}


# ==============================================================================
# stoleus_rollback_registry_freeze
# ==============================================================================

stoleus_rollback_registry_freeze() {

    if stoleus_rollback_registry_is_frozen; then
        return 0
    fi


    stoleus_metadata_collection_freeze \
        "$STOLEUS_ROLLBACK_REGISTRY_COLLECTION_ID" ||
        return $?


    STOLEUS_ROLLBACK_REGISTRY_READY="true"


    return 0
}


# ==============================================================================
# stoleus_rollback_registry_contains
# ==============================================================================

stoleus_rollback_registry_contains() {

    local plugin_id="${1:-}"
    local forward_stage="${2:-}"
    local rollback_key=""


    if [[ -z "$plugin_id" || -z "$forward_stage" ]]; then
        return 2
    fi


    rollback_key="${plugin_id}@${forward_stage}"


    stoleus_metadata_collection_contains \
        "$STOLEUS_ROLLBACK_REGISTRY_COLLECTION_ID" \
        "$rollback_key"
}


# ==============================================================================
# stoleus_rollback_registry_register
# ==============================================================================

stoleus_rollback_registry_register() {

    local plugin_id="${1:-}"
    local forward_stage="${2:-}"
    local rollback_function="${3:-}"

    local rollback_key=""


    if stoleus_rollback_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Rollback Registry is immutable after it is frozen." >&2

        return 8
    fi


    stoleus_rollback_registry_validate_plugin_id \
        "$plugin_id" ||
        return $?


    stoleus_rollback_registry_validate_stage \
        "$forward_stage" ||
        return $?


    stoleus_rollback_registry_validate_function \
        "$rollback_function" ||
        return $?


    rollback_key="${plugin_id}@${forward_stage}"


    if stoleus_metadata_collection_contains \
        "$STOLEUS_ROLLBACK_REGISTRY_COLLECTION_ID" \
        "$rollback_key"; then

        printf '%s\n' \
            "ERROR: Duplicate rollback action: ${rollback_key}" >&2

        return 8
    fi


    stoleus_metadata_collection_append \
        "$STOLEUS_ROLLBACK_REGISTRY_COLLECTION_ID" \
        "$rollback_key" \
        "$plugin_id" \
        "$forward_stage" \
        "$rollback_function" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_rollback_registry_get_field
# ==============================================================================

stoleus_rollback_registry_get_field() {

    local plugin_id="${1:-}"
    local forward_stage="${2:-}"
    local field_name="${3:-}"

    local rollback_key=""


    if [[ -z "$plugin_id" ||
          -z "$forward_stage" ||
          -z "$field_name" ]]; then

        printf '%s\n' \
            "ERROR: Rollback lookup requires plugin ID, stage, and field name." \
            >&2

        return 2
    fi


    rollback_key="${plugin_id}@${forward_stage}"


    stoleus_metadata_collection_get_field \
        "$STOLEUS_ROLLBACK_REGISTRY_COLLECTION_ID" \
        "$rollback_key" \
        "$field_name"

    return $?
}


# ==============================================================================
# stoleus_rollback_registry_get_function
# ==============================================================================

stoleus_rollback_registry_get_function() {

    local plugin_id="${1:-}"
    local forward_stage="${2:-}"


    stoleus_rollback_registry_get_field \
        "$plugin_id" \
        "$forward_stage" \
        "rollback-function"

    return $?
}


# ==============================================================================
# stoleus_rollback_registry_get_count
# ==============================================================================

stoleus_rollback_registry_get_count() {

    stoleus_metadata_collection_get_count \
        "$STOLEUS_ROLLBACK_REGISTRY_COLLECTION_ID"

    return $?
}


# ==============================================================================
# stoleus_rollback_registry_list
# ==============================================================================

stoleus_rollback_registry_list() {

    stoleus_metadata_collection_list \
        "$STOLEUS_ROLLBACK_REGISTRY_COLLECTION_ID" \
        "plugin-id" \
        "forward-stage" \
        "rollback-function"

    return $?
}


# ==============================================================================
# stoleus_rollback_registry_initialize
# ==============================================================================

stoleus_rollback_registry_initialize() {

    if [[ "${STOLEUS_ROLLBACK_REGISTRY_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_rollback_registry_reset || return $?


    STOLEUS_ROLLBACK_REGISTRY_INITIALIZED="true"


    return 0
}

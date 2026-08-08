#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Provider Selection Trace
# ==============================================================================
#
# Purpose:
#     Record structured provider-selection decisions for diagnostics.
#
# Internal API:
#
#     stoleus_provider_trace_initialize
#     stoleus_provider_trace_reset
#     stoleus_provider_trace_append
#     stoleus_provider_trace_get_count
#     stoleus_provider_trace_get_field
#     stoleus_provider_trace_list
# ==============================================================================

set -Eeuo pipefail


if [[ "${STOLEUS_PROVIDER_TRACE_LOADED:-false}" == "true" ]]; then
    return 0
fi

STOLEUS_PROVIDER_TRACE_LOADED="true"


readonly STOLEUS_PROVIDER_TRACE_COLLECTION_ID="provider-selection-trace"

STOLEUS_PROVIDER_TRACE_INITIALIZED="false"


stoleus_provider_trace_create_collection() {

    if stoleus_metadata_collection_exists \
        "$STOLEUS_PROVIDER_TRACE_COLLECTION_ID"; then

        return 0
    fi


    stoleus_metadata_collection_create \
        "$STOLEUS_PROVIDER_TRACE_COLLECTION_ID" \
        "trace-key" \
        "trace-key" \
        "subject-type" \
        "subject-id" \
        "provider-id" \
        "enabled" \
        "conditions" \
        "condition-result" \
        "priority" \
        "decision" \
        "reason" ||
        return $?


    return 0
}


stoleus_provider_trace_reset() {

    if [[ "${STOLEUS_PROVIDER_TRACE_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Provider Trace must be initialized before reset." >&2

        return 6
    fi


    stoleus_metadata_collection_reset \
        "$STOLEUS_PROVIDER_TRACE_COLLECTION_ID" ||
        return $?


    # Metadata collection reset removes the collection definition itself.
    # Recreate the empty schema so the trace registry remains usable.
    stoleus_provider_trace_create_collection || return $?


    return 0
}


stoleus_provider_trace_append() {

    local subject_type="${1:-}"
    local subject_id="${2:-}"
    local provider_id="${3:-}"
    local enabled="${4:-}"
    local conditions="${5:-}"
    local condition_result="${6:-}"
    local priority="${7:-}"
    local decision="${8:-}"
    local reason="${9:-}"

    local trace_index=0
    local trace_key=""


    if [[ -z "$subject_type" ||
          -z "$subject_id" ||
          -z "$provider_id" ||
          -z "$enabled" ||
          -z "$condition_result" ||
          -z "$priority" ||
          -z "$decision" ]]; then

        printf '%s\n' \
            "ERROR: Provider trace append received incomplete metadata." >&2

        return 2
    fi


    trace_index="$(
        stoleus_provider_trace_get_count
    )" || return $?


    trace_key="${subject_type}:${subject_id}@${provider_id}#${trace_index}"


    stoleus_metadata_collection_append \
        "$STOLEUS_PROVIDER_TRACE_COLLECTION_ID" \
        "$trace_key" \
        "$subject_type" \
        "$subject_id" \
        "$provider_id" \
        "$enabled" \
        "$conditions" \
        "$condition_result" \
        "$priority" \
        "$decision" \
        "$reason" ||
        return $?


    return 0
}


stoleus_provider_trace_get_count() {

    stoleus_metadata_collection_get_count \
        "$STOLEUS_PROVIDER_TRACE_COLLECTION_ID"

    return $?
}


stoleus_provider_trace_get_field() {

    local trace_key="${1:-}"
    local field_name="${2:-}"


    if [[ -z "$trace_key" || -z "$field_name" ]]; then
        return 2
    fi


    stoleus_metadata_collection_get_field \
        "$STOLEUS_PROVIDER_TRACE_COLLECTION_ID" \
        "$trace_key" \
        "$field_name"

    return $?
}


stoleus_provider_trace_list() {

    stoleus_metadata_collection_list \
        "$STOLEUS_PROVIDER_TRACE_COLLECTION_ID"

    return $?
}


stoleus_provider_trace_initialize() {

    if [[ "${STOLEUS_PROVIDER_TRACE_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_provider_trace_create_collection || return $?


    STOLEUS_PROVIDER_TRACE_INITIALIZED="true"


    return 0
}

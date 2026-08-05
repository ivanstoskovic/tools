#!/usr/bin/env bash

# ==============================================================================
# Test-only Plugin Registry Storage Helpers
# ==============================================================================
#
# These helpers deliberately mutate generic metadata storage to construct
# invalid graphs for Resolver and Planning tests.
#
# Production code must never source this file.
# ==============================================================================

stoleus_test_registry_replace_field() {

    local plugin_id="${1:-}"
    local field_name="${2:-}"
    local field_value="${3:-}"

    local registry_index=""
    local value_key=""


    if [[ -z "$plugin_id" || -z "$field_name" ]]; then

        printf '%s\n' \
            "ERROR: Test Registry mutation requires plugin ID and field name." \
            >&2

        return 2
    fi


    registry_index="$(
        stoleus_registry_get_index "$plugin_id"
    )" || return $?


    value_key="${STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID}|${registry_index}|${field_name}"


    if [[ -z "${STOLEUS_METADATA_VALUES[$value_key]+stored}" ]]; then

        printf '%s\n' \
            "ERROR: Test Registry field does not exist: ${plugin_id}.${field_name}" \
            >&2

        return 6
    fi


    STOLEUS_METADATA_VALUES["$value_key"]="$field_value"

    return 0
}

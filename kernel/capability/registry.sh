#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Capability Registry
# ==============================================================================
#
# Purpose:
#     Import provided-capability declarations from the immutable Plugin
#     Registry into a dedicated immutable metadata collection.
#
# Processing flow:
#
#     Plugin Registry
#         ↓
#     required-capability metadata validation
#         ↓
#     provided-capability normalization
#         ↓
#     Generic Metadata Collection: capability-providers
#         ↓
#     Frozen Capability Registry
#
# Capability Registry responsibilities:
#
#     - validate required and provided capability identifiers;
#     - register capability-to-plugin provider records;
#     - prevent duplicate provider records;
#     - preserve deterministic provider insertion order;
#     - expose capability-oriented query APIs.
#
# Capability Registry does not:
#
#     - select one provider;
#     - apply platform context;
#     - modify plugin dependencies;
#     - build execution plans;
#     - load plugin implementations.
#
# Public API:
#
#     stoleus_capability_registry_initialize
#     stoleus_capability_registry_import_plugins
#     stoleus_capability_registry_contains
#     stoleus_capability_registry_get_count
#     stoleus_capability_registry_get_field
#     stoleus_capability_registry_get_provider
#     stoleus_capability_registry_list
#     stoleus_capability_registry_list_providers
#     stoleus_capability_registry_is_frozen
#     stoleus_capability_registry_reset
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_CAPABILITY_REGISTRY_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_CAPABILITY_REGISTRY_SUBSYSTEM_LOADED="true"


# ==============================================================================
# Constants
# ==============================================================================

readonly STOLEUS_CAPABILITY_REGISTRY_COLLECTION_ID="capability-providers"


# ==============================================================================
# stoleus_capability_registry_is_frozen
# ==============================================================================

stoleus_capability_registry_is_frozen() {

    if ! stoleus_metadata_collection_exists \
        "$STOLEUS_CAPABILITY_REGISTRY_COLLECTION_ID"; then

        return 1
    fi


    stoleus_metadata_collection_is_frozen \
        "$STOLEUS_CAPABILITY_REGISTRY_COLLECTION_ID"
}


# ==============================================================================
# stoleus_capability_registry_create_collection
# ==============================================================================

stoleus_capability_registry_create_collection() {

    if stoleus_metadata_collection_exists \
        "$STOLEUS_CAPABILITY_REGISTRY_COLLECTION_ID"; then

        return 0
    fi


    stoleus_metadata_collection_create \
        "$STOLEUS_CAPABILITY_REGISTRY_COLLECTION_ID" \
        "provider-key" \
        "provider-key" \
        "capability-id" \
        "provider-plugin-id" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_capability_registry_reset
# ==============================================================================

stoleus_capability_registry_reset() {

    stoleus_metadata_collection_reset \
        "$STOLEUS_CAPABILITY_REGISTRY_COLLECTION_ID" ||
        return $?


    STOLEUS_CAPABILITY_REGISTRY_IMPORTED="false"
    STOLEUS_CAPABILITY_REGISTRY_READY="false"


    stoleus_capability_registry_create_collection || return $?


    return 0
}


# ==============================================================================
# stoleus_capability_registry_validate_id
# ==============================================================================

stoleus_capability_registry_validate_id() {

    local capability_id="${1:-}"


    if [[ -z "$capability_id" ]]; then

        printf '%s\n' \
            "ERROR: Capability ID is required." >&2

        return 2
    fi


    if [[ ! "$capability_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid capability ID: ${capability_id}" >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_capability_registry_parse_list
# ==============================================================================

stoleus_capability_registry_parse_list() {

    local capability_list="${1:-}"


    if [[ -z "$capability_list" ]]; then
        return 0
    fi


    printf '%s\n' "$capability_list" |
        tr ',' '\n'

    return 0
}


# ==============================================================================
# stoleus_capability_registry_contains
# ==============================================================================

stoleus_capability_registry_contains() {

    local provider_key="${1:-}"


    if [[ -z "$provider_key" ]]; then
        return 2
    fi


    stoleus_metadata_collection_contains \
        "$STOLEUS_CAPABILITY_REGISTRY_COLLECTION_ID" \
        "$provider_key"
}


# ==============================================================================
# stoleus_capability_registry_get_count
# ==============================================================================

stoleus_capability_registry_get_count() {

    stoleus_metadata_collection_get_count \
        "$STOLEUS_CAPABILITY_REGISTRY_COLLECTION_ID"

    return $?
}


# ==============================================================================
# stoleus_capability_registry_get_field
# ==============================================================================

stoleus_capability_registry_get_field() {

    local provider_key="${1:-}"
    local field_name="${2:-}"


    if [[ -z "$provider_key" || -z "$field_name" ]]; then

        printf '%s\n' \
            "ERROR: Capability Registry field lookup requires provider key and field name." \
            >&2

        return 2
    fi


    stoleus_metadata_collection_get_field \
        "$STOLEUS_CAPABILITY_REGISTRY_COLLECTION_ID" \
        "$provider_key" \
        "$field_name"

    return $?
}


# ==============================================================================
# stoleus_capability_registry_validate_required
# ==============================================================================

stoleus_capability_registry_validate_required() {

    local plugin_id="${1:-}"
    local required_capabilities="${2:-}"

    local capability_id=""

    local -A seen_capabilities=()


    while IFS= read -r capability_id; do

        [[ -z "$capability_id" ]] && continue


        stoleus_capability_registry_validate_id \
            "$capability_id" ||
            return $?


        if [[ -n "${seen_capabilities[$capability_id]+declared}" ]]; then

            printf '%s\n' \
                "ERROR: Plugin '${plugin_id}' declares duplicate required capability: ${capability_id}" \
                >&2

            return 8
        fi


        seen_capabilities["$capability_id"]="true"

    done < <(
        stoleus_capability_registry_parse_list \
            "$required_capabilities"
    )


    return 0
}


# ==============================================================================
# stoleus_capability_registry_import_provider
# ==============================================================================

stoleus_capability_registry_import_provider() {

    local plugin_id="${1:-}"
    local capability_id="${2:-}"

    local provider_key=""


    if [[ -z "$plugin_id" || -z "$capability_id" ]]; then

        printf '%s\n' \
            "ERROR: Capability provider import requires plugin ID and capability ID." \
            >&2

        return 2
    fi


    stoleus_capability_registry_validate_id \
        "$capability_id" ||
        return $?


    if ! stoleus_registry_contains "$plugin_id"; then

        printf '%s\n' \
            "ERROR: Capability provider references an unknown plugin: ${plugin_id}" \
            >&2

        return 6
    fi


    provider_key="${capability_id}@${plugin_id}"


    if stoleus_capability_registry_contains "$provider_key"; then

        printf '%s\n' \
            "ERROR: Duplicate capability provider registration: ${provider_key}" \
            >&2

        return 8
    fi


    stoleus_metadata_collection_append \
        "$STOLEUS_CAPABILITY_REGISTRY_COLLECTION_ID" \
        "$provider_key" \
        "$capability_id" \
        "$plugin_id" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_capability_registry_import_plugin
# ==============================================================================

stoleus_capability_registry_import_plugin() {

    local plugin_id="${1:-}"

    local required_capabilities=""
    local provided_capabilities=""
    local capability_id=""

    local -A seen_provided_capabilities=()


    if [[ -z "$plugin_id" ]]; then

        printf '%s\n' \
            "ERROR: Capability Registry plugin import requires a plugin ID." \
            >&2

        return 2
    fi


    required_capabilities="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "capabilities"
    )" || return $?


    provided_capabilities="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "provided-capabilities"
    )" || return $?


    stoleus_capability_registry_validate_required \
        "$plugin_id" \
        "$required_capabilities" ||
        return $?


    while IFS= read -r capability_id; do

        [[ -z "$capability_id" ]] && continue


        if [[ -n "${seen_provided_capabilities[$capability_id]+declared}" ]]; then

            printf '%s\n' \
                "ERROR: Plugin '${plugin_id}' declares duplicate provided capability: ${capability_id}" \
                >&2

            return 8
        fi


        seen_provided_capabilities["$capability_id"]="true"


        stoleus_capability_registry_import_provider \
            "$plugin_id" \
            "$capability_id" ||
            return $?

    done < <(
        stoleus_capability_registry_parse_list \
            "$provided_capabilities"
    )


    return 0
}


# ==============================================================================
# stoleus_capability_registry_import_plugins
# ==============================================================================

stoleus_capability_registry_import_plugins() {

    local plugin_id=""
    local existing_count=0


    if [[ "${STOLEUS_CAPABILITY_REGISTRY_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Capability Registry must be initialized before import." \
            >&2

        return 6
    fi


    if ! stoleus_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Plugin Registry must be frozen before Capability Registry import." \
            >&2

        return 6
    fi


    if stoleus_capability_registry_is_frozen; then
        return 0
    fi


    if [[ "${STOLEUS_CAPABILITY_REGISTRY_IMPORTED:-false}" == "true" ]]; then

        printf '%s\n' \
            "ERROR: Plugins were already imported into the Capability Registry." \
            >&2

        return 8
    fi


    existing_count="$(
        stoleus_capability_registry_get_count
    )" || return $?


    if (( existing_count != 0 )); then

        printf '%s\n' \
            "ERROR: Capability Registry must be empty before plugin import." \
            >&2

        return 8
    fi


    while IFS= read -r plugin_id; do

        [[ -z "$plugin_id" ]] && continue


        stoleus_capability_registry_import_plugin \
            "$plugin_id" ||
            return $?

    done < <(
        stoleus_registry_list_ids
    )


    STOLEUS_CAPABILITY_REGISTRY_IMPORTED="true"


    stoleus_metadata_collection_freeze \
        "$STOLEUS_CAPABILITY_REGISTRY_COLLECTION_ID" ||
        return $?


    STOLEUS_CAPABILITY_REGISTRY_READY="true"


    return 0
}


# ==============================================================================
# stoleus_capability_registry_get_provider
# ==============================================================================

stoleus_capability_registry_get_provider() {

    local capability_id="${1:-}"
    local plugin_id="${2:-}"


    if [[ -z "$capability_id" || -z "$plugin_id" ]]; then

        printf '%s\n' \
            "ERROR: Capability provider lookup requires capability ID and plugin ID." \
            >&2

        return 2
    fi


    stoleus_capability_registry_get_field \
        "${capability_id}@${plugin_id}" \
        "provider-plugin-id"

    return $?
}


# ==============================================================================
# stoleus_capability_registry_list
# ==============================================================================

stoleus_capability_registry_list() {

    stoleus_metadata_collection_list \
        "$STOLEUS_CAPABILITY_REGISTRY_COLLECTION_ID" \
        "capability-id" \
        "provider-plugin-id"

    return $?
}


# ==============================================================================
# stoleus_capability_registry_list_providers
# ==============================================================================

stoleus_capability_registry_list_providers() {

    local requested_capability="${1:-}"

    local row_count=0
    local row_index=0

    local provider_key=""
    local capability_id=""
    local provider_plugin_id=""


    if [[ -z "$requested_capability" ]]; then

        printf '%s\n' \
            "ERROR: Capability provider listing requires a capability ID." \
            >&2

        return 2
    fi


    stoleus_capability_registry_validate_id \
        "$requested_capability" ||
        return $?


    row_count="$(
        stoleus_capability_registry_get_count
    )" || return $?


    for ((row_index = 0; row_index < row_count; row_index++)); do

        provider_key="$(
            stoleus_metadata_collection_get_key_by_index \
                "$STOLEUS_CAPABILITY_REGISTRY_COLLECTION_ID" \
                "$row_index"
        )" || return $?


        capability_id="$(
            stoleus_capability_registry_get_field \
                "$provider_key" \
                "capability-id"
        )" || return $?


        [[ "$capability_id" != "$requested_capability" ]] && continue


        provider_plugin_id="$(
            stoleus_capability_registry_get_field \
                "$provider_key" \
                "provider-plugin-id"
        )" || return $?


        printf '%s\n' "$provider_plugin_id"
    done


    return 0
}


# ==============================================================================
# stoleus_capability_registry_initialize
# ==============================================================================

stoleus_capability_registry_initialize() {

    if [[ "${STOLEUS_CAPABILITY_REGISTRY_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_capability_registry_reset || return $?


    STOLEUS_CAPABILITY_REGISTRY_INITIALIZED="true"


    return 0
}

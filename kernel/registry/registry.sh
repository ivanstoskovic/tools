#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Plugin Registry
# ==============================================================================
#
# Purpose:
#     Import validated PluginDefinitions into an immutable generic metadata
#     collection.
#
# Processing flow:
#
#     PluginDefinitions
#         ↓
#     Plugin-specific validation
#         ↓
#     Generic Metadata Collection: plugins
#         ↓
#     Frozen Plugin Registry
#
# The generic Metadata subsystem owns:
#
#     - schema enforcement;
#     - row storage;
#     - insertion order;
#     - indexed key lookup;
#     - collection freezing;
#     - generic field projection.
#
# The Plugin Registry owns:
#
#     - plugin-specific schema;
#     - PluginDefinition validation and import;
#     - plugin-oriented public APIs;
#     - lifecycle-reference validation.
#
# Public API:
#
#     stoleus_registry_initialize
#     stoleus_registry_import_definitions
#     stoleus_registry_contains
#     stoleus_registry_get_index
#     stoleus_registry_get_field
#     stoleus_registry_get_field_by_index
#     stoleus_registry_get_id_by_index
#     stoleus_registry_get_count
#     stoleus_registry_list
#     stoleus_registry_list_ids
#     stoleus_registry_freeze
#     stoleus_registry_is_frozen
#     stoleus_registry_reset
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_REGISTRY_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_REGISTRY_SUBSYSTEM_LOADED="true"


# ==============================================================================
# Registry Constants
# ==============================================================================

readonly STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID="plugins"


# ==============================================================================
# stoleus_registry_is_frozen
# ==============================================================================

stoleus_registry_is_frozen() {

    if ! stoleus_metadata_collection_exists \
        "$STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID"; then

        return 1
    fi


    stoleus_metadata_collection_is_frozen \
        "$STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID"
}


# ==============================================================================
# stoleus_registry_reset
# ==============================================================================
#
# Purpose:
#     Remove Registry-owned metadata and return the adapter to an unimported
#     state.
#
# PluginDefinition state is not modified.
# ==============================================================================

stoleus_registry_reset() {

    # --------------------------------------------------------------------------
    # Remove the current Registry collection and all stored plugin rows.
    # --------------------------------------------------------------------------
    stoleus_metadata_collection_reset \
        "$STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID" ||
        return $?


    STOLEUS_REGISTRY_IMPORTED="false"
    STOLEUS_REGISTRY_READY="false"


    # --------------------------------------------------------------------------
    # Restore the Registry to its normal empty mutable state.
    #
    # Historically, stoleus_registry_reset() cleared Registry data while
    # leaving the Registry immediately usable. Preserve that contract after the
    # migration to generic metadata storage.
    #
    # This also allows tests and future explicit bootstrap resets to rebuild
    # definitions without reinitializing the complete kernel process.
    # --------------------------------------------------------------------------
    stoleus_registry_create_collection || return $?


    return 0
}


# ==============================================================================
# stoleus_registry_create_collection
# ==============================================================================
#
# Schema:
#
#     id
#     category
#     description
#     plugin-path
#     implementation
#     dependencies
#     capabilities
#     manifest
#     manifest-provider
#     install
#     configure
#     verify
#     upgrade
#     remove
# ==============================================================================

stoleus_registry_create_collection() {

    if stoleus_metadata_collection_exists \
        "$STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID"; then

        return 0
    fi


    stoleus_metadata_collection_create \
        "$STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID" \
        "id" \
        "id" \
        "category" \
        "description" \
        "plugin-path" \
        "implementation" \
        "dependencies" \
        "capabilities" \
        "manifest" \
        "manifest-provider" \
        "install" \
        "configure" \
        "verify" \
        "upgrade" \
        "remove" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_registry_contains
# ==============================================================================

stoleus_registry_contains() {

    local plugin_id="${1:-}"


    if [[ -z "$plugin_id" ]]; then
        return 2
    fi


    if ! stoleus_metadata_collection_exists \
        "$STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID"; then

        return 6
    fi


    stoleus_metadata_collection_contains \
        "$STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID" \
        "$plugin_id"
}


# ==============================================================================
# stoleus_registry_get_index
# ==============================================================================

stoleus_registry_get_index() {

    local plugin_id="${1:-}"


    if [[ -z "$plugin_id" ]]; then

        printf '%s\n' \
            "ERROR: Registry lookup requires a plugin ID." >&2

        return 2
    fi


    stoleus_metadata_collection_get_index \
        "$STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID" \
        "$plugin_id"

    return $?
}


# ==============================================================================
# stoleus_registry_get_count
# ==============================================================================

stoleus_registry_get_count() {

    stoleus_metadata_collection_get_count \
        "$STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID"

    return $?
}


# ==============================================================================
# stoleus_registry_get_id_by_index
# ==============================================================================

stoleus_registry_get_id_by_index() {

    local registry_index="${1:-}"


    if [[ -z "$registry_index" ||
          ! "$registry_index" =~ ^[0-9]+$ ]]; then

        printf '%s\n' \
            "ERROR: Registry index lookup requires a numeric index." >&2

        return 2
    fi


    stoleus_metadata_collection_get_key_by_index \
        "$STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID" \
        "$registry_index"

    return $?
}


# ==============================================================================
# stoleus_registry_get_field
# ==============================================================================

stoleus_registry_get_field() {

    local plugin_id="${1:-}"
    local field_name="${2:-}"


    if [[ -z "$plugin_id" || -z "$field_name" ]]; then

        printf '%s\n' \
            "ERROR: Registry field lookup requires plugin ID and field name." \
            >&2

        return 2
    fi


    stoleus_metadata_collection_get_field \
        "$STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID" \
        "$plugin_id" \
        "$field_name"

    return $?
}


# ==============================================================================
# stoleus_registry_get_field_by_index
# ==============================================================================

stoleus_registry_get_field_by_index() {

    local registry_index="${1:-}"
    local field_name="${2:-}"

    local plugin_id=""


    if [[ -z "$registry_index" ||
          ! "$registry_index" =~ ^[0-9]+$ ||
          -z "$field_name" ]]; then

        printf '%s\n' \
            "ERROR: Indexed Registry lookup requires index and field name." \
            >&2

        return 2
    fi


    plugin_id="$(
        stoleus_registry_get_id_by_index \
            "$registry_index"
    )" || return $?


    stoleus_registry_get_field \
        "$plugin_id" \
        "$field_name"

    return $?
}


# ==============================================================================
# stoleus_registry_validate_function_reference
# ==============================================================================

stoleus_registry_validate_function_reference() {

    local plugin_id="${1:-}"
    local lifecycle_stage="${2:-}"
    local function_reference="${3:-}"


    if [[ -z "$function_reference" ]]; then
        return 0
    fi


    if [[ ! "$function_reference" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then

        printf '%s\n' \
            "ERROR: Registry plugin '${plugin_id}' has an invalid ${lifecycle_stage} function reference: ${function_reference}" \
            >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_registry_validate_reference_list
# ==============================================================================
#
# Purpose:
#     Validate comma-separated plugin IDs or capability IDs.
#
# Arguments:
#
#     $1 = owner plugin ID
#     $2 = metadata field name
#     $3 = comma-separated values
# ==============================================================================

stoleus_registry_validate_reference_list() {

    local plugin_id="${1:-}"
    local field_name="${2:-}"
    local values="${3:-}"

    local value=""

    local -A seen_values=()


    if [[ -z "$values" ]]; then
        return 0
    fi


    while IFS= read -r value; do

        value="$(
            printf '%s' "$value" |
                sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
        )"


        [[ -z "$value" ]] && continue


        if [[ ! "$value" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

            printf '%s\n' \
                "ERROR: Registry plugin '${plugin_id}' has an invalid ${field_name} reference: ${value}" \
                >&2

            return 6
        fi


        if [[ -n "${seen_values[$value]+seen}" ]]; then

            printf '%s\n' \
                "ERROR: Registry plugin '${plugin_id}' declares duplicate ${field_name} reference: ${value}" \
                >&2

            return 8
        fi


        seen_values["$value"]="true"

    done < <(
        printf '%s\n' "$values" |
            tr ',' '\n'
    )


    return 0
}


# ==============================================================================
# stoleus_registry_validate_definition
# ==============================================================================

stoleus_registry_validate_definition() {

    local definition_index="${1:-}"

    local plugin_id=""
    local category=""
    local description=""
    local plugin_path=""
    local implementation_path=""
    local dependencies=""
    local capabilities=""
    local manifest_path=""
    local manifest_provider=""

    local install_function=""
    local configure_function=""
    local verify_function=""
    local upgrade_function=""
    local remove_function=""


    if [[ -z "$definition_index" ||
          ! "$definition_index" =~ ^[0-9]+$ ]]; then

        printf '%s\n' \
            "ERROR: Registry import received an invalid Definition index." \
            >&2

        return 2
    fi


    plugin_id="${STOLEUS_DEFINITION_IDS[$definition_index]:-}"
    category="${STOLEUS_DEFINITION_CATEGORIES[$definition_index]:-}"
    description="${STOLEUS_DEFINITION_DESCRIPTIONS[$definition_index]:-}"
    plugin_path="${STOLEUS_DEFINITION_PLUGIN_PATHS[$definition_index]:-}"
    implementation_path="${STOLEUS_DEFINITION_IMPLEMENTATIONS[$definition_index]:-}"
    dependencies="${STOLEUS_DEFINITION_DEPENDENCIES[$definition_index]:-}"
    capabilities="${STOLEUS_DEFINITION_CAPABILITIES[$definition_index]:-}"
    manifest_path="${STOLEUS_DEFINITION_MANIFEST_PATHS[$definition_index]:-}"
    manifest_provider="${STOLEUS_DEFINITION_MANIFEST_PROVIDERS[$definition_index]:-}"

    install_function="${STOLEUS_DEFINITION_INSTALL_FUNCTIONS[$definition_index]:-}"
    configure_function="${STOLEUS_DEFINITION_CONFIGURE_FUNCTIONS[$definition_index]:-}"
    verify_function="${STOLEUS_DEFINITION_VERIFY_FUNCTIONS[$definition_index]:-}"
    upgrade_function="${STOLEUS_DEFINITION_UPGRADE_FUNCTIONS[$definition_index]:-}"
    remove_function="${STOLEUS_DEFINITION_REMOVE_FUNCTIONS[$definition_index]:-}"


    if [[ -z "$plugin_id" ||
          ! "$plugin_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Registry import found an invalid plugin ID: ${plugin_id}" \
            >&2

        return 6
    fi


    if stoleus_registry_contains "$plugin_id"; then

        printf '%s\n' \
            "ERROR: Duplicate Registry plugin ID: $plugin_id" >&2

        return 8
    fi


    if [[ -z "$category" ||
          ! "$category" =~ ^[a-z][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Registry plugin '${plugin_id}' has an invalid category: ${category}" \
            >&2

        return 6
    fi


    if [[ -z "$description" ]]; then

        printf '%s\n' \
            "ERROR: Registry plugin '${plugin_id}' requires a description." \
            >&2

        return 6
    fi


    if [[ -z "$plugin_path" || ! -d "$plugin_path" ]]; then

        printf '%s\n' \
            "ERROR: Registry plugin '${plugin_id}' directory is invalid: ${plugin_path}" \
            >&2

        return 6
    fi


    if [[ -z "$implementation_path" || ! -f "$implementation_path" ]]; then

        printf '%s\n' \
            "ERROR: Registry plugin '${plugin_id}' implementation is missing: ${implementation_path}" \
            >&2

        return 6
    fi


    if [[ -z "$manifest_path" || ! -f "$manifest_path" ]]; then

        printf '%s\n' \
            "ERROR: Registry plugin '${plugin_id}' manifest is missing: ${manifest_path}" \
            >&2

        return 6
    fi


    if [[ -z "$manifest_provider" ]]; then

        printf '%s\n' \
            "ERROR: Registry plugin '${plugin_id}' requires a manifest provider." \
            >&2

        return 6
    fi


    stoleus_registry_validate_reference_list \
        "$plugin_id" \
        "dependency" \
        "$dependencies" ||
        return $?


    stoleus_registry_validate_reference_list \
        "$plugin_id" \
        "capability" \
        "$capabilities" ||
        return $?


    stoleus_registry_validate_function_reference \
        "$plugin_id" \
        "install" \
        "$install_function" ||
        return $?


    stoleus_registry_validate_function_reference \
        "$plugin_id" \
        "configure" \
        "$configure_function" ||
        return $?


    stoleus_registry_validate_function_reference \
        "$plugin_id" \
        "verify" \
        "$verify_function" ||
        return $?


    stoleus_registry_validate_function_reference \
        "$plugin_id" \
        "upgrade" \
        "$upgrade_function" ||
        return $?


    stoleus_registry_validate_function_reference \
        "$plugin_id" \
        "remove" \
        "$remove_function" ||
        return $?


    if [[ -z "$install_function" &&
          -z "$configure_function" &&
          -z "$verify_function" &&
          -z "$upgrade_function" &&
          -z "$remove_function" ]]; then

        printf '%s\n' \
            "ERROR: Registry plugin '${plugin_id}' does not expose a lifecycle function." \
            >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_registry_append_definition
# ==============================================================================

stoleus_registry_append_definition() {

    local definition_index="${1:-}"


    if stoleus_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Registry is immutable after it is frozen." >&2

        return 8
    fi


    stoleus_registry_validate_definition \
        "$definition_index" ||
        return $?


    stoleus_metadata_collection_append \
        "$STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID" \
        "${STOLEUS_DEFINITION_IDS[$definition_index]}" \
        "${STOLEUS_DEFINITION_CATEGORIES[$definition_index]}" \
        "${STOLEUS_DEFINITION_DESCRIPTIONS[$definition_index]}" \
        "${STOLEUS_DEFINITION_PLUGIN_PATHS[$definition_index]}" \
        "${STOLEUS_DEFINITION_IMPLEMENTATIONS[$definition_index]}" \
        "${STOLEUS_DEFINITION_DEPENDENCIES[$definition_index]}" \
        "${STOLEUS_DEFINITION_CAPABILITIES[$definition_index]}" \
        "${STOLEUS_DEFINITION_MANIFEST_PATHS[$definition_index]}" \
        "${STOLEUS_DEFINITION_MANIFEST_PROVIDERS[$definition_index]}" \
        "${STOLEUS_DEFINITION_INSTALL_FUNCTIONS[$definition_index]}" \
        "${STOLEUS_DEFINITION_CONFIGURE_FUNCTIONS[$definition_index]}" \
        "${STOLEUS_DEFINITION_VERIFY_FUNCTIONS[$definition_index]}" \
        "${STOLEUS_DEFINITION_UPGRADE_FUNCTIONS[$definition_index]}" \
        "${STOLEUS_DEFINITION_REMOVE_FUNCTIONS[$definition_index]}" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_registry_freeze
# ==============================================================================

stoleus_registry_freeze() {

    if stoleus_registry_is_frozen; then
        return 0
    fi


    stoleus_metadata_collection_freeze \
        "$STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID" ||
        return $?


    STOLEUS_REGISTRY_READY="true"


    return 0
}


# ==============================================================================
# stoleus_registry_import_definitions
# ==============================================================================

stoleus_registry_import_definitions() {

    local definition_index=0
    local existing_count=0


    if [[ "${STOLEUS_REGISTRY_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Registry must be initialized before importing definitions." \
            >&2

        return 6
    fi


    if [[ "${STOLEUS_DEFINITION_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Definition subsystem must be initialized before Registry import." \
            >&2

        return 6
    fi


    if ! stoleus_definition_is_frozen; then

        printf '%s\n' \
            "ERROR: PluginDefinitions must be frozen before Registry import." \
            >&2

        return 6
    fi


    if stoleus_registry_is_frozen; then
        return 0
    fi


    if [[ "${STOLEUS_REGISTRY_IMPORTED:-false}" == "true" ]]; then

        printf '%s\n' \
            "ERROR: PluginDefinitions were already imported into the Registry." \
            >&2

        return 8
    fi


    existing_count="$(
        stoleus_registry_get_count
    )" || return $?


    if (( existing_count != 0 )); then

        printf '%s\n' \
            "ERROR: Registry must be empty before Definition import." >&2

        return 8
    fi


    for definition_index in "${!STOLEUS_DEFINITION_IDS[@]}"; do

        stoleus_registry_append_definition \
            "$definition_index" ||
            return $?
    done


    STOLEUS_REGISTRY_IMPORTED="true"

    stoleus_registry_freeze || return $?


    return 0
}


# ==============================================================================
# stoleus_registry_list
# ==============================================================================

stoleus_registry_list() {

    local category_filter="${1:-}"
    local plugin_id=""
    local category=""
    local description=""


    while IFS= read -r plugin_id; do

        [[ -z "$plugin_id" ]] && continue


        category="$(
            stoleus_registry_get_field \
                "$plugin_id" \
                "category"
        )" || return $?


        if [[ -n "$category_filter" ]] &&
           [[ "$category" != "$category_filter" ]]; then

            continue
        fi


        description="$(
            stoleus_registry_get_field \
                "$plugin_id" \
                "description"
        )" || return $?


        printf '%s\t%s\t%s\n' \
            "$plugin_id" \
            "$category" \
            "$description"

    done < <(
        stoleus_registry_list_ids
    )


    return 0
}


# ==============================================================================
# stoleus_registry_list_ids
# ==============================================================================

stoleus_registry_list_ids() {

    stoleus_metadata_collection_list \
        "$STOLEUS_PLUGIN_REGISTRY_COLLECTION_ID" \
        "id"

    return $?
}


# ==============================================================================
# stoleus_registry_initialize
# ==============================================================================

stoleus_registry_initialize() {

    if [[ "${STOLEUS_REGISTRY_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_registry_reset || return $?
    stoleus_registry_create_collection || return $?


    STOLEUS_REGISTRY_INITIALIZED="true"

    return 0
}

#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Plugin Manager
# ==============================================================================
#
# Purpose:
#     Expose canonical runtime views over immutable Registry metadata and
#     Lifecycle implementation-loading state.
#
# The Plugin Manager is a facade.
#
# It does not duplicate Registry metadata and does not become a second source
# of truth.
#
# It answers runtime questions such as:
#
#     - Is the plugin known?
#     - What category/type does it belong to?
#     - Which lifecycle operations does it support?
#     - What are its dependencies and required capabilities?
#     - Has its implementation been loaded?
#
# The Plugin Manager does not:
#
#     - discover plugins;
#     - parse manifests;
#     - register definitions;
#     - resolve dependency order;
#     - build plans;
#     - load implementations automatically;
#     - execute lifecycle operations.
#
# Public API:
#
#     stoleus_plugin_initialize
#     stoleus_plugin_activate
#     stoleus_plugin_is_active
#     stoleus_plugin_exists
#     stoleus_plugin_get
#     stoleus_plugin_get_field
#     stoleus_plugin_list
#     stoleus_plugin_list_operations
#     stoleus_plugin_supports_operation
#     stoleus_plugin_get_dependencies
#     stoleus_plugin_get_capabilities
#     stoleus_plugin_get_runtime_state
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_PLUGIN_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_PLUGIN_SUBSYSTEM_LOADED="true"


# ==============================================================================
# stoleus_plugin_reset
# ==============================================================================

stoleus_plugin_reset() {

    STOLEUS_PLUGIN_MANAGER_ACTIVE="false"

    return 0
}


# ==============================================================================
# stoleus_plugin_is_active
# ==============================================================================

stoleus_plugin_is_active() {

    [[ "${STOLEUS_PLUGIN_MANAGER_ACTIVE:-false}" == "true" ]]
}


# ==============================================================================
# stoleus_plugin_require_active
# ==============================================================================

stoleus_plugin_require_active() {

    if [[ "${STOLEUS_PLUGIN_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Plugin Manager must be initialized before use." >&2

        return 6
    fi


    if ! stoleus_plugin_is_active; then

        printf '%s\n' \
            "ERROR: Plugin Manager is unavailable before successful kernel metadata bootstrap." \
            >&2

        return 6
    fi


    if ! stoleus_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Plugin Manager requires a frozen Registry." >&2

        return 6
    fi


    if [[ "${STOLEUS_RESOLVER_VALIDATED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Plugin Manager requires validated Registry references." \
            >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_plugin_activate
# ==============================================================================
#
# Purpose:
#     Activate the runtime facade after Registry and Resolver validation.
#
# Activation does not load any plugin implementation.
# ==============================================================================

stoleus_plugin_activate() {

    if stoleus_plugin_is_active; then
        return 0
    fi


    if [[ "${STOLEUS_PLUGIN_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Plugin Manager must be initialized before activation." \
            >&2

        return 6
    fi


    if ! stoleus_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Plugin Manager cannot activate before Registry freeze." \
            >&2

        return 6
    fi


    if [[ "${STOLEUS_RESOLVER_VALIDATED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Plugin Manager cannot activate before Resolver validation." \
            >&2

        return 6
    fi


    STOLEUS_PLUGIN_MANAGER_ACTIVE="true"

    return 0
}


# ==============================================================================
# stoleus_plugin_exists
# ==============================================================================
#
# Arguments:
#
#     $1 = plugin ID
# ==============================================================================

stoleus_plugin_exists() {

    local plugin_id="${1:-}"


    if [[ -z "$plugin_id" ]]; then
        return 2
    fi


    stoleus_plugin_require_active || return $?

    stoleus_registry_contains "$plugin_id"
}


# ==============================================================================
# stoleus_plugin_get_field
# ==============================================================================
#
# Purpose:
#     Read one normalized plugin field.
#
# Supported Registry-backed fields:
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
#
# Runtime fields:
#
#     loaded
#     runtime-state
# ==============================================================================

stoleus_plugin_get_field() {

    local plugin_id="${1:-}"
    local field_name="${2:-}"


    if [[ -z "$plugin_id" || -z "$field_name" ]]; then

        printf '%s\n' \
            "ERROR: Plugin field lookup requires plugin ID and field name." \
            >&2

        return 2
    fi


    stoleus_plugin_require_active || return $?


    if ! stoleus_registry_contains "$plugin_id"; then

        printf '%s\n' \
            "ERROR: Unknown plugin: $plugin_id" >&2

        return 6
    fi


    case "$field_name" in

        loaded)

            if stoleus_lifecycle_is_plugin_loaded "$plugin_id"; then
                printf '%s\n' "true"
            else
                printf '%s\n' "false"
            fi

            ;;


        runtime-state)

            if stoleus_lifecycle_is_plugin_loaded "$plugin_id"; then
                printf '%s\n' "loaded"
            else
                printf '%s\n' "metadata-only"
            fi

            ;;


        *)

            stoleus_registry_get_field \
                "$plugin_id" \
                "$field_name" ||
                return $?

            ;;
    esac


    return 0
}


# ==============================================================================
# stoleus_plugin_list_operations
# ==============================================================================
#
# Purpose:
#     List lifecycle operations supported by one plugin.
#
# Arguments:
#
#     $1 = plugin ID
#
# Output:
#
#     One operation per line in canonical lifecycle order.
# ==============================================================================

stoleus_plugin_list_operations() {

    local plugin_id="${1:-}"
    local operation=""
    local function_reference=""

    local -a operations=(
        "install"
        "configure"
        "verify"
        "upgrade"
        "remove"
    )


    stoleus_plugin_require_active || return $?


    if ! stoleus_registry_contains "$plugin_id"; then

        printf '%s\n' \
            "ERROR: Unknown plugin: $plugin_id" >&2

        return 6
    fi


    for operation in "${operations[@]}"; do

        function_reference="$(
            stoleus_registry_get_field \
                "$plugin_id" \
                "$operation"
        )" || return $?


        if [[ -n "$function_reference" ]]; then
            printf '%s\n' "$operation"
        fi
    done


    return 0
}


# ==============================================================================
# stoleus_plugin_supports_operation
# ==============================================================================
#
# Arguments:
#
#     $1 = plugin ID
#     $2 = lifecycle operation
#
# Return codes:
#
#     0 = supported
#     1 = unsupported
#     2 = invalid input
#     6 = unknown plugin or inactive manager
# ==============================================================================

stoleus_plugin_supports_operation() {

    local plugin_id="${1:-}"
    local operation="${2:-}"
    local function_reference=""


    if [[ -z "$plugin_id" || -z "$operation" ]]; then
        return 2
    fi


    case "$operation" in
        install|configure|verify|upgrade|remove)
            ;;
        *)
            return 2
            ;;
    esac


    stoleus_plugin_require_active || return $?


    if ! stoleus_registry_contains "$plugin_id"; then
        return 6
    fi


    function_reference="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "$operation"
    )" || return $?


    [[ -n "$function_reference" ]]
}


# ==============================================================================
# stoleus_plugin_get_dependencies
# ==============================================================================
#
# Output:
#
#     One direct dependency ID per line.
# ==============================================================================

stoleus_plugin_get_dependencies() {

    local plugin_id="${1:-}"
    local dependency_list=""


    stoleus_plugin_require_active || return $?


    if ! stoleus_registry_contains "$plugin_id"; then

        printf '%s\n' \
            "ERROR: Unknown plugin: $plugin_id" >&2

        return 6
    fi


    dependency_list="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "dependencies"
    )" || return $?


    stoleus_resolver_parse_reference_list \
        "$dependency_list"

    return $?
}


# ==============================================================================
# stoleus_plugin_get_capabilities
# ==============================================================================
#
# Output:
#
#     One required capability ID per line.
# ==============================================================================

stoleus_plugin_get_capabilities() {

    local plugin_id="${1:-}"
    local capability_list=""


    stoleus_plugin_require_active || return $?


    if ! stoleus_registry_contains "$plugin_id"; then

        printf '%s\n' \
            "ERROR: Unknown plugin: $plugin_id" >&2

        return 6
    fi


    capability_list="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "capabilities"
    )" || return $?


    stoleus_resolver_parse_reference_list \
        "$capability_list"

    return $?
}


# ==============================================================================
# stoleus_plugin_get_runtime_state
# ==============================================================================
#
# Output format:
#
#     plugin-id<TAB>runtime-state<TAB>implementation-path
# ==============================================================================

stoleus_plugin_get_runtime_state() {

    local plugin_id="${1:-}"
    local implementation_path=""
    local runtime_state="metadata-only"


    stoleus_plugin_require_active || return $?


    if ! stoleus_registry_contains "$plugin_id"; then

        printf '%s\n' \
            "ERROR: Unknown plugin: $plugin_id" >&2

        return 6
    fi


    implementation_path="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "implementation"
    )" || return $?


    if stoleus_lifecycle_is_plugin_loaded "$plugin_id"; then
        runtime_state="loaded"
    fi


    printf '%s\t%s\t%s\n' \
        "$plugin_id" \
        "$runtime_state" \
        "$implementation_path"

    return 0
}


# ==============================================================================
# stoleus_plugin_get
# ==============================================================================
#
# Purpose:
#     Print a complete normalized plugin view.
#
# Output fields:
#
#     id
#     category
#     description
#     runtime-state
#     dependencies
#     capabilities
#     supported-operations
#
# Fields are separated by tabs.
#
# Lists inside a field use commas.
# ==============================================================================

stoleus_plugin_get() {

    local plugin_id="${1:-}"

    local category=""
    local description=""
    local runtime_state=""
    local dependencies=""
    local capabilities=""
    local operations=""


    stoleus_plugin_require_active || return $?


    if ! stoleus_registry_contains "$plugin_id"; then

        printf '%s\n' \
            "ERROR: Unknown plugin: $plugin_id" >&2

        return 6
    fi


    category="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "category"
    )" || return $?


    description="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "description"
    )" || return $?


    runtime_state="$(
        stoleus_plugin_get_field \
            "$plugin_id" \
            "runtime-state"
    )" || return $?


    dependencies="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "dependencies"
    )" || return $?


    capabilities="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "capabilities"
    )" || return $?


    operations="$(
        stoleus_plugin_list_operations \
            "$plugin_id" |
            paste -sd ',' -
    )" || return $?


    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$plugin_id" \
        "$category" \
        "$description" \
        "$runtime_state" \
        "$dependencies" \
        "$capabilities" \
        "$operations"

    return 0
}


# ==============================================================================
# stoleus_plugin_list
# ==============================================================================
#
# Purpose:
#     List normalized runtime plugin views.
#
# Optional argument:
#
#     $1 = category filter
#
# Output format:
#
#     id<TAB>category<TAB>runtime-state<TAB>description
# ==============================================================================

stoleus_plugin_list() {

    local category_filter="${1:-}"
    local registry_index=0
    local plugin_id=""
    local category=""
    local runtime_state=""


    stoleus_plugin_require_active || return $?


    for registry_index in "${!STOLEUS_REGISTRY_IDS[@]}"; do

        plugin_id="${STOLEUS_REGISTRY_IDS[$registry_index]}"
        category="${STOLEUS_REGISTRY_CATEGORIES[$registry_index]}"


        if [[ -n "$category_filter" ]] &&
           [[ "$category" != "$category_filter" ]]; then

            continue
        fi


        if stoleus_lifecycle_is_plugin_loaded "$plugin_id"; then
            runtime_state="loaded"
        else
            runtime_state="metadata-only"
        fi


        printf '%s\t%s\t%s\t%s\n' \
            "$plugin_id" \
            "$category" \
            "$runtime_state" \
            "${STOLEUS_REGISTRY_DESCRIPTIONS[$registry_index]}"
    done


    return 0
}


# ==============================================================================
# stoleus_plugin_initialize
# ==============================================================================

stoleus_plugin_initialize() {

    if [[ "${STOLEUS_PLUGIN_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_plugin_reset || return $?


    STOLEUS_PLUGIN_INITIALIZED="true"

    return 0
}

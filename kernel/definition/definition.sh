#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Definition Subsystem
# ==============================================================================
#
# Purpose:
#     Convert DiscoveryRecords into normalized PluginDefinitions.
#
# Processing flow:
#
#     DiscoveryRecord
#         ↓
#     Manifest-provider selection
#         ↓
#     Manifest parsing
#         ↓
#     Metadata validation
#         ↓
#     PluginDefinition
#
# The Definition subsystem does not:
#
#     - execute plugin implementations;
#     - source implementation files;
#     - resolve dependencies;
#     - produce execution plans;
#     - modify infrastructure.
#
# Public API:
#
#     stoleus_definition_initialize
#     stoleus_definition_build_all
#     stoleus_definition_get_records
#     stoleus_definition_reset
#     stoleus_definition_is_frozen
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_DEFINITION_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_DEFINITION_SUBSYSTEM_LOADED="true"


# ==============================================================================
# PluginDefinition State
# ==============================================================================
#
# All arrays use the same numerical index.
#
# Definitions become immutable after a successful build operation.
# ==============================================================================

declare -a STOLEUS_DEFINITION_IDS=()
declare -a STOLEUS_DEFINITION_CATEGORIES=()
declare -a STOLEUS_DEFINITION_DESCRIPTIONS=()
declare -a STOLEUS_DEFINITION_PLUGIN_PATHS=()
declare -a STOLEUS_DEFINITION_IMPLEMENTATIONS=()
declare -a STOLEUS_DEFINITION_DEPENDENCIES=()
declare -a STOLEUS_DEFINITION_CAPABILITIES=()
declare -a STOLEUS_DEFINITION_REQUIRED_SERVICES=()
declare -a STOLEUS_DEFINITION_PROVIDED_SERVICES=()
declare -a STOLEUS_DEFINITION_SERVICE_OPERATION_BINDINGS=()
declare -a STOLEUS_DEFINITION_SERVICE_CONDITIONS=()
declare -a STOLEUS_DEFINITION_MANIFEST_PATHS=()
declare -a STOLEUS_DEFINITION_MANIFEST_PROVIDERS=()

declare -a STOLEUS_DEFINITION_INSTALL_FUNCTIONS=()
declare -a STOLEUS_DEFINITION_CONFIGURE_FUNCTIONS=()
declare -a STOLEUS_DEFINITION_VERIFY_FUNCTIONS=()
declare -a STOLEUS_DEFINITION_UPGRADE_FUNCTIONS=()
declare -a STOLEUS_DEFINITION_REMOVE_FUNCTIONS=()


# ==============================================================================
# Manifest Provider Loading
# ==============================================================================

source "${STOLEUS_KERNEL_ROOT}/definition/providers/bash.sh"


# ==============================================================================
# stoleus_definition_is_frozen
# ==============================================================================
#
# Return codes:
#
#     0 = definitions are frozen
#     1 = definitions remain mutable
# ==============================================================================

stoleus_definition_is_frozen() {

    [[ "${STOLEUS_DEFINITIONS_FROZEN:-false}" == "true" ]]
}


# ==============================================================================
# stoleus_definition_reset
# ==============================================================================
#
# Purpose:
#     Remove all definitions and return the subsystem to a mutable state.
#
# This function is intended for:
#
#     - tests;
#     - development tooling;
#     - an explicit complete bootstrap restart.
#
# Production bootstrap should build and freeze definitions exactly once.
# ==============================================================================

stoleus_definition_reset() {

    STOLEUS_DEFINITION_IDS=()
    STOLEUS_DEFINITION_CATEGORIES=()
    STOLEUS_DEFINITION_DESCRIPTIONS=()
    STOLEUS_DEFINITION_PLUGIN_PATHS=()
    STOLEUS_DEFINITION_IMPLEMENTATIONS=()
    STOLEUS_DEFINITION_DEPENDENCIES=()
    STOLEUS_DEFINITION_CAPABILITIES=()
    STOLEUS_DEFINITION_REQUIRED_SERVICES=()
    STOLEUS_DEFINITION_PROVIDED_SERVICES=()
    STOLEUS_DEFINITION_SERVICE_OPERATION_BINDINGS=()
    STOLEUS_DEFINITION_SERVICE_CONDITIONS=()
    STOLEUS_DEFINITION_MANIFEST_PATHS=()
    STOLEUS_DEFINITION_MANIFEST_PROVIDERS=()

    STOLEUS_DEFINITION_INSTALL_FUNCTIONS=()
    STOLEUS_DEFINITION_CONFIGURE_FUNCTIONS=()
    STOLEUS_DEFINITION_VERIFY_FUNCTIONS=()
    STOLEUS_DEFINITION_UPGRADE_FUNCTIONS=()
    STOLEUS_DEFINITION_REMOVE_FUNCTIONS=()

    STOLEUS_DEFINITIONS_FROZEN="false"


    return 0
}


# ==============================================================================
# stoleus_definition_exists
# ==============================================================================
#
# Purpose:
#     Determine whether a PluginDefinition ID already exists.
#
# Arguments:
#
#     $1 = plugin ID
#
# Return codes:
#
#     0 = definition exists
#     1 = definition does not exist
#     2 = plugin ID was omitted
# ==============================================================================

stoleus_definition_exists() {

    local plugin_id="${1:-}"
    local existing_id=""


    if [[ -z "$plugin_id" ]]; then
        return 2
    fi


    for existing_id in "${STOLEUS_DEFINITION_IDS[@]}"; do

        if [[ "$existing_id" == "$plugin_id" ]]; then
            return 0
        fi
    done


    return 1
}


# ==============================================================================
# stoleus_definition_validate_function_reference
# ==============================================================================
#
# Purpose:
#     Validate a lifecycle function reference without loading the implementation.
#
# Arguments:
#
#     $1 = lifecycle stage
#     $2 = function reference
#
# Empty references are valid because every lifecycle stage is optional.
# ==============================================================================

stoleus_definition_validate_function_reference() {

    local lifecycle_stage="${1:-}"
    local function_reference="${2:-}"


    if [[ -z "$function_reference" ]]; then
        return 0
    fi


    if [[ ! "$function_reference" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid ${lifecycle_stage} lifecycle function reference: ${function_reference}" \
            >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_definition_register
# ==============================================================================
#
# Purpose:
#     Register one normalized PluginDefinition.
#
# Arguments:
#
#     $1  = plugin ID
#     $2  = category
#     $3  = description
#     $4  = absolute plugin directory
#     $5  = absolute implementation-file path
#     $6  = comma-separated plugin dependencies
#     $7  = comma-separated required capabilities
#     $8  = absolute manifest path
#     $9  = manifest provider ID
#     $10 = install function
#     $11 = configure function
#     $12 = verify function
#     $13 = upgrade function
#     $14 = remove function
#
# Definitions cannot be added after the collection is frozen.
# ==============================================================================

stoleus_definition_register() {

    local plugin_id="${1:-}"
    local category="${2:-}"
    local description="${3:-}"
    local plugin_path="${4:-}"
    local implementation_path="${5:-}"
    local dependencies="${6:-}"
    local capabilities="${7:-}"
    local manifest_path="${8:-}"
    local manifest_provider="${9:-}"

    local install_function="${10:-}"
    local configure_function="${11:-}"
    local verify_function="${12:-}"
    local upgrade_function="${13:-}"
    local remove_function="${14:-}"

    local required_services="${15:-}"
    local provided_services="${16:-}"
    local service_operation_bindings="${17:-}"
    local service_conditions="${18:-}"


    if stoleus_definition_is_frozen; then

        printf '%s\n' \
            "ERROR: PluginDefinitions are immutable after they are frozen." \
            >&2

        return 8
    fi


    if [[ -z "$plugin_id" ]]; then

        printf '%s\n' \
            "ERROR: PluginDefinition requires an ID." >&2

        return 2
    fi


    if [[ ! "$plugin_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid PluginDefinition ID: $plugin_id" >&2

        return 6
    fi


    if stoleus_definition_exists "$plugin_id"; then

        printf '%s\n' \
            "ERROR: Duplicate PluginDefinition ID: $plugin_id" >&2

        return 8
    fi


    if [[ -z "$category" ]]; then

        printf '%s\n' \
            "ERROR: PluginDefinition '${plugin_id}' requires a category." \
            >&2

        return 2
    fi


    if [[ -z "$description" ]]; then

        printf '%s\n' \
            "ERROR: PluginDefinition '${plugin_id}' requires a description." \
            >&2

        return 2
    fi


    if [[ -z "$plugin_path" || ! -d "$plugin_path" ]]; then

        printf '%s\n' \
            "ERROR: PluginDefinition '${plugin_id}' has an invalid plugin directory: ${plugin_path}" \
            >&2

        return 6
    fi


    if [[ -z "$implementation_path" || ! -f "$implementation_path" ]]; then

        printf '%s\n' \
            "ERROR: PluginDefinition '${plugin_id}' implementation file is missing: ${implementation_path}" \
            >&2

        return 6
    fi


    if [[ -z "$manifest_path" || ! -f "$manifest_path" ]]; then

        printf '%s\n' \
            "ERROR: PluginDefinition '${plugin_id}' manifest file is missing: ${manifest_path}" \
            >&2

        return 6
    fi


    if [[ -z "$manifest_provider" ]]; then

        printf '%s\n' \
            "ERROR: PluginDefinition '${plugin_id}' requires a manifest provider." \
            >&2

        return 6
    fi


    stoleus_definition_validate_function_reference \
        "install" \
        "$install_function" ||
        return $?


    stoleus_definition_validate_function_reference \
        "configure" \
        "$configure_function" ||
        return $?


    stoleus_definition_validate_function_reference \
        "verify" \
        "$verify_function" ||
        return $?


    stoleus_definition_validate_function_reference \
        "upgrade" \
        "$upgrade_function" ||
        return $?


    stoleus_definition_validate_function_reference \
        "remove" \
        "$remove_function" ||
        return $?


    if [[ -z "$install_function" &&
          -z "$configure_function" &&
          -z "$verify_function" &&
          -z "$upgrade_function" &&
          -z "$remove_function" ]]; then

        printf '%s\n' \
            "ERROR: PluginDefinition '${plugin_id}' must expose at least one lifecycle function." \
            >&2

        return 6
    fi


    STOLEUS_DEFINITION_IDS+=("$plugin_id")
    STOLEUS_DEFINITION_CATEGORIES+=("$category")
    STOLEUS_DEFINITION_DESCRIPTIONS+=("$description")
    STOLEUS_DEFINITION_PLUGIN_PATHS+=("$plugin_path")
    STOLEUS_DEFINITION_IMPLEMENTATIONS+=("$implementation_path")
    STOLEUS_DEFINITION_DEPENDENCIES+=("$dependencies")
    STOLEUS_DEFINITION_CAPABILITIES+=("$capabilities")

    STOLEUS_DEFINITION_REQUIRED_SERVICES+=("$required_services")
    STOLEUS_DEFINITION_PROVIDED_SERVICES+=("$provided_services")
    STOLEUS_DEFINITION_SERVICE_OPERATION_BINDINGS+=(
        "$service_operation_bindings"
    )
    STOLEUS_DEFINITION_SERVICE_CONDITIONS+=("$service_conditions")

    STOLEUS_DEFINITION_MANIFEST_PATHS+=("$manifest_path")
    STOLEUS_DEFINITION_MANIFEST_PROVIDERS+=("$manifest_provider")

    STOLEUS_DEFINITION_INSTALL_FUNCTIONS+=("$install_function")
    STOLEUS_DEFINITION_CONFIGURE_FUNCTIONS+=("$configure_function")
    STOLEUS_DEFINITION_VERIFY_FUNCTIONS+=("$verify_function")
    STOLEUS_DEFINITION_UPGRADE_FUNCTIONS+=("$upgrade_function")
    STOLEUS_DEFINITION_REMOVE_FUNCTIONS+=("$remove_function")


    return 0
}


# ==============================================================================
# stoleus_definition_select_manifest
# ==============================================================================
#
# Purpose:
#     Select the manifest and manifest provider for one DiscoveryRecord.
#
# Arguments:
#
#     $1 = semicolon-separated manifest candidates
#
# Output:
#
#     provider<TAB>manifest-path
#
# Current provider priority:
#
#     1. Bash DSL: manifest.sh
#
# YAML and JSON candidates may be discovered, but their providers are not yet
# implemented. The subsystem returns configuration code 6 when no supported
# provider can process the record.
# ==============================================================================

stoleus_definition_select_manifest() {

    local manifest_candidates="${1:-}"
    local candidate=""


    if [[ -z "$manifest_candidates" ]]; then

        printf '%s\n' \
            "ERROR: Plugin candidate does not contain a manifest." \
            >&2

        return 6
    fi


    while IFS= read -r candidate; do

        [[ -z "$candidate" ]] && continue


        case "${candidate##*/}" in

            manifest.sh)

                printf 'bash\t%s\n' "$candidate"

                return 0

                ;;
        esac

    done < <(
        printf '%s\n' "$manifest_candidates" |
            tr ';' '\n'
    )


    printf '%s\n' \
        "ERROR: No supported manifest provider was found for: ${manifest_candidates}" \
        >&2

    return 6
}


# ==============================================================================
# stoleus_definition_build_record
# ==============================================================================
#
# Purpose:
#     Convert one DiscoveryRecord into one PluginDefinition.
#
# Arguments:
#
#     $1 = category
#     $2 = discovered directory name
#     $3 = absolute plugin directory
#     $4 = semicolon-separated manifest candidates
# ==============================================================================

stoleus_definition_build_record() {

    local category="${1:-}"
    local discovered_name="${2:-}"
    local plugin_path="${3:-}"
    local manifest_candidates="${4:-}"

    local provider_selection=""
    local manifest_provider=""
    local manifest_path=""


    if [[ -z "$category" ||
          -z "$discovered_name" ||
          -z "$plugin_path" ]]; then

        printf '%s\n' \
            "ERROR: Invalid DiscoveryRecord supplied to the Definition subsystem." \
            >&2

        return 2
    fi


    provider_selection="$(
        stoleus_definition_select_manifest \
            "$manifest_candidates"
    )" || return $?


    IFS=$'\t' read -r \
        manifest_provider \
        manifest_path \
        <<< "$provider_selection"


    case "$manifest_provider" in

        bash)

            stoleus_manifest_bash_load \
                "$manifest_path" \
                "$category" \
                "$discovered_name" \
                "$plugin_path" ||
                return $?

            ;;


        *)

            printf '%s\n' \
                "ERROR: Unknown manifest provider selected: $manifest_provider" \
                >&2

            return 6

            ;;
    esac


    return 0
}


# ==============================================================================
# stoleus_definition_build_all
# ==============================================================================
#
# Purpose:
#     Convert every DiscoveryRecord into a PluginDefinition.
#
# Requirements:
#
#     - discovery must be initialized;
#     - discovery scan must be complete;
#     - definitions must not already be frozen.
#
# A successful build freezes the complete definition collection.
# ==============================================================================

stoleus_definition_build_all() {

    local index=0


    if [[ "${STOLEUS_DEFINITION_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Definition subsystem must be initialized before building definitions." \
            >&2

        return 6
    fi


    if [[ "${STOLEUS_DISCOVERY_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Discovery subsystem must be initialized before building definitions." \
            >&2

        return 6
    fi


    if ! stoleus_discovery_is_scanned; then

        printf '%s\n' \
            "ERROR: Discovery scan must complete before building definitions." \
            >&2

        return 6
    fi


    if stoleus_definition_is_frozen; then
        return 0
    fi


    stoleus_definition_reset || return $?


    for index in "${!STOLEUS_DISCOVERY_RECORD_PATHS[@]}"; do

        stoleus_definition_build_record \
            "${STOLEUS_DISCOVERY_RECORD_CATEGORIES[$index]}" \
            "${STOLEUS_DISCOVERY_RECORD_NAMES[$index]}" \
            "${STOLEUS_DISCOVERY_RECORD_PATHS[$index]}" \
            "${STOLEUS_DISCOVERY_RECORD_MANIFESTS[$index]}" ||
            return $?
    done


    STOLEUS_DEFINITIONS_FROZEN="true"

    return 0
}


# ==============================================================================
# stoleus_definition_get_records
# ==============================================================================
#
# Purpose:
#     Print normalized PluginDefinitions.
#
# Output format:
#
#     id
#     category
#     description
#     implementation
#     dependencies
#     capabilities
#     manifest provider
#     install
#     configure
#     verify
#     upgrade
#     remove
#
# Fields are separated by tabs.
# ==============================================================================

stoleus_definition_get_records() {

    local index=0


    for index in "${!STOLEUS_DEFINITION_IDS[@]}"; do

        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "${STOLEUS_DEFINITION_IDS[$index]}" \
            "${STOLEUS_DEFINITION_CATEGORIES[$index]}" \
            "${STOLEUS_DEFINITION_DESCRIPTIONS[$index]}" \
            "${STOLEUS_DEFINITION_IMPLEMENTATIONS[$index]}" \
            "${STOLEUS_DEFINITION_DEPENDENCIES[$index]}" \
            "${STOLEUS_DEFINITION_CAPABILITIES[$index]}" \
            "${STOLEUS_DEFINITION_MANIFEST_PROVIDERS[$index]}" \
            "${STOLEUS_DEFINITION_INSTALL_FUNCTIONS[$index]}" \
            "${STOLEUS_DEFINITION_CONFIGURE_FUNCTIONS[$index]}" \
            "${STOLEUS_DEFINITION_VERIFY_FUNCTIONS[$index]}" \
            "${STOLEUS_DEFINITION_UPGRADE_FUNCTIONS[$index]}" \
            "${STOLEUS_DEFINITION_REMOVE_FUNCTIONS[$index]}"
    done


    return 0
}


# ==============================================================================
# stoleus_definition_initialize
# ==============================================================================
#
# Purpose:
#     Initialize empty mutable PluginDefinition state.
#
# Initialization does not parse manifests or build definitions.
# ==============================================================================

stoleus_definition_initialize() {

    if [[ "${STOLEUS_DEFINITION_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_definition_reset || return $?


    STOLEUS_DEFINITION_INITIALIZED="true"

    return 0
}

#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Discovery Subsystem
# ==============================================================================
#
# Purpose:
#     Locate candidate plugin directories and represent them as normalized
#     discovery records.
#
# Discovery performs filesystem inspection only.
#
# It does not:
#
#     - source manifests;
#     - parse manifest contents;
#     - load plugin implementations;
#     - register plugin definitions;
#     - execute plugin behavior.
#
# Public API:
#
#     stoleus_discovery_initialize
#     stoleus_discovery_add_root
#     stoleus_discovery_scan
#     stoleus_discovery_get_records
#     stoleus_discovery_reset
#
# Discovery records contain:
#
#     category
#     plugin name
#     absolute plugin directory
#     available manifest candidates
#
# Record order is deterministic:
#
#     roots are scanned in registration order;
#     directories inside each root are sorted lexically.
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_DISCOVERY_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_DISCOVERY_SUBSYSTEM_LOADED="true"


# ==============================================================================
# Discovery Root State
# ==============================================================================

declare -a STOLEUS_DISCOVERY_ROOT_CATEGORIES=()
declare -a STOLEUS_DISCOVERY_ROOT_PATHS=()


# ==============================================================================
# Discovery Record State
# ==============================================================================

declare -a STOLEUS_DISCOVERY_RECORD_CATEGORIES=()
declare -a STOLEUS_DISCOVERY_RECORD_NAMES=()
declare -a STOLEUS_DISCOVERY_RECORD_PATHS=()
declare -a STOLEUS_DISCOVERY_RECORD_MANIFESTS=()


# ==============================================================================
# stoleus_discovery_is_scanned
# ==============================================================================
#
# Purpose:
#     Determine whether the current discovery configuration has already been
#     scanned.
#
# Return codes:
#
#     0 = scan completed
#     1 = scan not completed
# ==============================================================================
stoleus_discovery_is_scanned() {

    [[ "${STOLEUS_DISCOVERY_SCANNED:-false}" == "true" ]]
}


# ==============================================================================
# stoleus_discovery_add_root
# ==============================================================================
#
# Purpose:
#     Register one plugin discovery root.
#
# Arguments:
#
#     $1
#         Plugin category.
#
#         Examples:
#
#             modules
#             providers
#             commands
#             generators
#
#     $2
#         Plugin root directory.
#
# Rules:
#
#     - category must be a lowercase identifier;
#     - path is normalized to an absolute path;
#     - duplicate category/path registrations are ignored;
#     - roots cannot be changed after scanning.
# ==============================================================================
stoleus_discovery_add_root() {

    local category="${1:-}"
    local root_path="${2:-}"

    local normalized_root=""
    local index=0


    if [[ -z "$category" ]]; then
        printf '%s\n' \
            "ERROR: Discovery root category is required." >&2

        return 2
    fi


    if [[ ! "$category" =~ ^[a-z][a-z0-9-]*$ ]]; then
        printf '%s\n' \
            "ERROR: Invalid discovery root category: $category" >&2

        return 6
    fi


    if [[ -z "$root_path" ]]; then
        printf '%s\n' \
            "ERROR: Discovery root path is required for category: $category" >&2

        return 2
    fi


    if stoleus_discovery_is_scanned; then
        printf '%s\n' \
            "ERROR: Discovery roots cannot be changed after scanning." >&2

        return 8
    fi


    if [[ "$root_path" == /* ]]; then
        normalized_root="$root_path"
    else
        normalized_root="${PROJECT_ROOT}/${root_path}"
    fi


    # --------------------------------------------------------------------------
    # Remove a trailing slash, except for the filesystem root itself.
    # --------------------------------------------------------------------------
    if [[ "$normalized_root" != "/" ]]; then
        normalized_root="${normalized_root%/}"
    fi


    # --------------------------------------------------------------------------
    # Duplicate registrations are idempotent.
    # --------------------------------------------------------------------------
    for index in "${!STOLEUS_DISCOVERY_ROOT_PATHS[@]}"; do

        if [[ "${STOLEUS_DISCOVERY_ROOT_CATEGORIES[$index]}" == "$category" ]] &&
           [[ "${STOLEUS_DISCOVERY_ROOT_PATHS[$index]}" == "$normalized_root" ]]; then

            return 0
        fi
    done


    STOLEUS_DISCOVERY_ROOT_CATEGORIES+=("$category")
    STOLEUS_DISCOVERY_ROOT_PATHS+=("$normalized_root")


    return 0
}


# ==============================================================================
# stoleus_discovery_reset
# ==============================================================================
#
# Purpose:
#     Remove all discovery records and allow the configured roots to be scanned
#     again.
#
# Registered roots are preserved.
#
# This is intended for:
#
#     - tests;
#     - development tooling;
#     - explicit refresh operations.
# ==============================================================================
stoleus_discovery_reset() {

    STOLEUS_DISCOVERY_RECORD_CATEGORIES=()
    STOLEUS_DISCOVERY_RECORD_NAMES=()
    STOLEUS_DISCOVERY_RECORD_PATHS=()
    STOLEUS_DISCOVERY_RECORD_MANIFESTS=()

    STOLEUS_DISCOVERY_SCANNED="false"


    return 0
}


# ==============================================================================
# stoleus_discovery_find_manifests
# ==============================================================================
#
# Purpose:
#     Find supported manifest files inside one candidate plugin directory.
#
# Arguments:
#
#     $1 = absolute plugin directory
#
# Supported candidates:
#
#     manifest.sh
#     manifest.yaml
#     manifest.yml
#     manifest.json
#
# Output:
#
#     Existing manifest paths joined by a semicolon.
#
# This function does not select a provider or parse any manifest.
# ==============================================================================
stoleus_discovery_find_manifests() {

    local plugin_path="${1:-}"

    local candidate=""
    local result=""

    local -a manifest_names=(
        "manifest.sh"
        "manifest.yaml"
        "manifest.yml"
        "manifest.json"
    )


    if [[ -z "$plugin_path" ]]; then
        printf '%s\n' \
            "ERROR: Plugin path is required for manifest discovery." >&2

        return 2
    fi


    for candidate in "${manifest_names[@]}"; do

        if [[ -f "${plugin_path}/${candidate}" ]]; then

            if [[ -n "$result" ]]; then
                result+=";"
            fi

            result+="${plugin_path}/${candidate}"
        fi
    done


    printf '%s' "$result"

    return 0
}


# ==============================================================================
# stoleus_discovery_record_exists
# ==============================================================================
#
# Purpose:
#     Determine whether a category/path pair is already recorded.
#
# Arguments:
#
#     $1 = category
#     $2 = absolute plugin directory
# ==============================================================================
stoleus_discovery_record_exists() {

    local category="${1:-}"
    local plugin_path="${2:-}"

    local index=0


    for index in "${!STOLEUS_DISCOVERY_RECORD_PATHS[@]}"; do

        if [[ "${STOLEUS_DISCOVERY_RECORD_CATEGORIES[$index]}" == "$category" ]] &&
           [[ "${STOLEUS_DISCOVERY_RECORD_PATHS[$index]}" == "$plugin_path" ]]; then

            return 0
        fi
    done


    return 1
}


# ==============================================================================
# stoleus_discovery_scan_root
# ==============================================================================
#
# Purpose:
#     Scan one registered root and append normalized discovery records.
#
# Arguments:
#
#     $1 = category
#     $2 = absolute discovery root
#
# Missing roots are valid and produce no records. This allows optional plugin
# categories and externally configured plugin roots.
# ==============================================================================
stoleus_discovery_scan_root() {

    local category="${1:-}"
    local root_path="${2:-}"

    local plugin_path=""
    local plugin_name=""
    local manifests=""


    if [[ -z "$category" || -z "$root_path" ]]; then
        printf '%s\n' \
            "ERROR: Category and root path are required when scanning a discovery root." \
            >&2

        return 2
    fi


    if [[ ! -d "$root_path" ]]; then
        return 0
    fi


    while IFS= read -r plugin_path; do

        [[ -z "$plugin_path" ]] && continue


        plugin_name="${plugin_path##*/}"


        # ----------------------------------------------------------------------
        # Hidden directories are framework metadata, not plugins.
        # ----------------------------------------------------------------------
        if [[ "$plugin_name" == .* ]]; then
            continue
        fi


        if stoleus_discovery_record_exists "$category" "$plugin_path"; then
            continue
        fi


        manifests="$(
            stoleus_discovery_find_manifests "$plugin_path"
        )" || return $?


        STOLEUS_DISCOVERY_RECORD_CATEGORIES+=("$category")
        STOLEUS_DISCOVERY_RECORD_NAMES+=("$plugin_name")
        STOLEUS_DISCOVERY_RECORD_PATHS+=("$plugin_path")
        STOLEUS_DISCOVERY_RECORD_MANIFESTS+=("$manifests")

    done < <(
        find "$root_path" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -print |
            LC_ALL=C sort
    )


    return 0
}


# ==============================================================================
# stoleus_discovery_scan
# ==============================================================================
#
# Purpose:
#     Scan every configured plugin root and create discovery records.
#
# Scanning is idempotent. A completed scan is not repeated unless
# stoleus_discovery_reset() is called first.
# ==============================================================================
stoleus_discovery_scan() {

    local index=0
    local category=""
    local root_path=""


    if [[ "${STOLEUS_DISCOVERY_INITIALIZED:-false}" != "true" ]]; then
        printf '%s\n' \
            "ERROR: Discovery must be initialized before scanning." >&2

        return 6
    fi


    if stoleus_discovery_is_scanned; then
        return 0
    fi


    for index in "${!STOLEUS_DISCOVERY_ROOT_PATHS[@]}"; do

        category="${STOLEUS_DISCOVERY_ROOT_CATEGORIES[$index]}"
        root_path="${STOLEUS_DISCOVERY_ROOT_PATHS[$index]}"


        stoleus_discovery_scan_root \
            "$category" \
            "$root_path" ||
            return $?
    done


    STOLEUS_DISCOVERY_SCANNED="true"

    return 0
}


# ==============================================================================
# stoleus_discovery_get_records
# ==============================================================================
#
# Purpose:
#     Print all discovery records.
#
# Output format:
#
#     category<TAB>name<TAB>absolute-path<TAB>manifest-candidates
#
# This stable tab-separated representation is intended for:
#
#     - diagnostics;
#     - tests;
#     - future manifest-provider selection;
#     - future registry construction.
# ==============================================================================
stoleus_discovery_get_records() {

    local index=0


    for index in "${!STOLEUS_DISCOVERY_RECORD_PATHS[@]}"; do

        printf '%s\t%s\t%s\t%s\n' \
            "${STOLEUS_DISCOVERY_RECORD_CATEGORIES[$index]}" \
            "${STOLEUS_DISCOVERY_RECORD_NAMES[$index]}" \
            "${STOLEUS_DISCOVERY_RECORD_PATHS[$index]}" \
            "${STOLEUS_DISCOVERY_RECORD_MANIFESTS[$index]}"
    done


    return 0
}


# ==============================================================================
# stoleus_discovery_initialize
# ==============================================================================
#
# Purpose:
#     Initialize discovery state and register the standard plugin roots.
#
# Standard roots:
#
#     plugins/modules
#     plugins/providers
#     plugins/commands
#     plugins/generators
#
# Initialization does not scan the filesystem.
# ==============================================================================
stoleus_discovery_initialize() {

    if [[ "${STOLEUS_DISCOVERY_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    STOLEUS_DISCOVERY_ROOT_CATEGORIES=()
    STOLEUS_DISCOVERY_ROOT_PATHS=()

    stoleus_discovery_reset || return $?


    stoleus_discovery_add_root \
        "modules" \
        "${PROJECT_ROOT}/plugins/modules" ||
        return $?


    stoleus_discovery_add_root \
        "providers" \
        "${PROJECT_ROOT}/plugins/providers" ||
        return $?


    stoleus_discovery_add_root \
        "commands" \
        "${PROJECT_ROOT}/plugins/commands" ||
        return $?


    stoleus_discovery_add_root \
        "generators" \
        "${PROJECT_ROOT}/plugins/generators" ||
        return $?


    STOLEUS_DISCOVERY_INITIALIZED="true"

    return 0
}

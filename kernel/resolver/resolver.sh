#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Resolver Subsystem
# ==============================================================================
#
# Purpose:
#     Resolve plugin and dependency references against the immutable Registry.
#
# Processing boundary:
#
#     Registry metadata
#         ↓
#     Resolver
#         ↓
#     Resolved plugin references
#
# The Resolver answers questions such as:
#
#     - Does this plugin exist?
#     - What Registry index identifies it?
#     - Which plugins does it directly depend on?
#     - Are all dependency references valid?
#
# The Resolver does not:
#
#     - discover plugins;
#     - parse manifests;
#     - modify Registry metadata;
#     - recursively order dependencies;
#     - detect dependency cycles;
#     - build execution plans;
#     - load plugin implementations;
#     - execute lifecycle functions.
#
# Public API:
#
#     stoleus_resolver_initialize
#     stoleus_resolver_resolve
#     stoleus_resolver_resolve_index
#     stoleus_resolver_resolve_dependencies
#     stoleus_resolver_validate_plugin
#     stoleus_resolver_validate_registry
#     stoleus_resolver_get_resolved
#     stoleus_resolver_reset
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_RESOLVER_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_RESOLVER_SUBSYSTEM_LOADED="true"


# ==============================================================================
# Resolved Reference State
# ==============================================================================
#
# A resolved reference contains:
#
#     requested plugin ID
#     Registry index
#     plugin category
#
# The Resolver cache is derived state. It can be rebuilt from the immutable
# Registry at any time.
# ==============================================================================

declare -a STOLEUS_RESOLVER_RESOLVED_IDS=()
declare -a STOLEUS_RESOLVER_RESOLVED_INDEXES=()
declare -a STOLEUS_RESOLVER_RESOLVED_CATEGORIES=()

declare -A STOLEUS_RESOLVER_INDEX_BY_ID=()


# ==============================================================================
# stoleus_resolver_reset
# ==============================================================================
#
# Purpose:
#     Clear all derived Resolver state.
#
# Registry data is not modified.
# ==============================================================================

stoleus_resolver_reset() {

    STOLEUS_RESOLVER_RESOLVED_IDS=()
    STOLEUS_RESOLVER_RESOLVED_INDEXES=()
    STOLEUS_RESOLVER_RESOLVED_CATEGORIES=()

    STOLEUS_RESOLVER_INDEX_BY_ID=()

    STOLEUS_RESOLVER_VALIDATED="false"


    return 0
}


# ==============================================================================
# stoleus_resolver_require_registry
# ==============================================================================
#
# Purpose:
#     Verify that Registry metadata is ready for resolution.
#
# Resolution is allowed only after the Registry has been frozen.
# ==============================================================================

stoleus_resolver_require_registry() {

    if [[ "${STOLEUS_REGISTRY_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Registry must be initialized before plugin resolution." \
            >&2

        return 6
    fi


    if ! stoleus_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Registry must be frozen before plugin resolution." \
            >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_resolver_cache_reference
# ==============================================================================
#
# Purpose:
#     Cache one successfully resolved Registry reference.
#
# Arguments:
#
#     $1 = plugin ID
#     $2 = Registry index
#
# Repeated caching of the same plugin is idempotent.
# ==============================================================================

stoleus_resolver_cache_reference() {

    local plugin_id="${1:-}"
    local registry_index="${2:-}"

    local category=""
    local resolved_position=0


    if [[ -z "$plugin_id" ||
          -z "$registry_index" ||
          ! "$registry_index" =~ ^[0-9]+$ ]]; then

        printf '%s\n' \
            "ERROR: Resolver cache requires plugin ID and numeric Registry index." \
            >&2

        return 2
    fi


    if [[ -n "${STOLEUS_RESOLVER_INDEX_BY_ID[$plugin_id]+resolved}" ]]; then
        return 0
    fi


    category="${STOLEUS_REGISTRY_CATEGORIES[$registry_index]:-}"


    if [[ -z "$category" ]]; then

        printf '%s\n' \
            "ERROR: Resolver found incomplete Registry metadata for plugin: $plugin_id" \
            >&2

        return 6
    fi


    resolved_position="${#STOLEUS_RESOLVER_RESOLVED_IDS[@]}"

    STOLEUS_RESOLVER_RESOLVED_IDS+=("$plugin_id")
    STOLEUS_RESOLVER_RESOLVED_INDEXES+=("$registry_index")
    STOLEUS_RESOLVER_RESOLVED_CATEGORIES+=("$category")

    STOLEUS_RESOLVER_INDEX_BY_ID["$plugin_id"]="$resolved_position"


    return 0
}


# ==============================================================================
# stoleus_resolver_resolve_index
# ==============================================================================
#
# Purpose:
#     Resolve a plugin ID to its Registry index.
#
# Arguments:
#
#     $1 = plugin ID
#
# Output:
#
#     Numeric Registry index followed by a newline.
#
# Return codes:
#
#     0 = resolved
#     2 = plugin ID omitted
#     6 = Registry unavailable or plugin unknown
# ==============================================================================

stoleus_resolver_resolve_index() {

    local plugin_id="${1:-}"
    local registry_index=""


    if [[ -z "$plugin_id" ]]; then

        printf '%s\n' \
            "ERROR: Plugin resolution requires a plugin ID." >&2

        return 2
    fi


    stoleus_resolver_require_registry || return $?


    registry_index="$(
        stoleus_registry_get_index "$plugin_id"
    )" || return $?


    stoleus_resolver_cache_reference \
        "$plugin_id" \
        "$registry_index" ||
        return $?


    printf '%s\n' "$registry_index"

    return 0
}


# ==============================================================================
# stoleus_resolver_resolve
# ==============================================================================
#
# Purpose:
#     Resolve one plugin and print its normalized reference.
#
# Arguments:
#
#     $1 = plugin ID
#
# Output format:
#
#     plugin-id<TAB>registry-index<TAB>category
# ==============================================================================

stoleus_resolver_resolve() {

    local plugin_id="${1:-}"
    local registry_index=""
    local category=""


    registry_index="$(
        stoleus_resolver_resolve_index "$plugin_id"
    )" || return $?


    category="${STOLEUS_REGISTRY_CATEGORIES[$registry_index]}"


    printf '%s\t%s\t%s\n' \
        "$plugin_id" \
        "$registry_index" \
        "$category"

    return 0
}


# ==============================================================================
# stoleus_resolver_parse_reference_list
# ==============================================================================
#
# Purpose:
#     Normalize a comma-separated Registry reference list.
#
# Arguments:
#
#     $1 = comma-separated references
#
# Output:
#
#     One trimmed non-empty reference per line.
# ==============================================================================

stoleus_resolver_parse_reference_list() {

    local reference_list="${1:-}"
    local reference=""


    if [[ -z "$reference_list" ]]; then
        return 0
    fi


    while IFS= read -r reference; do

        reference="$(
            printf '%s' "$reference" |
                sed -E \
                    's/^[[:space:]]+//; s/[[:space:]]+$//'
        )"


        if [[ -n "$reference" ]]; then
            printf '%s\n' "$reference"
        fi

    done < <(
        printf '%s\n' "$reference_list" |
            tr ',' '\n'
    )


    return 0
}


# ==============================================================================
# stoleus_resolver_resolve_dependencies
# ==============================================================================
#
# Purpose:
#     Resolve all direct dependencies declared by one plugin.
#
# Arguments:
#
#     $1 = plugin ID
#
# Output format:
#
#     dependency-id<TAB>registry-index<TAB>category
#
# Important:
#
#     This function resolves direct dependencies only.
#
#     It does not recursively traverse the graph or determine execution order.
#     Recursive traversal belongs to Planning.
# ==============================================================================

stoleus_resolver_resolve_dependencies() {

    local plugin_id="${1:-}"
    local registry_index=""
    local dependency_list=""
    local dependency_id=""


    registry_index="$(
        stoleus_resolver_resolve_index "$plugin_id"
    )" || return $?


    dependency_list="${STOLEUS_REGISTRY_DEPENDENCIES[$registry_index]}"


    while IFS= read -r dependency_id; do

        [[ -z "$dependency_id" ]] && continue


        stoleus_resolver_resolve \
            "$dependency_id" ||
            return $?

    done < <(
        stoleus_resolver_parse_reference_list \
            "$dependency_list"
    )


    return 0
}


# ==============================================================================
# stoleus_resolver_validate_plugin
# ==============================================================================
#
# Purpose:
#     Validate all direct references declared by one plugin.
#
# Arguments:
#
#     $1 = plugin ID
#
# Validation:
#
#     - plugin exists;
#     - plugin does not directly depend on itself;
#     - every direct dependency exists;
#     - duplicate direct dependencies are rejected.
#
# Cycle detection across multiple plugins belongs to Planning.
# ==============================================================================

stoleus_resolver_validate_plugin() {

    local plugin_id="${1:-}"
    local registry_index=""
    local dependency_list=""
    local dependency_id=""
    local dependency_index=""

    local -A seen_dependencies=()


    # --------------------------------------------------------------------------
    # A plugin ID is required.
    # --------------------------------------------------------------------------
    if [[ -z "$plugin_id" ]]; then

        printf '%s\n' \
            "ERROR: Plugin validation requires a plugin ID." >&2

        return 2
    fi


    # --------------------------------------------------------------------------
    # Registry metadata must already be complete and immutable.
    # --------------------------------------------------------------------------
    stoleus_resolver_require_registry || return $?


    # --------------------------------------------------------------------------
    # Resolve the requested plugin directly through the Registry.
    #
    # We deliberately do not call a state-changing resolver function inside
    # command substitution. Bash executes command substitution in a subshell,
    # and mutations to Resolver cache arrays would otherwise be discarded.
    # --------------------------------------------------------------------------
    registry_index="$(
        stoleus_registry_get_index "$plugin_id"
    )" || return $?


    # --------------------------------------------------------------------------
    # Cache the requested plugin explicitly in the current shell process.
    # --------------------------------------------------------------------------
    stoleus_resolver_cache_reference \
        "$plugin_id" \
        "$registry_index" ||
        return $?


    dependency_list="${STOLEUS_REGISTRY_DEPENDENCIES[$registry_index]}"


    # --------------------------------------------------------------------------
    # Validate and resolve every direct dependency.
    #
    # Recursive traversal and multi-plugin cycle detection remain Planning
    # responsibilities.
    # --------------------------------------------------------------------------
    while IFS= read -r dependency_id; do

        [[ -z "$dependency_id" ]] && continue


        # ----------------------------------------------------------------------
        # A plugin cannot directly depend on itself.
        # ----------------------------------------------------------------------
        if [[ "$dependency_id" == "$plugin_id" ]]; then

            printf '%s\n' \
                "ERROR: Plugin '${plugin_id}' cannot depend directly on itself." \
                >&2

            return 8
        fi


        # ----------------------------------------------------------------------
        # Duplicate direct dependencies indicate invalid manifest metadata.
        # ----------------------------------------------------------------------
        if [[ -n "${seen_dependencies[$dependency_id]+seen}" ]]; then

            printf '%s\n' \
                "ERROR: Plugin '${plugin_id}' declares duplicate dependency: ${dependency_id}" \
                >&2

            return 8
        fi


        seen_dependencies["$dependency_id"]="true"


        # ----------------------------------------------------------------------
        # Resolve the dependency through the immutable Registry.
        # ----------------------------------------------------------------------
        dependency_index="$(
            stoleus_registry_get_index "$dependency_id"
        )" || return $?


        # ----------------------------------------------------------------------
        # Cache the resolved dependency in the current shell process.
        # ----------------------------------------------------------------------
        stoleus_resolver_cache_reference \
            "$dependency_id" \
            "$dependency_index" ||
            return $?

    done < <(
        stoleus_resolver_parse_reference_list \
            "$dependency_list"
    )


    return 0
}


# ==============================================================================
# stoleus_resolver_validate_registry
# ==============================================================================
#
# Purpose:
#     Validate direct plugin references for the complete Registry.
#
# A successful validation does not freeze or modify Registry metadata.
#
# This operation may be repeated safely.
# ==============================================================================

stoleus_resolver_validate_registry() {

    local plugin_id=""


    stoleus_resolver_require_registry || return $?


    for plugin_id in "${STOLEUS_REGISTRY_IDS[@]}"; do

        stoleus_resolver_validate_plugin \
            "$plugin_id" ||
            return $?
    done


    STOLEUS_RESOLVER_VALIDATED="true"

    return 0
}


# ==============================================================================
# stoleus_resolver_get_resolved
# ==============================================================================
#
# Purpose:
#     Print references resolved during the current process.
#
# Output format:
#
#     plugin-id<TAB>registry-index<TAB>category
#
# Records are printed in first-resolution order.
# ==============================================================================

stoleus_resolver_get_resolved() {

    local resolved_position=0


    for resolved_position in "${!STOLEUS_RESOLVER_RESOLVED_IDS[@]}"; do

        printf '%s\t%s\t%s\n' \
            "${STOLEUS_RESOLVER_RESOLVED_IDS[$resolved_position]}" \
            "${STOLEUS_RESOLVER_RESOLVED_INDEXES[$resolved_position]}" \
            "${STOLEUS_RESOLVER_RESOLVED_CATEGORIES[$resolved_position]}"
    done


    return 0
}


# ==============================================================================
# stoleus_resolver_initialize
# ==============================================================================
#
# Purpose:
#     Initialize empty derived Resolver state.
#
# Initialization does not require a populated Registry.
# ==============================================================================

stoleus_resolver_initialize() {

    if [[ "${STOLEUS_RESOLVER_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_resolver_reset || return $?


    STOLEUS_RESOLVER_INITIALIZED="true"

    return 0
}

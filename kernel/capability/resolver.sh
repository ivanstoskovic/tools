#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Capability Resolver
# ==============================================================================
#
# Purpose:
#     Resolve required capabilities to concrete provider plugins.
#
# Selection rules:
#
#     - zero providers return configuration code 6;
#     - exactly one provider is selected;
#     - multiple providers return conflict code 8.
#
# Public API:
#
#     stoleus_capability_resolver_initialize
#     stoleus_capability_resolver_resolve
#     stoleus_capability_resolver_get_provider
#     stoleus_capability_resolver_validate_plugin
#     stoleus_capability_resolver_validate_registry
#     stoleus_capability_resolver_get_resolved
#     stoleus_capability_resolver_is_resolved
#     stoleus_capability_resolver_reset
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_CAPABILITY_RESOLVER_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi

STOLEUS_CAPABILITY_RESOLVER_SUBSYSTEM_LOADED="true"


# ==============================================================================
# Resolver State
# ==============================================================================

declare -a STOLEUS_CAPABILITY_RESOLVER_CAPABILITY_IDS=()
declare -a STOLEUS_CAPABILITY_RESOLVER_PROVIDER_PLUGIN_IDS=()

declare -A STOLEUS_CAPABILITY_RESOLVER_INDEX_BY_CAPABILITY=()


# ==============================================================================
# stoleus_capability_resolver_reset
# ==============================================================================

stoleus_capability_resolver_reset() {

    STOLEUS_CAPABILITY_RESOLVER_CAPABILITY_IDS=()
    STOLEUS_CAPABILITY_RESOLVER_PROVIDER_PLUGIN_IDS=()

    STOLEUS_CAPABILITY_RESOLVER_INDEX_BY_CAPABILITY=()

    STOLEUS_CAPABILITY_RESOLVER_VALIDATED="false"

    return 0
}


# ==============================================================================
# stoleus_capability_resolver_require_registry
# ==============================================================================

stoleus_capability_resolver_require_registry() {

    if [[ "${STOLEUS_CAPABILITY_RESOLVER_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Capability Resolver must be initialized before use." \
            >&2

        return 6
    fi


    if ! stoleus_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Capability resolution requires a frozen Plugin Registry." \
            >&2

        return 6
    fi


    if ! stoleus_capability_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Capability resolution requires a frozen Capability Registry." \
            >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_capability_resolver_is_resolved
# ==============================================================================

stoleus_capability_resolver_is_resolved() {

    local capability_id="${1:-}"


    if [[ -z "$capability_id" ]]; then
        return 2
    fi


    [[ -n "${STOLEUS_CAPABILITY_RESOLVER_INDEX_BY_CAPABILITY[$capability_id]+resolved}" ]]
}


# ==============================================================================
# stoleus_capability_resolver_cache
# ==============================================================================

stoleus_capability_resolver_cache() {

    local capability_id="${1:-}"
    local provider_plugin_id="${2:-}"

    local resolved_index=0


    if [[ -z "$capability_id" ||
          -z "$provider_plugin_id" ]]; then

        printf '%s\n' \
            "ERROR: Capability Resolver cache requires capability and provider IDs." \
            >&2

        return 2
    fi


    if stoleus_capability_resolver_is_resolved "$capability_id"; then
        return 0
    fi


    resolved_index="${#STOLEUS_CAPABILITY_RESOLVER_CAPABILITY_IDS[@]}"

    STOLEUS_CAPABILITY_RESOLVER_CAPABILITY_IDS+=("$capability_id")
    STOLEUS_CAPABILITY_RESOLVER_PROVIDER_PLUGIN_IDS+=("$provider_plugin_id")

    STOLEUS_CAPABILITY_RESOLVER_INDEX_BY_CAPABILITY["$capability_id"]="$resolved_index"


    return 0
}


# ==============================================================================
# stoleus_capability_resolver_resolve
# ==============================================================================

stoleus_capability_resolver_resolve() {

    local capability_id="${1:-}"

    local provider_plugin_id=""
    local selected_provider=""
    local override_provider=""

    local -a candidate_providers=()


    if [[ -z "$capability_id" ]]; then

        printf '%s\n' \
            "ERROR: Capability resolution requires a capability ID." \
            >&2

        return 2
    fi


    stoleus_capability_registry_validate_id \
        "$capability_id" ||
        return $?


    stoleus_capability_resolver_require_registry || return $?


    if [[ "${STOLEUS_CAPABILITY_POLICY_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Capability Policy must be initialized before capability resolution." \
            >&2

        return 6
    fi


    if stoleus_capability_resolver_is_resolved "$capability_id"; then

        selected_provider="$(
            stoleus_capability_resolver_get_provider \
                "$capability_id"
        )" || return $?


        printf '%s\t%s\n' \
            "$capability_id" \
            "$selected_provider"

        return 0
    fi


    # --------------------------------------------------------------------------
    # Collect provider facts from the Capability Registry.
    #
    # Selection itself belongs to Capability Policy.
    # --------------------------------------------------------------------------
    while IFS= read -r provider_plugin_id; do

        [[ -z "$provider_plugin_id" ]] && continue


        candidate_providers+=(
            "$provider_plugin_id"
        )

    done < <(
        stoleus_capability_registry_list_providers \
            "$capability_id"
    )


    override_provider="$(
        stoleus_context_get_capability_provider_override \
            "$capability_id"
    )" || return $?


    stoleus_capability_policy_select \
        "$capability_id" \
        "$override_provider" \
        "${candidate_providers[@]}" \
        >/dev/null ||
        return $?


    selected_provider="$(
        stoleus_provider_selection_get_selected
    )" || return $?


    stoleus_capability_resolver_cache \
        "$capability_id" \
        "$selected_provider" ||
        return $?


    printf '%s\t%s\n' \
        "$capability_id" \
        "$selected_provider"

    return 0
}


# ==============================================================================
# stoleus_capability_resolver_get_provider
# ==============================================================================

stoleus_capability_resolver_get_provider() {

    local capability_id="${1:-}"
    local resolved_index=""


    if [[ -z "$capability_id" ]]; then

        printf '%s\n' \
            "ERROR: Capability provider lookup requires a capability ID." \
            >&2

        return 2
    fi


    if ! stoleus_capability_resolver_is_resolved "$capability_id"; then

        stoleus_capability_resolver_resolve \
            "$capability_id" \
            >/dev/null ||
            return $?
    fi


    resolved_index="${STOLEUS_CAPABILITY_RESOLVER_INDEX_BY_CAPABILITY[$capability_id]}"


    printf '%s\n' \
        "${STOLEUS_CAPABILITY_RESOLVER_PROVIDER_PLUGIN_IDS[$resolved_index]}"

    return 0
}


# ==============================================================================
# stoleus_capability_resolver_validate_plugin
# ==============================================================================

stoleus_capability_resolver_validate_plugin() {

    local plugin_id="${1:-}"

    local required_capabilities=""
    local capability_id=""

    local -A seen_capabilities=()


    if [[ -z "$plugin_id" ]]; then

        printf '%s\n' \
            "ERROR: Capability requirement validation requires a plugin ID." \
            >&2

        return 2
    fi


    if ! stoleus_registry_contains "$plugin_id"; then

        printf '%s\n' \
            "ERROR: Capability validation references an unknown plugin: ${plugin_id}" \
            >&2

        return 6
    fi


    required_capabilities="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "capabilities"
    )" || return $?


    while IFS= read -r capability_id; do

        [[ -z "$capability_id" ]] && continue


        if [[ -n "${seen_capabilities[$capability_id]+declared}" ]]; then

            printf '%s\n' \
                "ERROR: Plugin '${plugin_id}' declares duplicate required capability: ${capability_id}" \
                >&2

            return 8
        fi


        seen_capabilities["$capability_id"]="true"


        stoleus_capability_resolver_resolve \
            "$capability_id" \
            >/dev/null ||
            return $?

    done < <(
        printf '%s\n' "$required_capabilities" |
            tr ',' '\n'
    )


    return 0
}


# ==============================================================================
# stoleus_capability_resolver_validate_registry
# ==============================================================================

stoleus_capability_resolver_validate_registry() {

    local plugin_id=""


    stoleus_capability_resolver_require_registry || return $?


    while IFS= read -r plugin_id; do

        [[ -z "$plugin_id" ]] && continue


        stoleus_capability_resolver_validate_plugin \
            "$plugin_id" ||
            return $?

    done < <(
        stoleus_registry_list_ids
    )


    STOLEUS_CAPABILITY_RESOLVER_VALIDATED="true"

    return 0
}


# ==============================================================================
# stoleus_capability_resolver_get_resolved
# ==============================================================================

stoleus_capability_resolver_get_resolved() {

    local resolved_index=0


    for resolved_index in \
        "${!STOLEUS_CAPABILITY_RESOLVER_CAPABILITY_IDS[@]}"; do

        printf '%s\t%s\n' \
            "${STOLEUS_CAPABILITY_RESOLVER_CAPABILITY_IDS[$resolved_index]}" \
            "${STOLEUS_CAPABILITY_RESOLVER_PROVIDER_PLUGIN_IDS[$resolved_index]}"
    done


    return 0
}


# ==============================================================================
# stoleus_capability_resolver_initialize
# ==============================================================================

stoleus_capability_resolver_initialize() {

    if [[ "${STOLEUS_CAPABILITY_RESOLVER_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_capability_resolver_reset || return $?


    STOLEUS_CAPABILITY_RESOLVER_INITIALIZED="true"

    return 0
}

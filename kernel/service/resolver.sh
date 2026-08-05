#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Service Provider Resolver
# ==============================================================================
#
# Purpose:
#     Select one deterministic provider for each requested service contract.
#
# Resolution flow:
#
#     service contract
#         ↓
#     Service Registry provider candidates
#         ↓
#     priority comparison
#         ↓
#     unique highest-priority provider
#         ↓
#     cached service binding
#
# Selection rules:
#
#     - the requested contract must exist;
#     - at least one provider must exist;
#     - the highest numeric priority wins;
#     - a tie at the highest priority is a conflict;
#     - successful selections are cached by service ID.
#
# This subsystem does not:
#
#     - load provider implementations;
#     - invoke service operations;
#     - evaluate operating-system context;
#     - support conditional providers yet.
#
# Public API:
#
#     stoleus_service_resolver_initialize
#     stoleus_service_resolver_resolve
#     stoleus_service_resolver_get_provider
#     stoleus_service_resolver_get_operation_binding
#     stoleus_service_resolver_validate_registry
#     stoleus_service_resolver_get_resolved
#     stoleus_service_resolver_is_resolved
#     stoleus_service_resolver_reset
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_SERVICE_RESOLVER_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_SERVICE_RESOLVER_SUBSYSTEM_LOADED="true"


# ==============================================================================
# Resolved Provider State
# ==============================================================================

declare -a STOLEUS_SERVICE_RESOLVER_SERVICE_IDS=()
declare -a STOLEUS_SERVICE_RESOLVER_PROVIDER_PLUGIN_IDS=()
declare -a STOLEUS_SERVICE_RESOLVER_PROVIDER_KEYS=()
declare -a STOLEUS_SERVICE_RESOLVER_CONTRACT_VERSIONS=()
declare -a STOLEUS_SERVICE_RESOLVER_PRIORITIES=()

declare -A STOLEUS_SERVICE_RESOLVER_INDEX_BY_SERVICE=()


# ==============================================================================
# stoleus_service_resolver_reset
# ==============================================================================

stoleus_service_resolver_reset() {

    STOLEUS_SERVICE_RESOLVER_SERVICE_IDS=()
    STOLEUS_SERVICE_RESOLVER_PROVIDER_PLUGIN_IDS=()
    STOLEUS_SERVICE_RESOLVER_PROVIDER_KEYS=()
    STOLEUS_SERVICE_RESOLVER_CONTRACT_VERSIONS=()
    STOLEUS_SERVICE_RESOLVER_PRIORITIES=()

    STOLEUS_SERVICE_RESOLVER_INDEX_BY_SERVICE=()

    STOLEUS_SERVICE_RESOLVER_VALIDATED="false"
    STOLEUS_SERVICE_RESOLVER_CONTEXT_GENERATION="${STOLEUS_CONTEXT_GENERATION:-0}"


    return 0
}


# ==============================================================================
# stoleus_service_resolver_require_registries
# ==============================================================================

stoleus_service_resolver_require_registries() {

    if [[ "${STOLEUS_SERVICE_RESOLVER_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Service Provider Resolver must be initialized before use." \
            >&2

        return 6
    fi


    if ! stoleus_contract_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Service resolution requires a frozen Contract Registry." \
            >&2

        return 6
    fi


    if ! stoleus_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Service resolution requires a frozen Plugin Registry." \
            >&2

        return 6
    fi


    if ! stoleus_service_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Service resolution requires a frozen Service Registry." \
            >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_service_resolver_is_resolved
# ==============================================================================

stoleus_service_resolver_is_resolved() {

    local service_id="${1:-}"


    if [[ -z "$service_id" ]]; then
        return 2
    fi


    [[ -n "${STOLEUS_SERVICE_RESOLVER_INDEX_BY_SERVICE[$service_id]+resolved}" ]]
}


# ==============================================================================
# stoleus_service_resolver_cache
# ==============================================================================

stoleus_service_resolver_cache() {

    local service_id="${1:-}"
    local provider_plugin_id="${2:-}"
    local contract_version="${3:-}"
    local priority="${4:-}"

    local provider_key=""
    local resolved_index=0


    if [[ -z "$service_id" ||
          -z "$provider_plugin_id" ||
          -z "$contract_version" ||
          -z "$priority" ]]; then

        printf '%s\n' \
            "ERROR: Service resolver cache received incomplete provider metadata." \
            >&2

        return 2
    fi


    if stoleus_service_resolver_is_resolved "$service_id"; then
        return 0
    fi


    provider_key="${service_id}@${provider_plugin_id}"
    resolved_index="${#STOLEUS_SERVICE_RESOLVER_SERVICE_IDS[@]}"


    STOLEUS_SERVICE_RESOLVER_SERVICE_IDS+=("$service_id")
    STOLEUS_SERVICE_RESOLVER_PROVIDER_PLUGIN_IDS+=("$provider_plugin_id")
    STOLEUS_SERVICE_RESOLVER_PROVIDER_KEYS+=("$provider_key")
    STOLEUS_SERVICE_RESOLVER_CONTRACT_VERSIONS+=("$contract_version")
    STOLEUS_SERVICE_RESOLVER_PRIORITIES+=("$priority")

    STOLEUS_SERVICE_RESOLVER_INDEX_BY_SERVICE["$service_id"]="$resolved_index"


    return 0
}


# ==============================================================================
# stoleus_service_resolver_sync_context
# ==============================================================================
#
# Purpose:
#     Invalidate cached provider selections whenever runtime context or explicit
#     provider overrides change.
# ==============================================================================

stoleus_service_resolver_sync_context() {

    local current_generation="${STOLEUS_CONTEXT_GENERATION:-0}"


    if [[ "${STOLEUS_SERVICE_RESOLVER_CONTEXT_GENERATION:-0}" == "$current_generation" ]]; then
        return 0
    fi


    STOLEUS_SERVICE_RESOLVER_SERVICE_IDS=()
    STOLEUS_SERVICE_RESOLVER_PROVIDER_PLUGIN_IDS=()
    STOLEUS_SERVICE_RESOLVER_PROVIDER_KEYS=()
    STOLEUS_SERVICE_RESOLVER_CONTRACT_VERSIONS=()
    STOLEUS_SERVICE_RESOLVER_PRIORITIES=()
    STOLEUS_SERVICE_RESOLVER_INDEX_BY_SERVICE=()

    STOLEUS_SERVICE_RESOLVER_VALIDATED="false"
    STOLEUS_SERVICE_RESOLVER_CONTEXT_GENERATION="$current_generation"


    return 0
}


# ==============================================================================
# stoleus_service_resolver_candidate_matches_context
# ==============================================================================

stoleus_service_resolver_candidate_matches_context() {

    local service_id="${1:-}"
    local provider_plugin_id="${2:-}"

    local conditions=""


    conditions="$(
        stoleus_service_registry_get_field \
            "${service_id}@${provider_plugin_id}" \
            "conditions"
    )" || return $?


    stoleus_context_matches_conditions "$conditions"

    return $?
}


# ==============================================================================
# stoleus_service_resolver_resolve
# ==============================================================================
#
# Purpose:
#     Select and cache the unique highest-priority provider for one service.
#
# Arguments:
#
#     $1 = service/contract ID
#
# Output:
#
#     service-id<TAB>provider-plugin-id<TAB>version<TAB>priority
#
# Return codes:
#
#     0 = provider resolved
#     2 = invalid input
#     6 = unknown contract or no provider
#     8 = highest-priority provider tie
# ==============================================================================

stoleus_service_resolver_resolve() {

    local service_id="${1:-}"

    local provider_plugin_id=""
    local contract_version=""
    local priority=""

    local selected_provider=""
    local selected_version=""
    local selected_priority=-1

    local tied_provider=""
    local candidate_count=0
    local matching_candidate_count=0

    local override_provider=""
    local override_provider_key=""


    if [[ -z "$service_id" ]]; then

        printf '%s\n' \
            "ERROR: Service resolution requires a service ID." >&2

        return 2
    fi


    stoleus_service_resolver_require_registries || return $?
    stoleus_service_resolver_sync_context || return $?


    if ! stoleus_contract_registry_contains "$service_id"; then

        printf '%s\n' \
            "ERROR: Cannot resolve unknown service contract: ${service_id}" \
            >&2

        return 6
    fi


    if stoleus_service_resolver_is_resolved "$service_id"; then

        stoleus_service_resolver_get_provider "$service_id"

        return $?
    fi


    override_provider="$(
        stoleus_context_get_provider_override "$service_id"
    )" || return $?


    if [[ -n "$override_provider" ]]; then

        override_provider_key="${service_id}@${override_provider}"


        if ! stoleus_service_registry_contains "$override_provider_key"; then

            printf '%s\n' \
                "ERROR: Provider override references an unregistered provider: ${override_provider_key}" \
                >&2

            return 6
        fi


        if ! stoleus_service_resolver_candidate_matches_context \
            "$service_id" \
            "$override_provider"; then

            printf '%s\n' \
                "ERROR: Provider override '${override_provider}' does not match runtime context for service '${service_id}'." \
                >&2

            return 6
        fi


        contract_version="$(
            stoleus_service_registry_get_field \
                "$override_provider_key" \
                "contract-version"
        )" || return $?


        priority="$(
            stoleus_service_registry_get_field \
                "$override_provider_key" \
                "priority"
        )" || return $?


        stoleus_service_resolver_cache \
            "$service_id" \
            "$override_provider" \
            "$contract_version" \
            "$priority" ||
            return $?


        printf '%s\t%s\t%s\t%s\n' \
            "$service_id" \
            "$override_provider" \
            "$contract_version" \
            "$priority"

        return 0
    fi


    while IFS=$'\t' read -r \
        provider_plugin_id \
        contract_version \
        priority; do

        [[ -z "$provider_plugin_id" ]] && continue


        candidate_count="$((candidate_count + 1))"


        if [[ ! "$priority" =~ ^[0-9]+$ ]]; then

            printf '%s\n' \
                "ERROR: Provider '${provider_plugin_id}' has invalid priority for service '${service_id}': ${priority}" \
                >&2

            return 6
        fi


        if stoleus_service_resolver_candidate_matches_context \
            "$service_id" \
            "$provider_plugin_id"; then

            matching_candidate_count="$((matching_candidate_count + 1))"

        else
            match_exit_code=$?

            if (( match_exit_code == 1 )); then
                continue
            fi

            return "$match_exit_code"
        fi


        if (( priority > selected_priority )); then

            selected_provider="$provider_plugin_id"
            selected_version="$contract_version"
            selected_priority="$priority"
            tied_provider=""

            continue
        fi


        if (( priority == selected_priority )); then
            tied_provider="$provider_plugin_id"
        fi

    done < <(
        stoleus_service_registry_list_providers \
            "$service_id"
    )


    if (( candidate_count == 0 )); then

        printf '%s\n' \
            "ERROR: No provider is registered for service: ${service_id}" \
            >&2

        return 6
    fi


    if (( matching_candidate_count == 0 )); then

        printf '%s\n' \
            "ERROR: No registered provider matches runtime context for service: ${service_id}" \
            >&2

        return 6
    fi


    if [[ -n "$tied_provider" ]]; then

        printf '%s\n' \
            "ERROR: Service '${service_id}' has multiple context-compatible providers with highest priority ${selected_priority}: ${selected_provider}, ${tied_provider}" \
            >&2

        return 8
    fi


    stoleus_service_resolver_cache \
        "$service_id" \
        "$selected_provider" \
        "$selected_version" \
        "$selected_priority" ||
        return $?


    printf '%s\t%s\t%s\t%s\n' \
        "$service_id" \
        "$selected_provider" \
        "$selected_version" \
        "$selected_priority"

    return 0
}


# ==============================================================================
# stoleus_service_resolver_get_provider
# ==============================================================================
#
# Output:
#
#     service-id<TAB>provider-plugin-id<TAB>version<TAB>priority
# ==============================================================================

stoleus_service_resolver_get_provider() {

    local service_id="${1:-}"

    local resolved_index=""


    if [[ -z "$service_id" ]]; then

        printf '%s\n' \
            "ERROR: Resolved provider lookup requires a service ID." >&2

        return 2
    fi


    if ! stoleus_service_resolver_is_resolved "$service_id"; then

        stoleus_service_resolver_resolve "$service_id"

        return $?
    fi


    resolved_index="${STOLEUS_SERVICE_RESOLVER_INDEX_BY_SERVICE[$service_id]}"


    printf '%s\t%s\t%s\t%s\n' \
        "${STOLEUS_SERVICE_RESOLVER_SERVICE_IDS[$resolved_index]}" \
        "${STOLEUS_SERVICE_RESOLVER_PROVIDER_PLUGIN_IDS[$resolved_index]}" \
        "${STOLEUS_SERVICE_RESOLVER_CONTRACT_VERSIONS[$resolved_index]}" \
        "${STOLEUS_SERVICE_RESOLVER_PRIORITIES[$resolved_index]}"

    return 0
}


# ==============================================================================
# stoleus_service_resolver_get_provider_plugin
# ==============================================================================
#
# Purpose:
#     Return only the selected provider plugin ID.
# ==============================================================================

stoleus_service_resolver_get_provider_plugin() {

    local service_id="${1:-}"
    local resolved_index=""


    if [[ -z "$service_id" ]]; then
        return 2
    fi


    if ! stoleus_service_resolver_is_resolved "$service_id"; then

        stoleus_service_resolver_resolve \
            "$service_id" \
            >/dev/null ||
            return $?
    fi


    resolved_index="${STOLEUS_SERVICE_RESOLVER_INDEX_BY_SERVICE[$service_id]}"


    printf '%s\n' \
        "${STOLEUS_SERVICE_RESOLVER_PROVIDER_PLUGIN_IDS[$resolved_index]}"

    return 0
}


# ==============================================================================
# stoleus_service_resolver_get_operation_binding
# ==============================================================================
#
# Purpose:
#     Resolve the provider and return its function binding for one operation.
#
# Arguments:
#
#     $1 = service ID
#     $2 = operation ID
# ==============================================================================

stoleus_service_resolver_get_operation_binding() {

    local service_id="${1:-}"
    local operation_id="${2:-}"

    local provider_plugin_id=""


    if [[ -z "$service_id" || -z "$operation_id" ]]; then

        printf '%s\n' \
            "ERROR: Resolved operation lookup requires service ID and operation ID." \
            >&2

        return 2
    fi


    provider_plugin_id="$(
        stoleus_service_resolver_get_provider_plugin \
            "$service_id"
    )" || return $?


    stoleus_service_registry_get_operation_binding \
        "$service_id" \
        "$provider_plugin_id" \
        "$operation_id"

    return $?
}


# ==============================================================================
# stoleus_service_resolver_validate_plugin_requirements
# ==============================================================================

stoleus_service_resolver_validate_plugin_requirements() {

    local plugin_id="${1:-}"
    local required_services=""
    local service_id=""


    if [[ -z "$plugin_id" ]]; then

        printf '%s\n' \
            "ERROR: Service requirement validation requires a plugin ID." \
            >&2

        return 2
    fi


    required_services="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "required-services"
    )" || return $?


    while IFS= read -r service_id; do

        [[ -z "$service_id" ]] && continue


        stoleus_service_resolver_resolve \
            "$service_id" \
            >/dev/null ||
            return $?

    done < <(
        printf '%s\n' "$required_services" |
            tr ',' '\n'
    )


    return 0
}


# ==============================================================================
# stoleus_service_resolver_validate_registry
# ==============================================================================
#
# Purpose:
#     Resolve every service required by every registered plugin.
#
# Plugins without service requirements are valid.
# ==============================================================================

stoleus_service_resolver_validate_registry() {

    local plugin_id=""


    stoleus_service_resolver_require_registries || return $?


    while IFS= read -r plugin_id; do

        [[ -z "$plugin_id" ]] && continue


        stoleus_service_resolver_validate_plugin_requirements \
            "$plugin_id" ||
            return $?

    done < <(
        stoleus_registry_list_ids
    )


    STOLEUS_SERVICE_RESOLVER_VALIDATED="true"

    return 0
}


# ==============================================================================
# stoleus_service_resolver_get_resolved
# ==============================================================================
#
# Output:
#
#     service-id<TAB>provider-plugin-id<TAB>version<TAB>priority
# ==============================================================================

stoleus_service_resolver_get_resolved() {

    local resolved_index=0


    for resolved_index in "${!STOLEUS_SERVICE_RESOLVER_SERVICE_IDS[@]}"; do

        printf '%s\t%s\t%s\t%s\n' \
            "${STOLEUS_SERVICE_RESOLVER_SERVICE_IDS[$resolved_index]}" \
            "${STOLEUS_SERVICE_RESOLVER_PROVIDER_PLUGIN_IDS[$resolved_index]}" \
            "${STOLEUS_SERVICE_RESOLVER_CONTRACT_VERSIONS[$resolved_index]}" \
            "${STOLEUS_SERVICE_RESOLVER_PRIORITIES[$resolved_index]}"
    done


    return 0
}


# ==============================================================================
# stoleus_service_resolver_initialize
# ==============================================================================

stoleus_service_resolver_initialize() {

    if [[ "${STOLEUS_SERVICE_RESOLVER_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_service_resolver_reset || return $?


    STOLEUS_SERVICE_RESOLVER_INITIALIZED="true"

    return 0
}

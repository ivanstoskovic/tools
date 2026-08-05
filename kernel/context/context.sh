#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Runtime Context
# ==============================================================================
#
# Purpose:
#     Store runtime facts and explicit service-provider overrides used during
#     provider resolution.
#
# Examples:
#
#     stoleus_context_set "os-family" "debian"
#     stoleus_context_set "distribution" "ubuntu"
#     stoleus_context_set "architecture" "x86_64"
#
#     stoleus_context_set_provider_override \
#         "package-manager" \
#         "apt-provider"
#
# Every mutation increments STOLEUS_CONTEXT_GENERATION. Stateful consumers use
# this generation to invalidate caches when context changes.
#
# Public API:
#
#     stoleus_context_initialize
#     stoleus_context_set
#     stoleus_context_get
#     stoleus_context_contains
#     stoleus_context_list
#     stoleus_context_matches_conditions
#     stoleus_context_set_provider_override
#     stoleus_context_get_provider_override
#     stoleus_context_clear_provider_override
#     stoleus_context_list_provider_overrides
#     stoleus_context_get_generation
#     stoleus_context_reset
# ==============================================================================

set -Eeuo pipefail


if [[ "${STOLEUS_CONTEXT_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_CONTEXT_SUBSYSTEM_LOADED="true"


declare -a STOLEUS_CONTEXT_KEYS=()
declare -a STOLEUS_CONTEXT_VALUES=()
declare -A STOLEUS_CONTEXT_INDEX_BY_KEY=()

declare -A STOLEUS_CONTEXT_PROVIDER_OVERRIDES=()

STOLEUS_CONTEXT_GENERATION=0


# ==============================================================================
# stoleus_context_validate_key
# ==============================================================================

stoleus_context_validate_key() {

    local context_key="${1:-}"


    if [[ -z "$context_key" ]]; then

        printf '%s\n' \
            "ERROR: Context key is required." >&2

        return 2
    fi


    if [[ ! "$context_key" =~ ^[a-z][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid context key: ${context_key}" >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_context_increment_generation
# ==============================================================================

stoleus_context_increment_generation() {

    STOLEUS_CONTEXT_GENERATION="$((STOLEUS_CONTEXT_GENERATION + 1))"

    return 0
}


# ==============================================================================
# stoleus_context_reset
# ==============================================================================

stoleus_context_reset() {

    STOLEUS_CONTEXT_KEYS=()
    STOLEUS_CONTEXT_VALUES=()
    STOLEUS_CONTEXT_INDEX_BY_KEY=()

    STOLEUS_CONTEXT_PROVIDER_OVERRIDES=()

    stoleus_context_increment_generation || return $?


    return 0
}


# ==============================================================================
# stoleus_context_contains
# ==============================================================================

stoleus_context_contains() {

    local context_key="${1:-}"


    if [[ -z "$context_key" ]]; then
        return 2
    fi


    [[ -n "${STOLEUS_CONTEXT_INDEX_BY_KEY[$context_key]+stored}" ]]
}


# ==============================================================================
# stoleus_context_set
# ==============================================================================

stoleus_context_set() {

    local context_key="${1:-}"
    local context_value="${2:-}"

    local context_index=0


    stoleus_context_validate_key "$context_key" || return $?


    if [[ -z "$context_value" ]]; then

        printf '%s\n' \
            "ERROR: Context value cannot be empty for key '${context_key}'." \
            >&2

        return 2
    fi


    if [[ "$context_value" == *$'\n'* ||
          "$context_value" == *';'* ||
          "$context_value" == *'|'* ]]; then

        printf '%s\n' \
            "ERROR: Context value contains unsupported delimiters for key '${context_key}'." \
            >&2

        return 6
    fi


    if stoleus_context_contains "$context_key"; then

        context_index="${STOLEUS_CONTEXT_INDEX_BY_KEY[$context_key]}"


        if [[ "${STOLEUS_CONTEXT_VALUES[$context_index]}" == "$context_value" ]]; then
            return 0
        fi


        STOLEUS_CONTEXT_VALUES[$context_index]="$context_value"

        stoleus_context_increment_generation || return $?

        return 0
    fi


    context_index="${#STOLEUS_CONTEXT_KEYS[@]}"

    STOLEUS_CONTEXT_KEYS+=("$context_key")
    STOLEUS_CONTEXT_VALUES+=("$context_value")
    STOLEUS_CONTEXT_INDEX_BY_KEY["$context_key"]="$context_index"

    stoleus_context_increment_generation || return $?


    return 0
}


# ==============================================================================
# stoleus_context_get
# ==============================================================================

stoleus_context_get() {

    local context_key="${1:-}"
    local context_index=""


    stoleus_context_validate_key "$context_key" || return $?


    if ! stoleus_context_contains "$context_key"; then

        printf '%s\n' \
            "ERROR: Unknown runtime context key: ${context_key}" >&2

        return 6
    fi


    context_index="${STOLEUS_CONTEXT_INDEX_BY_KEY[$context_key]}"

    printf '%s\n' \
        "${STOLEUS_CONTEXT_VALUES[$context_index]}"

    return 0
}


# ==============================================================================
# stoleus_context_list
# ==============================================================================

stoleus_context_list() {

    local context_index=0


    for context_index in "${!STOLEUS_CONTEXT_KEYS[@]}"; do

        printf '%s\t%s\n' \
            "${STOLEUS_CONTEXT_KEYS[$context_index]}" \
            "${STOLEUS_CONTEXT_VALUES[$context_index]}"
    done


    return 0
}


# ==============================================================================
# stoleus_context_matches_conditions
# ==============================================================================
#
# Arguments:
#
#     $1 = semicolon-separated key=value conditions
#
# Return codes:
#
#     0 = every condition matches
#     1 = at least one condition does not match
#     6 = malformed condition metadata
#
# An empty condition list matches every runtime context.
# ==============================================================================

stoleus_context_matches_conditions() {

    local conditions="${1:-}"

    local condition=""
    local context_key=""
    local expected_value=""
    local actual_value=""


    if [[ -z "$conditions" ]]; then
        return 0
    fi


    while IFS= read -r condition; do

        [[ -z "$condition" ]] && continue


        IFS='=' read -r \
            context_key \
            expected_value \
            <<< "$condition"


        if [[ -z "$context_key" || -z "$expected_value" ]]; then

            printf '%s\n' \
                "ERROR: Malformed provider condition: ${condition}" >&2

            return 6
        fi


        stoleus_context_validate_key "$context_key" || return $?


        if ! stoleus_context_contains "$context_key"; then
            return 1
        fi


        actual_value="$(
            stoleus_context_get "$context_key"
        )" || return $?


        if [[ "$actual_value" != "$expected_value" ]]; then
            return 1
        fi

    done < <(
        printf '%s\n' "$conditions" |
            tr ';' '\n'
    )


    return 0
}


# ==============================================================================
# stoleus_context_set_provider_override
# ==============================================================================

stoleus_context_set_provider_override() {

    local service_id="${1:-}"
    local provider_plugin_id="${2:-}"


    if [[ -z "$service_id" || -z "$provider_plugin_id" ]]; then

        printf '%s\n' \
            "ERROR: Provider override requires service ID and provider plugin ID." \
            >&2

        return 2
    fi


    if [[ ! "$service_id" =~ ^[a-z0-9][a-z0-9-]*$ ||
          ! "$provider_plugin_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Provider override contains an invalid identifier." >&2

        return 6
    fi


    if [[ "${STOLEUS_CONTEXT_PROVIDER_OVERRIDES[$service_id]:-}" == "$provider_plugin_id" ]]; then
        return 0
    fi


    STOLEUS_CONTEXT_PROVIDER_OVERRIDES["$service_id"]="$provider_plugin_id"

    stoleus_context_increment_generation || return $?


    return 0
}


# ==============================================================================
# stoleus_context_get_provider_override
# ==============================================================================

stoleus_context_get_provider_override() {

    local service_id="${1:-}"


    if [[ -z "$service_id" ]]; then
        return 2
    fi


    printf '%s\n' \
        "${STOLEUS_CONTEXT_PROVIDER_OVERRIDES[$service_id]:-}"

    return 0
}


# ==============================================================================
# stoleus_context_clear_provider_override
# ==============================================================================

stoleus_context_clear_provider_override() {

    local service_id="${1:-}"


    if [[ -z "$service_id" ]]; then
        return 2
    fi


    if [[ -z "${STOLEUS_CONTEXT_PROVIDER_OVERRIDES[$service_id]+stored}" ]]; then
        return 0
    fi


    unset 'STOLEUS_CONTEXT_PROVIDER_OVERRIDES[$service_id]'

    stoleus_context_increment_generation || return $?


    return 0
}


# ==============================================================================
# stoleus_context_list_provider_overrides
# ==============================================================================

stoleus_context_list_provider_overrides() {

    local service_id=""


    for service_id in "${!STOLEUS_CONTEXT_PROVIDER_OVERRIDES[@]}"; do

        printf '%s\t%s\n' \
            "$service_id" \
            "${STOLEUS_CONTEXT_PROVIDER_OVERRIDES[$service_id]}"
    done


    return 0
}


# ==============================================================================
# stoleus_context_get_generation
# ==============================================================================

stoleus_context_get_generation() {

    printf '%s\n' "$STOLEUS_CONTEXT_GENERATION"

    return 0
}


# ==============================================================================
# stoleus_context_initialize
# ==============================================================================

stoleus_context_initialize() {

    if [[ "${STOLEUS_CONTEXT_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    STOLEUS_CONTEXT_KEYS=()
    STOLEUS_CONTEXT_VALUES=()
    STOLEUS_CONTEXT_INDEX_BY_KEY=()
    STOLEUS_CONTEXT_PROVIDER_OVERRIDES=()
    STOLEUS_CONTEXT_GENERATION=0


    STOLEUS_CONTEXT_INITIALIZED="true"

    return 0
}

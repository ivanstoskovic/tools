#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Service Composition
# ==============================================================================
#
# Purpose:
#     Own runtime service-composition state.
#
# This first phase intentionally contains no composition algorithm.
#
# Responsibilities introduced later:
#
#     - resolve service and capability dependency graphs;
#     - cache resolved compositions;
#     - invalidate compositions when runtime Context changes;
#     - expose structured composition diagnostics.
#
# Internal API:
#
#     stoleus_composition_initialize
#     stoleus_composition_reset
#     stoleus_composition_is_initialized
#     stoleus_composition_get_count
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_COMPOSITION_LOADED:-false}" == "true" ]]; then
    return 0
fi

STOLEUS_COMPOSITION_LOADED="true"


# ==============================================================================
# State
# ==============================================================================

STOLEUS_COMPOSITION_INITIALIZED="false"
STOLEUS_COMPOSITION_CONTEXT_GENERATION="0"
STOLEUS_COMPOSITION_SELECTED_PROVIDER=""

declare -a STOLEUS_COMPOSITION_SUBJECT_TYPES=()
declare -a STOLEUS_COMPOSITION_SUBJECT_IDS=()
declare -a STOLEUS_COMPOSITION_PROVIDER_IDS=()
declare -a STOLEUS_COMPOSITION_CONTEXT_GENERATIONS=()
declare -a STOLEUS_COMPOSITION_STATUSES=()

declare -A STOLEUS_COMPOSITION_INDEX_BY_SUBJECT=()

declare -A STOLEUS_COMPOSITION_VISITING=()
declare -A STOLEUS_COMPOSITION_RESOLVED=()

declare -a STOLEUS_COMPOSITION_TRAVERSAL_STACK=()


# ==============================================================================
# stoleus_composition_reset
# ==============================================================================

stoleus_composition_reset() {

    STOLEUS_COMPOSITION_SUBJECT_TYPES=()
    STOLEUS_COMPOSITION_SUBJECT_IDS=()
    STOLEUS_COMPOSITION_PROVIDER_IDS=()
    STOLEUS_COMPOSITION_CONTEXT_GENERATIONS=()
    STOLEUS_COMPOSITION_STATUSES=()

    STOLEUS_COMPOSITION_INDEX_BY_SUBJECT=()

    STOLEUS_COMPOSITION_VISITING=()
    STOLEUS_COMPOSITION_RESOLVED=()
    STOLEUS_COMPOSITION_TRAVERSAL_STACK=()

    STOLEUS_COMPOSITION_SELECTED_PROVIDER=""

    STOLEUS_COMPOSITION_CONTEXT_GENERATION="${STOLEUS_CONTEXT_GENERATION:-0}"


    return 0
}


# ==============================================================================
# stoleus_composition_is_initialized
# ==============================================================================

stoleus_composition_is_initialized() {

    [[ "${STOLEUS_COMPOSITION_INITIALIZED:-false}" == "true" ]]
}


# ==============================================================================
# stoleus_composition_sync_context
# ==============================================================================
#
# Purpose:
#     Invalidate cached compositions when runtime Context changes.
# ==============================================================================

stoleus_composition_sync_context() {

    local current_generation="${STOLEUS_CONTEXT_GENERATION:-0}"


    if [[ "${STOLEUS_COMPOSITION_CONTEXT_GENERATION:-0}" == "$current_generation" ]]; then
        return 0
    fi


    STOLEUS_COMPOSITION_SUBJECT_TYPES=()
    STOLEUS_COMPOSITION_SUBJECT_IDS=()
    STOLEUS_COMPOSITION_PROVIDER_IDS=()
    STOLEUS_COMPOSITION_CONTEXT_GENERATIONS=()
    STOLEUS_COMPOSITION_STATUSES=()

    STOLEUS_COMPOSITION_INDEX_BY_SUBJECT=()

    STOLEUS_COMPOSITION_CONTEXT_GENERATION="$current_generation"


    return 0
}


# ==============================================================================
# stoleus_composition_resolve_provider
# ==============================================================================
#
# Purpose:
#     Resolve one typed Composition subject to the provider plugin whose
#     requirements must be traversed.
#
# Arguments:
#
#     $1 = plugin | service | capability
#     $2 = subject ID
#
# Output:
#
#     provider-plugin-id
#
# This function is stateful because Service/Capability resolution may populate
# resolver caches. Call it directly when state preservation matters.
# ==============================================================================

stoleus_composition_resolve_provider() {

    local subject_type="${1:-}"
    local subject_id="${2:-}"

    local provider_id=""


    if [[ -z "$subject_id" ||
          ! "$subject_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Composition provider resolution requires a valid subject ID." \
            >&2

        return 2
    fi


    case "$subject_type" in

        plugin)

            if ! stoleus_registry_contains "$subject_id"; then

                printf '%s\n' \
                    "ERROR: Composition references unknown plugin: ${subject_id}" \
                    >&2

                return 6
            fi


            provider_id="$subject_id"
            ;;


        service)

            if ! stoleus_service_resolver_is_resolved "$subject_id"; then

                stoleus_service_resolver_resolve \
                    "$subject_id" \
                    >/dev/null ||
                    return $?
            fi


            provider_id="$(
                stoleus_service_resolver_get_provider_plugin \
                    "$subject_id"
            )" || return $?
            ;;


        capability)

            if ! stoleus_capability_resolver_is_resolved "$subject_id"; then

                stoleus_capability_resolver_resolve \
                    "$subject_id" \
                    >/dev/null ||
                    return $?
            fi


            provider_id="$(
                stoleus_capability_resolver_get_provider \
                    "$subject_id"
            )" || return $?
            ;;


        *)

            printf '%s\n' \
                "ERROR: Unsupported Composition subject type: ${subject_type}" \
                >&2

            return 6
            ;;
    esac


    STOLEUS_COMPOSITION_SELECTED_PROVIDER="$provider_id"

    printf '%s\n' "$provider_id"

    return 0
}


# ==============================================================================
# stoleus_composition_list_provider_requirements
# ==============================================================================
#
# Purpose:
#     List the direct requirements declared by a provider plugin.
#
# Output:
#
#     type<TAB>id
#
# Types:
#
#     plugin
#     service
#     capability
#
# Notes:
#
#     Registry field `capabilities` is the legacy storage field for required
#     capabilities. `provided-capabilities` is intentionally not consumed here.
# ==============================================================================

stoleus_composition_list_provider_requirements() {

    local plugin_id="${1:-}"

    local dependencies=""
    local required_services=""
    local required_capabilities=""

    local requirement_id=""


    if [[ -z "$plugin_id" ||
          ! "$plugin_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Composition requires a valid provider plugin ID." >&2

        return 2
    fi


    if ! stoleus_registry_contains "$plugin_id"; then

        printf '%s\n' \
            "ERROR: Composition provider plugin is not registered: ${plugin_id}" \
            >&2

        return 6
    fi


    dependencies="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "dependencies"
    )" || return $?


    required_services="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "required-services"
    )" || return $?


    required_capabilities="$(
        stoleus_registry_get_field \
            "$plugin_id" \
            "capabilities"
    )" || return $?


    while IFS= read -r requirement_id; do

        [[ -z "$requirement_id" ]] && continue

        printf 'plugin\t%s\n' \
            "$requirement_id"

    done < <(
        stoleus_resolver_parse_reference_list \
            "$dependencies"
    )


    while IFS= read -r requirement_id; do

        [[ -z "$requirement_id" ]] && continue

        printf 'service\t%s\n' \
            "$requirement_id"

    done < <(
        stoleus_resolver_parse_reference_list \
            "$required_services"
    )


    while IFS= read -r requirement_id; do

        [[ -z "$requirement_id" ]] && continue

        printf 'capability\t%s\n' \
            "$requirement_id"

    done < <(
        stoleus_resolver_parse_reference_list \
            "$required_capabilities"
    )


    return 0
}


# ==============================================================================
# stoleus_composition_format_cycle
# ==============================================================================
#
# Arguments:
#
#     $1 = repeated typed subject key
#
# Output:
#
#     subject -> subject -> ... -> repeated-subject
# ==============================================================================

stoleus_composition_format_cycle() {

    local repeated_subject="${1:-}"
    local subject_key=""
    local include="false"
    local result=""


    if [[ -z "$repeated_subject" ]]; then
        return 2
    fi


    for subject_key in "${STOLEUS_COMPOSITION_TRAVERSAL_STACK[@]}"; do

        if [[ "$subject_key" == "$repeated_subject" ]]; then
            include="true"
        fi


        if [[ "$include" == "true" ]]; then

            if [[ -n "$result" ]]; then
                result+=" -> "
            fi

            result+="$subject_key"
        fi
    done


    if [[ -n "$result" ]]; then
        result+=" -> ${repeated_subject}"
    else
        result="$repeated_subject"
    fi


    printf '%s' "$result"

    return 0
}


# ==============================================================================
# stoleus_composition_leave_subject
# ==============================================================================
#
# Purpose:
#     Remove the current subject from active traversal state.
#
# This helper is used on both successful and failed traversal paths.
# ==============================================================================

stoleus_composition_leave_subject() {

    local subject_key="${1:-}"
    local last_index=0


    if [[ -z "$subject_key" ]]; then
        return 2
    fi


    unset 'STOLEUS_COMPOSITION_VISITING[$subject_key]'


    if (( ${#STOLEUS_COMPOSITION_TRAVERSAL_STACK[@]} > 0 )); then

        last_index="$((${#STOLEUS_COMPOSITION_TRAVERSAL_STACK[@]} - 1))"

        if [[ "${STOLEUS_COMPOSITION_TRAVERSAL_STACK[$last_index]}" == "$subject_key" ]]; then

            unset 'STOLEUS_COMPOSITION_TRAVERSAL_STACK[$last_index]'
        fi
    fi


    return 0
}


# ==============================================================================
# stoleus_composition_resolve_subject
# ==============================================================================
#
# Purpose:
#     Recursively compose one plugin/service/capability subject and all direct
#     requirements declared by its selected provider plugin.
#
# The provider is cached as a Composition record after all of its dependencies
# are successfully composed.
# ==============================================================================

stoleus_composition_resolve_subject() {

    local subject_type="${1:-}"
    local subject_id="${2:-}"

    local subject_key=""
    local provider_id=""
    local cycle_path=""

    local requirement_type=""
    local requirement_id=""

    local exit_code=0


    stoleus_composition_sync_context || return $?


    subject_key="$(
        stoleus_composition_get_key \
            "$subject_type" \
            "$subject_id"
    )" || return $?


    if [[ -n "${STOLEUS_COMPOSITION_RESOLVED["$subject_key"]+resolved}" ]]; then
        return 0
    fi


    if [[ -n "${STOLEUS_COMPOSITION_VISITING["$subject_key"]+visiting}" ]]; then

        cycle_path="$(
            stoleus_composition_format_cycle \
                "$subject_key"
        )" || return $?


        printf '%s\n' \
            "ERROR: Circular Composition dependency detected: ${cycle_path}" \
            >&2

        return 8
    fi


    STOLEUS_COMPOSITION_VISITING["$subject_key"]="true"
    STOLEUS_COMPOSITION_TRAVERSAL_STACK+=("$subject_key")


    if stoleus_composition_resolve_provider \
        "$subject_type" \
        "$subject_id" \
        >/dev/null
    then
        provider_id="$STOLEUS_COMPOSITION_SELECTED_PROVIDER"
    else
        exit_code=$?

        stoleus_composition_leave_subject \
            "$subject_key" ||
            return $?

        return "$exit_code"
    fi


    while IFS=$'\t' read -r \
        requirement_type \
        requirement_id
    do

        [[ -z "$requirement_type" ||
           -z "$requirement_id" ]] &&
            continue


        if stoleus_composition_resolve_subject \
            "$requirement_type" \
            "$requirement_id"
        then
            :
        else
            exit_code=$?

            stoleus_composition_leave_subject \
                "$subject_key" ||
                return $?

            return "$exit_code"
        fi

    done < <(
        stoleus_composition_list_provider_requirements \
            "$provider_id"
    )


    stoleus_composition_leave_subject \
        "$subject_key" ||
        return $?


    STOLEUS_COMPOSITION_RESOLVED["$subject_key"]="true"


    stoleus_composition_cache \
        "$subject_type" \
        "$subject_id" \
        "$provider_id" ||
        return $?


    return 0
}

# ==============================================================================
# stoleus_composition_validate_subject_type
# ==============================================================================

stoleus_composition_validate_subject_type() {

    local subject_type="${1:-}"


    case "$subject_type" in
        plugin|service|capability)
            return 0
            ;;
    esac


    printf '%s\n' \
        "ERROR: Unsupported Composition subject type: ${subject_type}" >&2

    return 6
}


# ==============================================================================
# stoleus_composition_get_key
# ==============================================================================

stoleus_composition_get_key() {

    local subject_type="${1:-}"
    local subject_id="${2:-}"


    stoleus_composition_validate_subject_type \
        "$subject_type" ||
        return $?


    if [[ -z "$subject_id" ||
          ! "$subject_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Composition requires a valid subject ID." >&2

        return 2
    fi


    printf '%s:%s\n' \
        "$subject_type" \
        "$subject_id"

    return 0
}


# ==============================================================================
# stoleus_composition_contains
# ==============================================================================

stoleus_composition_contains() {


    local subject_type="${1:-}"
    local subject_id="${2:-}"

    local key=""


    key="$(
        stoleus_composition_get_key \
            "$subject_type" \
            "$subject_id"
    )" || return $?


    [[ -n "${STOLEUS_COMPOSITION_INDEX_BY_SUBJECT["$key"]+stored}" ]]
}


# ==============================================================================
# stoleus_composition_cache
# ==============================================================================

stoleus_composition_cache() {

    stoleus_composition_sync_context || return $?

    local subject_type="${1:-}"
    local subject_id="${2:-}"
    local provider_id="${3:-}"

    local key=""
    local index=0


    if [[ "${STOLEUS_COMPOSITION_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Composition must be initialized before caching." >&2

        return 6
    fi


    key="$(
        stoleus_composition_get_key \
            "$subject_type" \
            "$subject_id"
    )" || return $?


    if [[ -z "$provider_id" ||
          ! "$provider_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Composition requires a valid provider ID." >&2

        return 2
    fi


    if stoleus_composition_contains \
        "$subject_type" \
        "$subject_id"; then

        return 0
    fi


    index="${#STOLEUS_COMPOSITION_SUBJECT_IDS[@]}"


    STOLEUS_COMPOSITION_SUBJECT_TYPES+=("$subject_type")
    STOLEUS_COMPOSITION_SUBJECT_IDS+=("$subject_id")
    STOLEUS_COMPOSITION_PROVIDER_IDS+=("$provider_id")
    STOLEUS_COMPOSITION_CONTEXT_GENERATIONS+=(
        "${STOLEUS_CONTEXT_GENERATION:-0}"
    )
    STOLEUS_COMPOSITION_STATUSES+=("resolved")

    STOLEUS_COMPOSITION_INDEX_BY_SUBJECT["$key"]="$index"


    return 0
}


# ==============================================================================
# stoleus_composition_get
# ==============================================================================

stoleus_composition_get() {


    local subject_type="${1:-}"
    local subject_id="${2:-}"

    local key=""
    local index=""


    key="$(
        stoleus_composition_get_key \
            "$subject_type" \
            "$subject_id"
    )" || return $?


    if ! stoleus_composition_contains \
        "$subject_type" \
        "$subject_id"; then

        return 6
    fi


    index="${STOLEUS_COMPOSITION_INDEX_BY_SUBJECT["$key"]}"


    printf '%s\t%s\t%s\t%s\t%s\n' \
        "${STOLEUS_COMPOSITION_SUBJECT_TYPES[$index]}" \
        "${STOLEUS_COMPOSITION_SUBJECT_IDS[$index]}" \
        "${STOLEUS_COMPOSITION_PROVIDER_IDS[$index]}" \
        "${STOLEUS_COMPOSITION_CONTEXT_GENERATIONS[$index]}" \
        "${STOLEUS_COMPOSITION_STATUSES[$index]}"

    return 0
}


# ==============================================================================
# stoleus_composition_get_provider
# ==============================================================================

stoleus_composition_get_provider() {


    local subject_type="${1:-}"
    local subject_id="${2:-}"

    local key=""
    local index=""


    key="$(
        stoleus_composition_get_key \
            "$subject_type" \
            "$subject_id"
    )" || return $?


    if ! stoleus_composition_contains \
        "$subject_type" \
        "$subject_id"; then

        return 6
    fi


    index="${STOLEUS_COMPOSITION_INDEX_BY_SUBJECT["$key"]}"


    printf '%s\n' \
        "${STOLEUS_COMPOSITION_PROVIDER_IDS[$index]}"

    return 0
}


# ==============================================================================
# stoleus_composition_explain_subject
# ==============================================================================
#
# Purpose:
#     Render one already-resolved Composition subject and its dependencies.
#
# Arguments:
#
#     $1 = subject type
#     $2 = subject ID
#     $3 = indentation depth
#
# This function is read-only.
# ==============================================================================

stoleus_composition_explain_subject() {

    local subject_type="${1:-}"
    local subject_id="${2:-}"
    local depth="${3:-0}"

    local provider_id=""
    local requirement_type=""
    local requirement_id=""

    local indent=""
    local child_indent=""
    local requirements=""


    if [[ ! "$depth" =~ ^[0-9]+$ ]]; then
        return 2
    fi


    if ! stoleus_composition_contains \
        "$subject_type" \
        "$subject_id"; then

        printf '%s\n' \
            "ERROR: Composition subject is not resolved: ${subject_type}:${subject_id}" \
            >&2

        return 6
    fi


    provider_id="$(
        stoleus_composition_get_provider \
            "$subject_type" \
            "$subject_id"
    )" || return $?


    printf -v indent '%*s' "$((depth * 2))" ""
    printf -v child_indent '%*s' "$(((depth + 1) * 2))" ""


    printf '%s%s:%s\n' \
        "$indent" \
        "$subject_type" \
        "$subject_id"

    printf '%sprovider: %s\n' \
        "$child_indent" \
        "$provider_id"


    requirements="$(
        stoleus_composition_list_provider_requirements \
            "$provider_id"
    )" || return $?


    if [[ -z "$requirements" ]]; then
        return 0
    fi


    printf '%sdependencies:\n' \
        "$child_indent"


    while IFS=$'\t' read -r \
        requirement_type \
        requirement_id
    do

        [[ -z "$requirement_type" ||
           -z "$requirement_id" ]] &&
            continue


        stoleus_composition_explain_subject \
            "$requirement_type" \
            "$requirement_id" \
            "$((depth + 2))" ||
            return $?

    done <<< "$requirements"


    return 0
}


# ==============================================================================
# stoleus_composition_explain
# ==============================================================================
#
# Purpose:
#     Explain one previously resolved Composition graph.
#
# Arguments:
#
#     $1 = plugin | service | capability
#     $2 = subject ID
#
# This operation is diagnostic and read-only. It never resolves or mutates
# Composition state.
# ==============================================================================

stoleus_composition_explain() {

    local subject_type="${1:-}"
    local subject_id="${2:-}"


    stoleus_composition_validate_subject_type \
        "$subject_type" ||
        return $?


    if [[ -z "$subject_id" ||
          ! "$subject_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Composition explain requires a valid subject ID." >&2

        return 2
    fi


    stoleus_composition_explain_subject \
        "$subject_type" \
        "$subject_id" \
        "0"

    return $?
}


# ==============================================================================
# stoleus_composition_list
# ==============================================================================
#
# Purpose:
#     List all resolved Composition records in deterministic dependency-first
#     order.
#
# Output:
#
#     type<TAB>subject-id<TAB>provider-id<TAB>context-generation<TAB>status
#
# This function is read-only.
# ==============================================================================

stoleus_composition_list() {

    local index=0


    for index in "${!STOLEUS_COMPOSITION_SUBJECT_IDS[@]}"; do

        printf '%s\t%s\t%s\t%s\t%s\n' \
            "${STOLEUS_COMPOSITION_SUBJECT_TYPES[$index]}" \
            "${STOLEUS_COMPOSITION_SUBJECT_IDS[$index]}" \
            "${STOLEUS_COMPOSITION_PROVIDER_IDS[$index]}" \
            "${STOLEUS_COMPOSITION_CONTEXT_GENERATIONS[$index]}" \
            "${STOLEUS_COMPOSITION_STATUSES[$index]}"
    done


    return 0
}


# ==============================================================================
# stoleus_composition_list_order
# ==============================================================================
#
# Purpose:
#     List resolved Composition subjects in deterministic dependency-first order.
#
# Output:
#
#     type<TAB>subject-id<TAB>provider-id
# ==============================================================================

stoleus_composition_list_order() {

    local index=0


    for index in "${!STOLEUS_COMPOSITION_SUBJECT_IDS[@]}"; do

        printf '%s\t%s\t%s\n' \
            "${STOLEUS_COMPOSITION_SUBJECT_TYPES[$index]}" \
            "${STOLEUS_COMPOSITION_SUBJECT_IDS[$index]}" \
            "${STOLEUS_COMPOSITION_PROVIDER_IDS[$index]}"
    done


    return 0
}


# ==============================================================================
# stoleus_composition_get_count
# ==============================================================================

stoleus_composition_get_count() {


    printf '%s\n' \
        "${#STOLEUS_COMPOSITION_SUBJECT_IDS[@]}"

    return 0
}


# ==============================================================================
# stoleus_composition_initialize
# ==============================================================================

stoleus_composition_initialize() {

    if [[ "${STOLEUS_COMPOSITION_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_composition_reset || return $?


    STOLEUS_COMPOSITION_INITIALIZED="true"


    return 0
}

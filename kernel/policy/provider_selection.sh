#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Generic Provider Selection Policy
# ==============================================================================
#
# Purpose:
#     Select one provider from a set of registered provider candidates using
#     generic policy metadata.
#
# Selection order:
#
#     1. Explicit override, when supplied and eligible.
#     2. Enabled candidate filtering.
#     3. Highest numeric priority.
#     4. Highest-priority tie -> conflict.
#
# Providers without explicit policy metadata receive:
#
#     priority = 0
#     enabled  = true
#
# Conditions and tags are stored by the Policy Registry but are intentionally
# not evaluated in this phase.
# ==============================================================================

set -Eeuo pipefail


if [[ "${STOLEUS_PROVIDER_SELECTION_LOADED:-false}" == "true" ]]; then
    return 0
fi

STOLEUS_PROVIDER_SELECTION_LOADED="true"


STOLEUS_PROVIDER_SELECTION_INITIALIZED="false"

STOLEUS_PROVIDER_SELECTION_SELECTED_PROVIDER=""
STOLEUS_PROVIDER_SELECTION_SELECTED_SUBJECT_TYPE=""
STOLEUS_PROVIDER_SELECTION_SELECTED_SUBJECT_ID=""


# ==============================================================================
# stoleus_provider_selection_get_policy_key
# ==============================================================================

stoleus_provider_selection_get_policy_key() {

    local subject_type="${1:-}"
    local subject_id="${2:-}"
    local provider_id="${3:-}"


    if [[ -z "$subject_type" ||
          -z "$subject_id" ||
          -z "$provider_id" ]]; then

        return 2
    fi


    printf '%s:%s@%s\n' \
        "$subject_type" \
        "$subject_id" \
        "$provider_id"

    return 0
}


# ==============================================================================
# stoleus_provider_selection_get_priority
# ==============================================================================

stoleus_provider_selection_get_priority() {

    local subject_type="${1:-}"
    local subject_id="${2:-}"
    local provider_id="${3:-}"

    local policy_key=""


    policy_key="$(
        stoleus_provider_selection_get_policy_key \
            "$subject_type" \
            "$subject_id" \
            "$provider_id"
    )" || return $?


    if ! stoleus_provider_policy_registry_contains "$policy_key"; then

        printf '%s\n' "0"

        return 0
    fi


    stoleus_provider_policy_registry_get_field \
        "$policy_key" \
        "priority"

    return $?
}


# ==============================================================================
# stoleus_provider_selection_is_enabled
# ==============================================================================

stoleus_provider_selection_is_enabled() {

    local subject_type="${1:-}"
    local subject_id="${2:-}"
    local provider_id="${3:-}"

    local policy_key=""
    local enabled=""


    policy_key="$(
        stoleus_provider_selection_get_policy_key \
            "$subject_type" \
            "$subject_id" \
            "$provider_id"
    )" || return $?


    if ! stoleus_provider_policy_registry_contains "$policy_key"; then
        return 0
    fi


    enabled="$(
        stoleus_provider_policy_registry_get_field \
            "$policy_key" \
            "enabled"
    )" || return $?


    [[ "$enabled" == "true" ]]
}


# ==============================================================================
# stoleus_provider_selection_get_conditions
# ==============================================================================

stoleus_provider_selection_get_conditions() {

    local subject_type="${1:-}"
    local subject_id="${2:-}"
    local provider_id="${3:-}"

    local policy_key=""


    policy_key="$(
        stoleus_provider_selection_get_policy_key \
            "$subject_type" \
            "$subject_id" \
            "$provider_id"
    )" || return $?


    if ! stoleus_provider_policy_registry_contains "$policy_key"; then

        printf '%s\n' ""

        return 0
    fi


    stoleus_provider_policy_registry_get_field \
        "$policy_key" \
        "conditions"

    return $?
}


# ==============================================================================
# stoleus_provider_selection_matches_conditions
# ==============================================================================
#
# Arguments:
#
#     $1 = subject type
#     $2 = subject ID
#     $3 = provider ID
#
# Return codes:
#
#     0 = conditions match, or no conditions are configured
#     1 = conditions do not match current Context
#     other = configuration/runtime error
# ==============================================================================

stoleus_provider_selection_matches_conditions() {

    local subject_type="${1:-}"
    local subject_id="${2:-}"
    local provider_id="${3:-}"

    local policy_key=""
    local conditions=""


    if [[ -z "$subject_type" ||
          -z "$subject_id" ||
          -z "$provider_id" ]]; then

        printf '%s\n' \
            "ERROR: Provider condition evaluation requires subject type, subject ID and provider ID." \
            >&2

        return 2
    fi


    policy_key="$(
        stoleus_provider_selection_get_policy_key \
            "$subject_type" \
            "$subject_id" \
            "$provider_id"
    )" || return $?


    # Providers without explicit policy metadata are context-independent.
    if ! stoleus_provider_policy_registry_contains "$policy_key"; then
        return 0
    fi


    conditions="$(
        stoleus_provider_policy_registry_get_field \
            "$policy_key" \
            "conditions"
    )" || return $?


    stoleus_context_matches_conditions "$conditions"

    return $?
}


# ==============================================================================
# stoleus_provider_selection_get_selected
# ==============================================================================

stoleus_provider_selection_get_selected() {

    if [[ -z "${STOLEUS_PROVIDER_SELECTION_SELECTED_PROVIDER:-}" ]]; then

        printf '%s\n' \
            "ERROR: No provider-selection result is available." >&2

        return 6
    fi


    printf '%s\n' \
        "$STOLEUS_PROVIDER_SELECTION_SELECTED_PROVIDER"

    return 0
}


# ==============================================================================
# stoleus_provider_selection_select
# ==============================================================================
#
# Arguments:
#
#     $1      = subject type
#     $2      = subject ID
#     $3      = explicit provider override, or empty
#     $4...   = candidate provider IDs
#
# Output:
#
#     selected provider ID
# ==============================================================================

stoleus_provider_selection_select() {

    local subject_type="${1:-}"
    local subject_id="${2:-}"
    local override_provider="${3:-}"

    local candidate=""
    local priority=""
    local conditions=""
    local condition_exit_code=0

    local selected_provider=""
    local selected_priority=-1

    local candidate_count=0
    local eligible_count=0

    local override_registered="false"
    local override_enabled="false"
    local override_context_match="false"

    local index=0

    local -A seen_candidates=()

    local -a candidate_ids=()
    local -a candidate_priorities=()
    local -a candidate_enabled=()
    local -a candidate_conditions=()
    local -a candidate_condition_results=()
    local -a candidate_eligible=()


    if [[ "${STOLEUS_PROVIDER_SELECTION_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Provider Selection must be initialized before selection." \
            >&2

        return 6
    fi


    stoleus_provider_policy_registry_validate_subject_type \
        "$subject_type" ||
        return $?


    if [[ -z "$subject_id" ||
          ! "$subject_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Provider Selection requires a valid subject ID." >&2

        return 2
    fi


    if [[ -n "$override_provider" &&
          ! "$override_provider" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Provider Selection override contains an invalid provider ID." \
            >&2

        return 2
    fi


    STOLEUS_PROVIDER_SELECTION_SELECTED_PROVIDER=""
    STOLEUS_PROVIDER_SELECTION_SELECTED_SUBJECT_TYPE=""
    STOLEUS_PROVIDER_SELECTION_SELECTED_SUBJECT_ID=""


    stoleus_provider_trace_reset || return $?


    shift 3


    # --------------------------------------------------------------------------
    # Evaluate every candidate without yet committing the final trace decision.
    # --------------------------------------------------------------------------
    for candidate in "$@"; do

        [[ -z "$candidate" ]] && continue


        if [[ ! "$candidate" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

            printf '%s\n' \
                "ERROR: Provider Selection contains invalid candidate: ${candidate}" \
                >&2

            return 6
        fi


        if [[ -n "${seen_candidates["$candidate"]+declared}" ]]; then

            printf '%s\n' \
                "ERROR: Duplicate provider candidate: ${candidate}" >&2

            return 8
        fi


        seen_candidates["$candidate"]="true"

        candidate_count="$((candidate_count + 1))"


        priority="$(
            stoleus_provider_selection_get_priority \
                "$subject_type" \
                "$subject_id" \
                "$candidate"
        )" || return $?


        if [[ ! "$priority" =~ ^[0-9]+$ ]]; then

            printf '%s\n' \
                "ERROR: Provider '${candidate}' has invalid policy priority: ${priority}" \
                >&2

            return 6
        fi


        conditions="$(
            stoleus_provider_selection_get_conditions \
                "$subject_type" \
                "$subject_id" \
                "$candidate"
        )" || return $?


        candidate_ids+=("$candidate")
        candidate_priorities+=("$priority")
        candidate_conditions+=("$conditions")


        if [[ -n "$override_provider" &&
              "$candidate" == "$override_provider" ]]; then

            override_registered="true"
        fi


        if stoleus_provider_selection_is_enabled \
            "$subject_type" \
            "$subject_id" \
            "$candidate"; then

            candidate_enabled+=("true")

        else
            candidate_enabled+=("false")
            candidate_condition_results+=("not-evaluated")
            candidate_eligible+=("false")

            continue
        fi


        if [[ -n "$override_provider" &&
              "$candidate" == "$override_provider" ]]; then

            override_enabled="true"
        fi


        if stoleus_provider_selection_matches_conditions \
            "$subject_type" \
            "$subject_id" \
            "$candidate"; then

            condition_exit_code=0

        else
            condition_exit_code=$?
        fi


        if (( condition_exit_code == 1 )); then

            candidate_condition_results+=("rejected")
            candidate_eligible+=("false")

            continue
        fi


        if (( condition_exit_code != 0 )); then
            return "$condition_exit_code"
        fi


        candidate_condition_results+=("matched")
        candidate_eligible+=("true")

        eligible_count="$((eligible_count + 1))"


        if [[ -n "$override_provider" &&
              "$candidate" == "$override_provider" ]]; then

            override_context_match="true"
        fi


        if (( priority > selected_priority )); then

            selected_provider="$candidate"
            selected_priority="$priority"
        fi
    done


    # --------------------------------------------------------------------------
    # Validate the candidate population and explicit override.
    # --------------------------------------------------------------------------
    if (( candidate_count == 0 )); then

        printf '%s\n' \
            "ERROR: No providers are registered for ${subject_type}: ${subject_id}" \
            >&2

        return 6
    fi


    if [[ -n "$override_provider" ]]; then

        if [[ "$override_registered" != "true" ]]; then

            printf '%s\n' \
                "ERROR: Provider override '${override_provider}' is not registered for ${subject_type} '${subject_id}'." \
                >&2

            return 6
        fi


        if [[ "$override_enabled" != "true" ]]; then

            for index in "${!candidate_ids[@]}"; do

                if [[ "${candidate_ids[$index]}" == "$override_provider" ]]; then

                    stoleus_provider_trace_append \
                        "$subject_type" \
                        "$subject_id" \
                        "${candidate_ids[$index]}" \
                        "${candidate_enabled[$index]}" \
                        "${candidate_conditions[$index]}" \
                        "${candidate_condition_results[$index]}" \
                        "${candidate_priorities[$index]}" \
                        "rejected-disabled" \
                        "explicit provider override is disabled" ||
                        return $?

                    break
                fi
            done


            printf '%s\n' \
                "ERROR: Provider override '${override_provider}' is disabled for ${subject_type} '${subject_id}'." \
                >&2

            return 6
        fi


        if [[ "$override_context_match" != "true" ]]; then

            for index in "${!candidate_ids[@]}"; do

                if [[ "${candidate_ids[$index]}" == "$override_provider" ]]; then

                    stoleus_provider_trace_append \
                        "$subject_type" \
                        "$subject_id" \
                        "${candidate_ids[$index]}" \
                        "${candidate_enabled[$index]}" \
                        "${candidate_conditions[$index]}" \
                        "${candidate_condition_results[$index]}" \
                        "${candidate_priorities[$index]}" \
                        "rejected-context" \
                        "explicit provider override does not match runtime context" ||
                        return $?

                    break
                fi
            done


            printf '%s\n' \
                "ERROR: Provider override '${override_provider}' does not match runtime context for ${subject_type} '${subject_id}'." \
                >&2

            return 6
        fi


        selected_provider="$override_provider"
    fi


    if (( eligible_count == 0 )); then

        for index in "${!candidate_ids[@]}"; do

            if [[ "${candidate_enabled[$index]}" != "true" ]]; then

                stoleus_provider_trace_append \
                    "$subject_type" \
                    "$subject_id" \
                    "${candidate_ids[$index]}" \
                    "${candidate_enabled[$index]}" \
                    "${candidate_conditions[$index]}" \
                    "${candidate_condition_results[$index]}" \
                    "${candidate_priorities[$index]}" \
                    "rejected-disabled" \
                    "provider is disabled" ||
                    return $?

            else

                stoleus_provider_trace_append \
                    "$subject_type" \
                    "$subject_id" \
                    "${candidate_ids[$index]}" \
                    "${candidate_enabled[$index]}" \
                    "${candidate_conditions[$index]}" \
                    "${candidate_condition_results[$index]}" \
                    "${candidate_priorities[$index]}" \
                    "rejected-context" \
                    "provider conditions do not match runtime context" ||
                    return $?
            fi
        done


        printf '%s\n' \
            "ERROR: No eligible provider is available for ${subject_type}: ${subject_id}" \
            >&2

        return 6
    fi


    # --------------------------------------------------------------------------
    # Detect a highest-priority conflict when no override resolved selection.
    # --------------------------------------------------------------------------
    if [[ -z "$override_provider" ]]; then

        local highest_priority_count=0


        for index in "${!candidate_ids[@]}"; do

            if [[ "${candidate_eligible[$index]}" == "true" &&
                  "${candidate_priorities[$index]}" == "$selected_priority" ]]; then

                highest_priority_count="$((highest_priority_count + 1))"
            fi
        done


        if (( highest_priority_count > 1 )); then

            for index in "${!candidate_ids[@]}"; do

                if [[ "${candidate_enabled[$index]}" != "true" ]]; then

                    stoleus_provider_trace_append \
                        "$subject_type" \
                        "$subject_id" \
                        "${candidate_ids[$index]}" \
                        "${candidate_enabled[$index]}" \
                        "${candidate_conditions[$index]}" \
                        "${candidate_condition_results[$index]}" \
                        "${candidate_priorities[$index]}" \
                        "rejected-disabled" \
                        "provider is disabled" ||
                        return $?

                elif [[ "${candidate_condition_results[$index]}" != "matched" ]]; then

                    stoleus_provider_trace_append \
                        "$subject_type" \
                        "$subject_id" \
                        "${candidate_ids[$index]}" \
                        "${candidate_enabled[$index]}" \
                        "${candidate_conditions[$index]}" \
                        "${candidate_condition_results[$index]}" \
                        "${candidate_priorities[$index]}" \
                        "rejected-context" \
                        "provider conditions do not match runtime context" ||
                        return $?

                elif [[ "${candidate_priorities[$index]}" == "$selected_priority" ]]; then

                    stoleus_provider_trace_append \
                        "$subject_type" \
                        "$subject_id" \
                        "${candidate_ids[$index]}" \
                        "${candidate_enabled[$index]}" \
                        "${candidate_conditions[$index]}" \
                        "${candidate_condition_results[$index]}" \
                        "${candidate_priorities[$index]}" \
                        "rejected-tie" \
                        "provider shares the highest eligible priority" ||
                        return $?

                else

                    stoleus_provider_trace_append \
                        "$subject_type" \
                        "$subject_id" \
                        "${candidate_ids[$index]}" \
                        "${candidate_enabled[$index]}" \
                        "${candidate_conditions[$index]}" \
                        "${candidate_condition_results[$index]}" \
                        "${candidate_priorities[$index]}" \
                        "eligible-lower-priority" \
                        "provider has lower priority than the tied leaders" ||
                        return $?
                fi
            done


            printf '%s\n' \
                "ERROR: ${subject_type} '${subject_id}' has multiple eligible providers with highest priority ${selected_priority}." \
                >&2

            return 8
        fi
    fi


    # --------------------------------------------------------------------------
    # Record the final successful decision for every candidate.
    # --------------------------------------------------------------------------
    for index in "${!candidate_ids[@]}"; do

        if [[ "${candidate_enabled[$index]}" != "true" ]]; then

            stoleus_provider_trace_append \
                "$subject_type" \
                "$subject_id" \
                "${candidate_ids[$index]}" \
                "${candidate_enabled[$index]}" \
                "${candidate_conditions[$index]}" \
                "${candidate_condition_results[$index]}" \
                "${candidate_priorities[$index]}" \
                "rejected-disabled" \
                "provider is disabled" ||
                return $?

            continue
        fi


        if [[ "${candidate_condition_results[$index]}" != "matched" ]]; then

            stoleus_provider_trace_append \
                "$subject_type" \
                "$subject_id" \
                "${candidate_ids[$index]}" \
                "${candidate_enabled[$index]}" \
                "${candidate_conditions[$index]}" \
                "${candidate_condition_results[$index]}" \
                "${candidate_priorities[$index]}" \
                "rejected-context" \
                "provider conditions do not match runtime context" ||
                return $?

            continue
        fi


        if [[ "${candidate_ids[$index]}" == "$selected_provider" ]]; then

            if [[ -n "$override_provider" ]]; then

                stoleus_provider_trace_append \
                    "$subject_type" \
                    "$subject_id" \
                    "${candidate_ids[$index]}" \
                    "${candidate_enabled[$index]}" \
                    "${candidate_conditions[$index]}" \
                    "${candidate_condition_results[$index]}" \
                    "${candidate_priorities[$index]}" \
                    "selected-override" \
                    "explicit provider override selected this provider" ||
                    return $?

            else

                stoleus_provider_trace_append \
                    "$subject_type" \
                    "$subject_id" \
                    "${candidate_ids[$index]}" \
                    "${candidate_enabled[$index]}" \
                    "${candidate_conditions[$index]}" \
                    "${candidate_condition_results[$index]}" \
                    "${candidate_priorities[$index]}" \
                    "selected" \
                    "highest-priority eligible provider" ||
                    return $?
            fi

            continue
        fi


        stoleus_provider_trace_append \
            "$subject_type" \
            "$subject_id" \
            "${candidate_ids[$index]}" \
            "${candidate_enabled[$index]}" \
            "${candidate_conditions[$index]}" \
            "${candidate_condition_results[$index]}" \
            "${candidate_priorities[$index]}" \
            "eligible-lower-priority" \
            "eligible provider was not selected" ||
            return $?
    done


    STOLEUS_PROVIDER_SELECTION_SELECTED_PROVIDER="$selected_provider"
    STOLEUS_PROVIDER_SELECTION_SELECTED_SUBJECT_TYPE="$subject_type"
    STOLEUS_PROVIDER_SELECTION_SELECTED_SUBJECT_ID="$subject_id"


    printf '%s\n' "$selected_provider"

    return 0
}


# ==============================================================================
# stoleus_provider_selection_initialize
# ==============================================================================

stoleus_provider_selection_initialize() {

    if [[ "${STOLEUS_PROVIDER_SELECTION_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    STOLEUS_PROVIDER_SELECTION_INITIALIZED="true"


    return 0
}

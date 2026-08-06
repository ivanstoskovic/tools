#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Rollback Plan Builder
# ==============================================================================
#
# Purpose:
#     Own Rollback Plan mutation, sequencing, and freezing.
#
# The builder does not decide which actions belong in a rollback plan. That is
# the Rollback Planner's responsibility.
#
# Internal API:
#
#     stoleus_rollback_builder_initialize
#     stoleus_rollback_builder_reset
#     stoleus_rollback_builder_begin
#     stoleus_rollback_builder_add
#     stoleus_rollback_builder_finalize
#     stoleus_rollback_builder_is_active
#     stoleus_rollback_builder_is_finalized
#     stoleus_rollback_builder_get_count
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_ROLLBACK_BUILDER_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_ROLLBACK_BUILDER_SUBSYSTEM_LOADED="true"


# ==============================================================================
# State
# ==============================================================================

STOLEUS_ROLLBACK_BUILDER_ACTIVE="false"
STOLEUS_ROLLBACK_BUILDER_FINALIZED="false"
STOLEUS_ROLLBACK_BUILDER_NEXT_STEP=1


# ==============================================================================
# stoleus_rollback_builder_reset
# ==============================================================================

stoleus_rollback_builder_reset() {

    stoleus_rollback_plan_reset || return $?


    STOLEUS_ROLLBACK_BUILDER_ACTIVE="false"
    STOLEUS_ROLLBACK_BUILDER_FINALIZED="false"
    STOLEUS_ROLLBACK_BUILDER_NEXT_STEP=1


    return 0
}


# ==============================================================================
# stoleus_rollback_builder_is_active
# ==============================================================================

stoleus_rollback_builder_is_active() {

    [[ "${STOLEUS_ROLLBACK_BUILDER_ACTIVE:-false}" == "true" ]]
}


# ==============================================================================
# stoleus_rollback_builder_is_finalized
# ==============================================================================

stoleus_rollback_builder_is_finalized() {

    [[ "${STOLEUS_ROLLBACK_BUILDER_FINALIZED:-false}" == "true" ]]
}


# ==============================================================================
# stoleus_rollback_builder_begin
# ==============================================================================

stoleus_rollback_builder_begin() {

    if [[ "${STOLEUS_ROLLBACK_BUILDER_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Rollback Plan Builder must be initialized before use." \
            >&2

        return 6
    fi


    if stoleus_rollback_builder_is_active; then

        printf '%s\n' \
            "ERROR: Rollback Plan Builder is already active." >&2

        return 8
    fi


    if stoleus_rollback_builder_is_finalized ||
       stoleus_rollback_plan_is_frozen; then

        printf '%s\n' \
            "ERROR: Rollback Plan Builder must be reset before starting another build." \
            >&2

        return 8
    fi


    stoleus_rollback_plan_reset || return $?


    STOLEUS_ROLLBACK_BUILDER_ACTIVE="true"
    STOLEUS_ROLLBACK_BUILDER_FINALIZED="false"
    STOLEUS_ROLLBACK_BUILDER_NEXT_STEP=1


    return 0
}


# ==============================================================================
# stoleus_rollback_builder_add
# ==============================================================================
#
# Arguments:
#
#     $1 = original execution step
#     $2 = plugin ID
#     $3 = rollback function
#
# The rollback-step sequence is assigned automatically.
# ==============================================================================

stoleus_rollback_builder_add() {

    local execution_step="${1:-}"
    local plugin_id="${2:-}"
    local rollback_function="${3:-}"

    local rollback_step=0


    if ! stoleus_rollback_builder_is_active; then

        printf '%s\n' \
            "ERROR: Rollback Plan Builder is not active." >&2

        return 8
    fi


    if stoleus_rollback_builder_is_finalized; then

        printf '%s\n' \
            "ERROR: Finalized Rollback Plan Builder cannot accept actions." \
            >&2

        return 8
    fi


    rollback_step="$STOLEUS_ROLLBACK_BUILDER_NEXT_STEP"


    stoleus_rollback_plan_append \
        "$rollback_step" \
        "$execution_step" \
        "$plugin_id" \
        "$rollback_function" ||
        return $?


    STOLEUS_ROLLBACK_BUILDER_NEXT_STEP="$((rollback_step + 1))"


    return 0
}


# ==============================================================================
# stoleus_rollback_builder_finalize
# ==============================================================================

stoleus_rollback_builder_finalize() {

    if ! stoleus_rollback_builder_is_active; then

        printf '%s\n' \
            "ERROR: Rollback Plan Builder is not active." >&2

        return 8
    fi


    if stoleus_rollback_builder_is_finalized; then

        printf '%s\n' \
            "ERROR: Rollback Plan Builder has already been finalized." >&2

        return 8
    fi


    stoleus_rollback_plan_freeze || return $?


    STOLEUS_ROLLBACK_BUILDER_ACTIVE="false"
    STOLEUS_ROLLBACK_BUILDER_FINALIZED="true"


    return 0
}


# ==============================================================================
# stoleus_rollback_builder_get_count
# ==============================================================================

stoleus_rollback_builder_get_count() {

    stoleus_rollback_plan_get_count

    return $?
}


# ==============================================================================
# stoleus_rollback_builder_initialize
# ==============================================================================

stoleus_rollback_builder_initialize() {

    if [[ "${STOLEUS_ROLLBACK_BUILDER_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_rollback_builder_reset || return $?


    STOLEUS_ROLLBACK_BUILDER_INITIALIZED="true"


    return 0
}

#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Capability Provider Policy
# ==============================================================================
#
# Purpose:
#     Own deterministic selection rules for capability providers.
#
# This subsystem does not own provider metadata. Provider facts remain in the
# Capability Registry. The Resolver supplies candidate providers to this policy.
#
# Initial selection rules:
#
#     - no candidates                    -> not found
#     - one candidate                    -> select candidate
#     - multiple candidates              -> conflict
#     - explicit registered override     -> select override
#     - explicit unregistered override   -> not found
#
# Future policy inputs:
#
#     - provider priority
#     - runtime-context compatibility
#     - platform compatibility
#     - deterministic policy diagnostics
#
# Internal API:
#
#     stoleus_capability_policy_initialize
#     stoleus_capability_policy_reset
#     stoleus_capability_policy_select
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_CAPABILITY_POLICY_LOADED:-false}" == "true" ]]; then
    return 0
fi

STOLEUS_CAPABILITY_POLICY_LOADED="true"


# ==============================================================================
# State
# ==============================================================================

STOLEUS_CAPABILITY_POLICY_INITIALIZED="false"


# ==============================================================================
# stoleus_capability_policy_reset
# ==============================================================================

stoleus_capability_policy_reset() {

    if [[ "${STOLEUS_CAPABILITY_POLICY_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Capability Policy must be initialized before reset." >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_capability_policy_select
# ==============================================================================
#
# Arguments:
#
#     $1      = capability ID
#     $2      = explicit provider override, or empty string
#     $3...   = candidate provider plugin IDs
#
# Output:
#
#     selected provider plugin ID
# ==============================================================================

stoleus_capability_policy_select() {

    local capability_id="${1:-}"
    local override_provider="${2:-}"


    if [[ "${STOLEUS_CAPABILITY_POLICY_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Capability Policy must be initialized before provider selection." \
            >&2

        return 6
    fi


    if [[ -z "$capability_id" ||
          ! "$capability_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Capability Policy requires a valid capability ID." >&2

        return 2
    fi


    if [[ -n "$override_provider" &&
          ! "$override_provider" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Capability provider override contains an invalid provider ID." \
            >&2

        return 2
    fi


    shift 2


    stoleus_provider_selection_select \
        "capability" \
        "$capability_id" \
        "$override_provider" \
        "$@"

    return $?
}


# ==============================================================================
# stoleus_capability_policy_initialize
# ==============================================================================

stoleus_capability_policy_initialize() {

    if [[ "${STOLEUS_CAPABILITY_POLICY_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    STOLEUS_CAPABILITY_POLICY_INITIALIZED="true"


    return 0
}

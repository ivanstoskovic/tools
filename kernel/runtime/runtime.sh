#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Runtime Subsystem
# ==============================================================================
#
# Purpose:
#     Own runtime state shared by kernel subsystems during one framework process.
#
# Future runtime responsibilities:
#
#     - execution context;
#     - platform context;
#     - configuration context;
#     - logging context;
#     - security context.
#
# Runtime state must not contain plugin definitions or execution planning logic.
# ==============================================================================

set -Eeuo pipefail


if [[ "${STOLEUS_RUNTIME_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_RUNTIME_SUBSYSTEM_LOADED="true"


# ==============================================================================
# stoleus_runtime_initialize
# ==============================================================================

stoleus_runtime_initialize() {

    if [[ "${STOLEUS_RUNTIME_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    STOLEUS_RUNTIME_INITIALIZED="true"

    return 0
}

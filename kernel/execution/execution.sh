#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Execution Subsystem
# ==============================================================================
#
# Purpose:
#     Execute immutable execution plans through resolved implementations and
#     providers.
#
# Execution will eventually own:
#
#     - plan-step execution;
#     - lifecycle invocation;
#     - failure propagation;
#     - reporting;
#     - cancellation;
#     - dry-run enforcement.
#
# Execution must not discover plugins or create dependency plans.
# ==============================================================================

set -Eeuo pipefail


if [[ "${STOLEUS_EXECUTION_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_EXECUTION_SUBSYSTEM_LOADED="true"


# ==============================================================================
# stoleus_execution_initialize
# ==============================================================================

stoleus_execution_initialize() {

    if [[ "${STOLEUS_EXECUTION_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    STOLEUS_EXECUTION_INITIALIZED="true"

    return 0
}

#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Planning Subsystem
# ==============================================================================
#
# Purpose:
#     Convert execution requests and registered definitions into immutable
#     execution plans.
#
# Planning will eventually own:
#
#     - dependency resolution;
#     - cycle detection;
#     - lifecycle-stage expansion;
#     - provider resolution;
#     - deterministic ordering.
#
# Planning must never execute infrastructure operations.
# ==============================================================================

set -Eeuo pipefail


if [[ "${STOLEUS_PLANNING_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_PLANNING_SUBSYSTEM_LOADED="true"


# ==============================================================================
# stoleus_planning_initialize
# ==============================================================================

stoleus_planning_initialize() {

    if [[ "${STOLEUS_PLANNING_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    STOLEUS_PLANNING_INITIALIZED="true"

    return 0
}

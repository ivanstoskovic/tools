#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Discovery Subsystem
# ==============================================================================
#
# Purpose:
#     Locate candidate plugins without loading their implementations.
#
# Discovery will eventually:
#
#     - scan configured plugin roots;
#     - identify candidate plugin directories;
#     - identify supported manifest formats;
#     - produce discovery records.
#
# Discovery must not register definitions or execute plugin behavior.
# ==============================================================================

set -Eeuo pipefail


if [[ "${STOLEUS_DISCOVERY_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_DISCOVERY_SUBSYSTEM_LOADED="true"


# ==============================================================================
# stoleus_discovery_initialize
# ==============================================================================

stoleus_discovery_initialize() {

    if [[ "${STOLEUS_DISCOVERY_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    STOLEUS_DISCOVERY_INITIALIZED="true"

    return 0
}

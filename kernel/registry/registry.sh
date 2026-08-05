#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Registry Subsystem
# ==============================================================================
#
# Purpose:
#     Store normalized, immutable framework definitions.
#
# The registry will eventually contain:
#
#     - plugin definitions;
#     - contract definitions;
#     - capability definitions;
#     - dependency metadata.
#
# The registry must not discover plugins, execute implementations, or modify
# infrastructure.
# ==============================================================================

set -Eeuo pipefail


if [[ "${STOLEUS_REGISTRY_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_REGISTRY_SUBSYSTEM_LOADED="true"


# ==============================================================================
# stoleus_registry_initialize
# ==============================================================================

stoleus_registry_initialize() {

    if [[ "${STOLEUS_REGISTRY_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    STOLEUS_REGISTRY_INITIALIZED="true"

    return 0
}

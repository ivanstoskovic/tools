#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Kernel
# ==============================================================================
#
# Purpose:
#     Assemble and initialize the framework kernel.
#
# The kernel coordinates the framework subsystems but does not contain
# infrastructure automation logic.
#
# Kernel subsystems:
#
#     runtime
#     registry
#     discovery
#     planning
#     execution
#
# This kernel is currently built alongside the existing Stoleus implementation.
# It is not yet loaded by bin/stoleus.
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Kernel Load Guard
# ==============================================================================

if [[ "${STOLEUS_KERNEL_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_KERNEL_LOADED="true"


# ==============================================================================
# Kernel Root Validation
# ==============================================================================

if [[ -z "${PROJECT_ROOT:-}" ]]; then
    printf '%s\n' \
        "ERROR: PROJECT_ROOT must be defined before loading the Stoleus kernel." \
        >&2

    return 1
fi


if [[ ! -d "$PROJECT_ROOT" ]]; then
    printf '%s\n' \
        "ERROR: PROJECT_ROOT does not exist: $PROJECT_ROOT" \
        >&2

    return 1
fi


STOLEUS_KERNEL_ROOT="${PROJECT_ROOT}/kernel"


if [[ ! -d "$STOLEUS_KERNEL_ROOT" ]]; then
    printf '%s\n' \
        "ERROR: Stoleus kernel directory does not exist: $STOLEUS_KERNEL_ROOT" \
        >&2

    return 1
fi


# ==============================================================================
# Kernel Subsystems
# ==============================================================================
#
# Loading order is intentional:
#
#     runtime
#         Provides the runtime state used by all later subsystems.
#
#     registry
#         Owns normalized framework definitions.
#
#     discovery
#         Discovers candidate plugins that can later become definitions.
#
#     planning
#         Produces immutable execution plans from registered definitions.
#
#     execution
#         Executes previously produced plans.
# ==============================================================================

source "${STOLEUS_KERNEL_ROOT}/runtime/runtime.sh"
source "${STOLEUS_KERNEL_ROOT}/registry/registry.sh"
source "${STOLEUS_KERNEL_ROOT}/discovery/discovery.sh"
source "${STOLEUS_KERNEL_ROOT}/planning/planning.sh"
source "${STOLEUS_KERNEL_ROOT}/execution/execution.sh"


# ==============================================================================
# stoleus_kernel_initialize
# ==============================================================================
#
# Purpose:
#     Initialize every kernel subsystem in dependency order.
#
# This function currently initializes subsystem state only.
#
# It does not:
#
#     - discover plugins;
#     - load manifests;
#     - build execution plans;
#     - execute infrastructure changes.
# ==============================================================================
stoleus_kernel_initialize() {

    if [[ "${STOLEUS_KERNEL_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_runtime_initialize || return $?
    stoleus_registry_initialize || return $?
    stoleus_discovery_initialize || return $?
    stoleus_planning_initialize || return $?
    stoleus_execution_initialize || return $?


    STOLEUS_KERNEL_INITIALIZED="true"

    return 0
}

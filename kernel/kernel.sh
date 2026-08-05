#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Kernel
# ==============================================================================
#
# Purpose:
#     Assemble and initialize the Stoleus Framework kernel.
#
# Kernel pipeline:
#
#     Runtime
#         ↓
#     Discovery
#         ↓
#     Definition
#         ↓
#     Registry
#         ↓
#     Resolver
#         ↓
#     Planning
#         ↓
#     Lifecycle
#         ↓
#     Execution
#
# The new kernel is developed alongside the existing production implementation.
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
# Loading order is intentional.
#
# runtime
#     Owns process-level runtime state.
#
# discovery
#     Locates plugin candidates and produces DiscoveryRecords.
#
# definition
#     Converts manifests into normalized PluginDefinitions.
#
# registry
#     Stores validated immutable PluginDefinitions.
#
# resolver
#     Resolves plugin and dependency references.
#
# planning
#     Produces immutable ExecutionPlans.
#
# lifecycle
#     Loads plugin implementations and invokes lifecycle entry points.
#
# execution
#     Executes frozen plan steps through the Lifecycle subsystem.
# ==============================================================================

source "${STOLEUS_KERNEL_ROOT}/runtime/runtime.sh"
source "${STOLEUS_KERNEL_ROOT}/discovery/discovery.sh"
source "${STOLEUS_KERNEL_ROOT}/definition/definition.sh"
source "${STOLEUS_KERNEL_ROOT}/registry/registry.sh"
source "${STOLEUS_KERNEL_ROOT}/resolver/resolver.sh"
source "${STOLEUS_KERNEL_ROOT}/planning/planning.sh"
source "${STOLEUS_KERNEL_ROOT}/lifecycle/lifecycle.sh"
source "${STOLEUS_KERNEL_ROOT}/execution/execution.sh"


# ==============================================================================
# stoleus_kernel_initialize
# ==============================================================================
#
# Purpose:
#     Initialize every kernel subsystem in dependency order.
#
# Initialization alone does not:
#
#     - scan plugin directories;
#     - parse manifests;
#     - import Registry entries;
#     - resolve plugins;
#     - build plans;
#     - load implementations;
#     - execute lifecycle functions.
# ==============================================================================

stoleus_kernel_initialize() {

    if [[ "${STOLEUS_KERNEL_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_runtime_initialize || return $?
    stoleus_discovery_initialize || return $?
    stoleus_definition_initialize || return $?
    stoleus_registry_initialize || return $?
    stoleus_resolver_initialize || return $?
    stoleus_planning_initialize || return $?
    stoleus_lifecycle_initialize || return $?
    stoleus_execution_initialize || return $?


    STOLEUS_KERNEL_INITIALIZED="true"

    return 0
}

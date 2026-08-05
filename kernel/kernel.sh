#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Kernel
# ==============================================================================
#
# Purpose:
#     Assemble, initialize, and bootstrap the Stoleus Framework kernel.
#
# Metadata pipeline:
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
#     Plugin Manager
#
# Operational pipeline:
#
#     ExecutionRequest
#         ↓
#     Planning
#         ↓
#     Lifecycle
#         ↓
#     Execution
#
# Public API:
#
#     stoleus_kernel_initialize
#     stoleus_kernel_bootstrap
#     stoleus_kernel_is_ready
#     stoleus_kernel_get_status
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
#     Resolves and validates plugin references.
#
# plugin
#     Exposes canonical runtime views over Registry and Lifecycle state.
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
source "${STOLEUS_KERNEL_ROOT}/metadata/collection.sh"
source "${STOLEUS_KERNEL_ROOT}/discovery/discovery.sh"
source "${STOLEUS_KERNEL_ROOT}/definition/definition.sh"
source "${STOLEUS_KERNEL_ROOT}/registry/registry.sh"
source "${STOLEUS_KERNEL_ROOT}/resolver/resolver.sh"
source "${STOLEUS_KERNEL_ROOT}/contract/definition.sh"
source "${STOLEUS_KERNEL_ROOT}/contract/registry.sh"
source "${STOLEUS_KERNEL_ROOT}/plugin/plugin.sh"
source "${STOLEUS_KERNEL_ROOT}/planning/planning.sh"
source "${STOLEUS_KERNEL_ROOT}/lifecycle/lifecycle.sh"
source "${STOLEUS_KERNEL_ROOT}/execution/execution.sh"


# ==============================================================================
# Kernel Bootstrap State
# ==============================================================================

STOLEUS_KERNEL_BOOTSTRAP_STARTED="false"
STOLEUS_KERNEL_BOOTSTRAP_COMPLETED="false"
STOLEUS_KERNEL_READY="false"

STOLEUS_KERNEL_BOOTSTRAP_STAGE="not-started"
STOLEUS_KERNEL_BOOTSTRAP_EXIT_CODE="0"


# ==============================================================================
# stoleus_kernel_is_ready
# ==============================================================================

stoleus_kernel_is_ready() {

    [[ "${STOLEUS_KERNEL_READY:-false}" == "true" ]]
}


# ==============================================================================
# stoleus_kernel_initialize
# ==============================================================================
#
# Purpose:
#     Initialize every kernel subsystem in dependency order.
# ==============================================================================

stoleus_kernel_initialize() {

    if [[ "${STOLEUS_KERNEL_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_runtime_initialize || return $?
    stoleus_metadata_initialize || return $?
    stoleus_discovery_initialize || return $?
    stoleus_definition_initialize || return $?
    stoleus_registry_initialize || return $?
    stoleus_resolver_initialize || return $?
    stoleus_contract_definition_initialize || return $?
    stoleus_contract_registry_initialize || return $?
    stoleus_plugin_initialize || return $?
    stoleus_planning_initialize || return $?
    stoleus_lifecycle_initialize || return $?
    stoleus_execution_initialize || return $?


    STOLEUS_KERNEL_INITIALIZED="true"

    return 0
}


# ==============================================================================
# stoleus_kernel_record_bootstrap_failure
# ==============================================================================

stoleus_kernel_record_bootstrap_failure() {

    local stage_name="${1:-unknown}"
    local exit_code="${2:-1}"


    STOLEUS_KERNEL_BOOTSTRAP_STAGE="$stage_name"
    STOLEUS_KERNEL_BOOTSTRAP_EXIT_CODE="$exit_code"

    STOLEUS_KERNEL_BOOTSTRAP_COMPLETED="true"
    STOLEUS_KERNEL_READY="false"


    return 0
}


# ==============================================================================
# stoleus_kernel_bootstrap
# ==============================================================================
#
# Purpose:
#     Build the complete immutable kernel metadata model.
#
# Bootstrap stages:
#
#     initialize
#     discover
#     define
#     register
#     resolve
#     plugins
#     ready
# ==============================================================================

stoleus_kernel_bootstrap() {

    local exit_code=0


    if stoleus_kernel_is_ready; then
        return 0
    fi


    if [[ "${STOLEUS_KERNEL_BOOTSTRAP_COMPLETED:-false}" == "true" ]] &&
       [[ "${STOLEUS_KERNEL_READY:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Kernel bootstrap previously failed at stage '${STOLEUS_KERNEL_BOOTSTRAP_STAGE}' with exit code ${STOLEUS_KERNEL_BOOTSTRAP_EXIT_CODE}." \
            >&2

        return 8
    fi


    if [[ "${STOLEUS_KERNEL_BOOTSTRAP_STARTED:-false}" == "true" ]]; then

        printf '%s\n' \
            "ERROR: Kernel bootstrap is already in progress." >&2

        return 8
    fi


    STOLEUS_KERNEL_BOOTSTRAP_STARTED="true"
    STOLEUS_KERNEL_BOOTSTRAP_STAGE="initialize"
    STOLEUS_KERNEL_BOOTSTRAP_EXIT_CODE="0"


    if stoleus_kernel_initialize; then
        exit_code=0
    else
        exit_code=$?

        stoleus_kernel_record_bootstrap_failure \
            "initialize" \
            "$exit_code"

        return "$exit_code"
    fi


    STOLEUS_KERNEL_BOOTSTRAP_STAGE="discover"


    if stoleus_discovery_scan; then
        exit_code=0
    else
        exit_code=$?

        stoleus_kernel_record_bootstrap_failure \
            "discover" \
            "$exit_code"

        return "$exit_code"
    fi


    STOLEUS_KERNEL_BOOTSTRAP_STAGE="define"


    if stoleus_definition_build_all; then
        exit_code=0
    else
        exit_code=$?

        stoleus_kernel_record_bootstrap_failure \
            "define" \
            "$exit_code"

        return "$exit_code"
    fi


    STOLEUS_KERNEL_BOOTSTRAP_STAGE="register"


    if stoleus_registry_import_definitions; then
        exit_code=0
    else
        exit_code=$?

        stoleus_kernel_record_bootstrap_failure \
            "register" \
            "$exit_code"

        return "$exit_code"
    fi


    STOLEUS_KERNEL_BOOTSTRAP_STAGE="resolve"


    if stoleus_resolver_validate_registry; then
        exit_code=0
    else
        exit_code=$?

        stoleus_kernel_record_bootstrap_failure \
            "resolve" \
            "$exit_code"

        return "$exit_code"
    fi


    STOLEUS_KERNEL_BOOTSTRAP_STAGE="contracts"


    if stoleus_contract_definition_build_all; then
        exit_code=0
    else
        exit_code=$?

        stoleus_kernel_record_bootstrap_failure \
            "contracts" \
            "$exit_code"

        return "$exit_code"
    fi


    STOLEUS_KERNEL_BOOTSTRAP_STAGE="contract-registry"


    if stoleus_contract_registry_import_definitions; then
        exit_code=0
    else
        exit_code=$?

        stoleus_kernel_record_bootstrap_failure \
            "contract-registry" \
            "$exit_code"

        return "$exit_code"
    fi


    STOLEUS_KERNEL_BOOTSTRAP_STAGE="plugins"


    if stoleus_plugin_activate; then
        exit_code=0
    else
        exit_code=$?

        stoleus_kernel_record_bootstrap_failure \
            "plugins" \
            "$exit_code"

        return "$exit_code"
    fi


    STOLEUS_KERNEL_BOOTSTRAP_STAGE="ready"
    STOLEUS_KERNEL_BOOTSTRAP_EXIT_CODE="0"

    STOLEUS_KERNEL_BOOTSTRAP_COMPLETED="true"
    STOLEUS_KERNEL_READY="true"


    return 0
}


# ==============================================================================
# stoleus_kernel_get_status
# ==============================================================================
#
# Output fields:
#
#     loaded
#     initialized
#     bootstrap-started
#     bootstrap-completed
#     ready
#     stage
#     bootstrap-exit-code
#     discovery-record-count
#     definition-count
#     registry-count
#     resolved-reference-count
#     plugin-manager-active
# ==============================================================================

stoleus_kernel_get_status() {

    local registry_count=0


    registry_count="$(
        stoleus_registry_get_count
    )" || return $?


    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${STOLEUS_KERNEL_LOADED:-false}" \
        "${STOLEUS_KERNEL_INITIALIZED:-false}" \
        "${STOLEUS_KERNEL_BOOTSTRAP_STARTED:-false}" \
        "${STOLEUS_KERNEL_BOOTSTRAP_COMPLETED:-false}" \
        "${STOLEUS_KERNEL_READY:-false}" \
        "${STOLEUS_KERNEL_BOOTSTRAP_STAGE:-not-started}" \
        "${STOLEUS_KERNEL_BOOTSTRAP_EXIT_CODE:-0}" \
        "${#STOLEUS_DISCOVERY_RECORD_PATHS[@]}" \
        "${#STOLEUS_DEFINITION_IDS[@]}" \
        "$registry_count" \
        "${#STOLEUS_RESOLVER_RESOLVED_IDS[@]}" \
        "${STOLEUS_PLUGIN_MANAGER_ACTIVE:-false}"

    return 0
}

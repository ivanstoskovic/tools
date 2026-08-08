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
source "${STOLEUS_KERNEL_ROOT}/context/context.sh"
source "${STOLEUS_KERNEL_ROOT}/platform/platform.sh"
source "${STOLEUS_KERNEL_ROOT}/metadata/collection.sh"
source "${STOLEUS_KERNEL_ROOT}/rollback/registry.sh"
source "${STOLEUS_KERNEL_ROOT}/rollback/plan.sh"
source "${STOLEUS_KERNEL_ROOT}/rollback/builder.sh"
source "${STOLEUS_KERNEL_ROOT}/rollback/planner.sh"
source "${STOLEUS_KERNEL_ROOT}/rollback/result_registry.sh"
source "${STOLEUS_KERNEL_ROOT}/rollback/executor.sh"
source "${STOLEUS_KERNEL_ROOT}/discovery/discovery.sh"
source "${STOLEUS_KERNEL_ROOT}/definition/definition.sh"
source "${STOLEUS_KERNEL_ROOT}/registry/registry.sh"
source "${STOLEUS_KERNEL_ROOT}/capability/registry.sh"
source "${STOLEUS_KERNEL_ROOT}/policy/provider_registry.sh"
source "${STOLEUS_KERNEL_ROOT}/policy/provider_trace.sh"
source "${STOLEUS_KERNEL_ROOT}/policy/provider_selection.sh"
source "${STOLEUS_KERNEL_ROOT}/capability/policy.sh"
source "${STOLEUS_KERNEL_ROOT}/capability/resolver.sh"
source "${STOLEUS_KERNEL_ROOT}/resolver/resolver.sh"
source "${STOLEUS_KERNEL_ROOT}/contract/definition.sh"
source "${STOLEUS_KERNEL_ROOT}/contract/registry.sh"
source "${STOLEUS_KERNEL_ROOT}/service/registry.sh"
source "${STOLEUS_KERNEL_ROOT}/service/resolver.sh"
source "${STOLEUS_KERNEL_ROOT}/composition/composition.sh"
source "${STOLEUS_KERNEL_ROOT}/service/runtime.sh"
source "${STOLEUS_KERNEL_ROOT}/plugin/plugin.sh"
source "${STOLEUS_KERNEL_ROOT}/planning/planning.sh"
source "${STOLEUS_KERNEL_ROOT}/lifecycle/lifecycle.sh"
source "${STOLEUS_KERNEL_ROOT}/execution/execution.sh"
source "${STOLEUS_KERNEL_ROOT}/execution/coordinator.sh"
source "${STOLEUS_KERNEL_ROOT}/api/api.sh"


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
    stoleus_context_initialize || return $?
    stoleus_platform_initialize || return $?
    stoleus_metadata_initialize || return $?
    stoleus_rollback_registry_initialize || return $?
    stoleus_rollback_plan_initialize || return $?
    stoleus_rollback_builder_initialize || return $?
    stoleus_rollback_planner_initialize || return $?
    stoleus_rollback_result_registry_initialize || return $?
    stoleus_rollback_executor_initialize || return $?
    stoleus_discovery_initialize || return $?
    stoleus_definition_initialize || return $?
    stoleus_registry_initialize || return $?
    stoleus_capability_registry_initialize || return $?
    stoleus_provider_policy_registry_initialize || return $?
    stoleus_provider_trace_initialize || return $?
    stoleus_provider_selection_initialize || return $?
    stoleus_capability_policy_initialize || return $?
    stoleus_capability_resolver_initialize || return $?
    stoleus_resolver_initialize || return $?
    stoleus_contract_definition_initialize || return $?
    stoleus_contract_registry_initialize || return $?
    stoleus_service_registry_initialize || return $?
    stoleus_service_resolver_initialize || return $?
    stoleus_composition_initialize || return $?
    stoleus_service_runtime_initialize || return $?
    stoleus_plugin_initialize || return $?
    stoleus_planning_initialize || return $?
    stoleus_lifecycle_initialize || return $?
    stoleus_execution_initialize || return $?
    stoleus_execution_coordinator_initialize || return $?
    stoleus_api_initialize || return $?


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

# ==============================================================================
# stoleus_kernel_bootstrap_platform_context
# ==============================================================================
#
# Purpose:
#     Execute automatic platform detection and publish detected facts into the
#     runtime context while preserving explicit context values.
# ==============================================================================

stoleus_kernel_bootstrap_platform_context() {

    stoleus_platform_detect || return $?

    stoleus_platform_apply_context \
        "preserve" ||
        return $?


    return 0
}


# ==============================================================================
# stoleus_kernel_run_bootstrap_stage
# ==============================================================================
#
# Arguments:
#
#     $1 = bootstrap stage name
#     $2 = stage function
#
# Responsibilities:
#
#     - update current bootstrap stage;
#     - invoke the stage function in the current shell;
#     - preserve state mutations performed by the stage;
#     - record a consistent bootstrap failure;
#     - return the stage's original exit code.
# ==============================================================================

stoleus_kernel_run_bootstrap_stage() {

    local stage_name="${1:-}"
    local stage_function="${2:-}"

    local exit_code=0


    if [[ -z "$stage_name" ||
          -z "$stage_function" ]]; then

        printf '%s\n' \
            "ERROR: Bootstrap stage execution requires stage name and function." \
            >&2

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if [[ ! "$stage_name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid bootstrap stage name: ${stage_name}" \
            >&2

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    if [[ ! "$stage_function" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid bootstrap stage function: ${stage_function}" \
            >&2

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    if ! declare -F "$stage_function" >/dev/null 2>&1; then

        printf '%s\n' \
            "ERROR: Bootstrap stage function is not loaded: ${stage_function}" \
            >&2

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    STOLEUS_KERNEL_BOOTSTRAP_STAGE="$stage_name"


    if "$stage_function"; then
        exit_code=0
    else
        exit_code=$?
    fi


    if (( exit_code == 0 )); then
        return 0
    fi


    stoleus_kernel_record_bootstrap_failure \
        "$stage_name" \
        "$exit_code"


    return "$exit_code"
}


# ==============================================================================
# stoleus_kernel_bootstrap
# ==============================================================================
#
# Bootstrap stages are declared as parallel local arrays. A stage at index N in
# STOLEUS_BOOTSTRAP_STAGE_NAMES is executed by the function at index N in
# STOLEUS_BOOTSTRAP_STAGE_FUNCTIONS.
#
# The arrays are local because one bootstrap execution owns the pipeline. The
# stage order remains deterministic and cannot be mutated externally.
# ==============================================================================

stoleus_kernel_bootstrap() {

    local stage_index=0

    local -a STOLEUS_BOOTSTRAP_STAGE_NAMES=(
        "initialize"
        "platform-context"
        "discover"
        "define"
        "register"
        "capability-registry"
        "capability-resolution"
        "resolve"
        "contracts"
        "contract-registry"
        "services"
        "service-resolution"
        "plugins"
    )

    local -a STOLEUS_BOOTSTRAP_STAGE_FUNCTIONS=(
        "stoleus_kernel_initialize"
        "stoleus_kernel_bootstrap_platform_context"
        "stoleus_discovery_scan"
        "stoleus_definition_build_all"
        "stoleus_registry_import_definitions"
        "stoleus_capability_registry_import_plugins"
        "stoleus_capability_resolver_validate_registry"
        "stoleus_resolver_validate_registry"
        "stoleus_contract_definition_build_all"
        "stoleus_contract_registry_import_definitions"
        "stoleus_service_registry_import_plugins"
        "stoleus_service_resolver_validate_registry"
        "stoleus_plugin_activate"
    )


    if stoleus_kernel_is_ready; then
        return 0
    fi


    if [[ "${STOLEUS_KERNEL_BOOTSTRAP_COMPLETED:-false}" == "true" ]] &&
       [[ "${STOLEUS_KERNEL_READY:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Kernel bootstrap previously failed at stage '${STOLEUS_KERNEL_BOOTSTRAP_STAGE}' with exit code ${STOLEUS_KERNEL_BOOTSTRAP_EXIT_CODE}." \
            >&2

        return "${STOLEUS_EXIT_CONFLICT:-8}"
    fi


    if [[ "${STOLEUS_KERNEL_BOOTSTRAP_STARTED:-false}" == "true" ]]; then

        printf '%s\n' \
            "ERROR: Kernel bootstrap is already in progress." >&2

        return "${STOLEUS_EXIT_CONFLICT:-8}"
    fi


    if (( ${#STOLEUS_BOOTSTRAP_STAGE_NAMES[@]} !=
          ${#STOLEUS_BOOTSTRAP_STAGE_FUNCTIONS[@]} )); then

        printf '%s\n' \
            "ERROR: Kernel bootstrap stage table is inconsistent." >&2

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    STOLEUS_KERNEL_BOOTSTRAP_STARTED="true"
    STOLEUS_KERNEL_BOOTSTRAP_STAGE="initialize"
    STOLEUS_KERNEL_BOOTSTRAP_EXIT_CODE="0"


    for stage_index in \
        "${!STOLEUS_BOOTSTRAP_STAGE_NAMES[@]}"; do

        stoleus_kernel_run_bootstrap_stage \
            "${STOLEUS_BOOTSTRAP_STAGE_NAMES[$stage_index]}" \
            "${STOLEUS_BOOTSTRAP_STAGE_FUNCTIONS[$stage_index]}" ||
            return $?
    done


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

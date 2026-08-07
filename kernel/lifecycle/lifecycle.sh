#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Lifecycle Subsystem
# ==============================================================================
#
# Purpose:
#     Load plugin implementations and invoke lifecycle entry points selected by
#     an immutable ExecutionPlan.
#
# Processing boundary:
#
#     ExecutionPlan step
#         ↓
#     Lifecycle Dispatcher
#         ↓
#     Plugin implementation loading
#         ↓
#     Lifecycle function invocation
#
# The Lifecycle subsystem does not:
#
#     - discover plugins;
#     - parse manifests;
#     - mutate Registry metadata;
#     - resolve dependencies;
#     - build plans;
#     - choose execution order.
#
# Public API:
#
#     stoleus_lifecycle_initialize
#     stoleus_lifecycle_load_plugin
#     stoleus_lifecycle_is_plugin_loaded
#     stoleus_lifecycle_invoke
#     stoleus_lifecycle_get_loaded
#     stoleus_lifecycle_reset
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_LIFECYCLE_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_LIFECYCLE_SUBSYSTEM_LOADED="true"


# ==============================================================================
# Loaded Implementation State
# ==============================================================================

declare -a STOLEUS_LIFECYCLE_LOADED_PLUGIN_IDS=()
declare -a STOLEUS_LIFECYCLE_LOADED_IMPLEMENTATIONS=()

declare -A STOLEUS_LIFECYCLE_LOADED_BY_ID=()


# ==============================================================================
# stoleus_lifecycle_reset
# ==============================================================================
#
# Purpose:
#     Clear Lifecycle bookkeeping.
#
# Important:
#
#     Bash cannot unload functions that were introduced by sourced plugin
#     implementations without tracking every function individually.
#
#     This reset clears framework bookkeeping only. Production execution should
#     normally use one kernel process per invocation.
# ==============================================================================

stoleus_lifecycle_reset() {

    STOLEUS_LIFECYCLE_LOADED_PLUGIN_IDS=()
    STOLEUS_LIFECYCLE_LOADED_IMPLEMENTATIONS=()
    STOLEUS_LIFECYCLE_LOADED_BY_ID=()


    return 0
}


# ==============================================================================
# stoleus_lifecycle_require_registry
# ==============================================================================

stoleus_lifecycle_require_registry() {

    if [[ "${STOLEUS_REGISTRY_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Registry must be initialized before lifecycle dispatch." \
            >&2

        return 6
    fi


    if ! stoleus_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Registry must be frozen before lifecycle dispatch." \
            >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_lifecycle_is_plugin_loaded
# ==============================================================================
#
# Arguments:
#
#     $1 = plugin ID
#
# Return codes:
#
#     0 = implementation loaded
#     1 = implementation not loaded
#     2 = plugin ID omitted
# ==============================================================================

stoleus_lifecycle_is_plugin_loaded() {

    local plugin_id="${1:-}"


    if [[ -z "$plugin_id" ]]; then
        return 2
    fi


    [[ -n "${STOLEUS_LIFECYCLE_LOADED_BY_ID[$plugin_id]+loaded}" ]]
}


# ==============================================================================
# stoleus_lifecycle_load_plugin
# ==============================================================================
#
# Purpose:
#     Load one plugin implementation exactly once in the current Bash process.
#
# Arguments:
#
#     $1 = plugin ID
#
# Loading an implementation does not invoke any lifecycle function.
# ==============================================================================

stoleus_lifecycle_load_plugin() {

    local plugin_id="${1:-}"
    local registry_index=""
    local implementation_path=""
    local loaded_position=0


    if [[ -z "$plugin_id" ]]; then

        printf '%s\n' \
            "ERROR: Lifecycle implementation loading requires a plugin ID." \
            >&2

        return 2
    fi


    stoleus_lifecycle_require_registry || return $?


    if stoleus_lifecycle_is_plugin_loaded "$plugin_id"; then
        return 0
    fi


    registry_index="$(
        stoleus_registry_get_index "$plugin_id"
    )" || return $?


    implementation_path="$(
        stoleus_registry_get_field_by_index \
            "$registry_index" \
            "implementation"
    )" || return $?


    if [[ -z "$implementation_path" || ! -f "$implementation_path" ]]; then

        printf '%s\n' \
            "ERROR: Plugin '${plugin_id}' implementation file is unavailable: ${implementation_path}" \
            >&2

        return 6
    fi


    source "$implementation_path"


    loaded_position="${#STOLEUS_LIFECYCLE_LOADED_PLUGIN_IDS[@]}"

    STOLEUS_LIFECYCLE_LOADED_PLUGIN_IDS+=("$plugin_id")
    STOLEUS_LIFECYCLE_LOADED_IMPLEMENTATIONS+=("$implementation_path")
    STOLEUS_LIFECYCLE_LOADED_BY_ID["$plugin_id"]="$loaded_position"


    return 0
}


# ==============================================================================
# stoleus_lifecycle_validate_plan_reference
# ==============================================================================
#
# Purpose:
#     Verify that a plan's lifecycle function still matches immutable Registry
#     metadata.
#
# Arguments:
#
#     $1 = Registry index
#     $2 = lifecycle stage
#     $3 = planned function reference
#
# This prevents corrupted or manually modified plans from invoking an unrelated
# function.
# ==============================================================================

stoleus_lifecycle_validate_plan_reference() {

    local registry_index="${1:-}"
    local lifecycle_stage="${2:-}"
    local planned_function="${3:-}"

    local registered_function=""


    if [[ -z "$registry_index" ||
          ! "$registry_index" =~ ^[0-9]+$ ||
          -z "$lifecycle_stage" ||
          -z "$planned_function" ]]; then

        printf '%s\n' \
            "ERROR: Lifecycle plan-reference validation received incomplete input." \
            >&2

        return 2
    fi


    registered_function="$(
        stoleus_planning_get_lifecycle_function \
            "$registry_index" \
            "$lifecycle_stage"
    )" || return $?


    if [[ -z "$registered_function" ]]; then

        printf '%s\n' \
            "ERROR: Registry does not expose lifecycle stage '${lifecycle_stage}' at index ${registry_index}." \
            >&2

        return 6
    fi


    if [[ "$registered_function" != "$planned_function" ]]; then

        printf '%s\n' \
            "ERROR: ExecutionPlan lifecycle reference does not match Registry metadata: ${planned_function}" \
            >&2

        return 8
    fi


    return 0
}


# ==============================================================================
# stoleus_lifecycle_invoke_function
# ==============================================================================
#
# Purpose:
#     Safely invoke an arbitrary function from a registered plugin
#     implementation.
#
# Arguments:
#
#     $1 = plugin ID
#     $2 = Registry index
#     $3 = function reference
#     $4... = optional function arguments
#
# Unlike stoleus_lifecycle_invoke, this helper does not require the function to
# match a standard lifecycle stage. It is intended for validated internal
# operations such as compensating rollback actions.
# ==============================================================================

stoleus_lifecycle_invoke_function() {

    local plugin_id="${1:-}"
    local registry_index="${2:-}"
    local function_reference="${3:-}"

    local registered_plugin_id=""


    if [[ -z "$plugin_id" ||
          -z "$registry_index" ||
          ! "$registry_index" =~ ^[0-9]+$ ||
          -z "$function_reference" ]]; then

        printf '%s\n' \
            "ERROR: Generic lifecycle invocation requires plugin ID, Registry index, and function reference." \
            >&2

        return 2
    fi


    if [[ ! "$function_reference" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid generic lifecycle function reference: ${function_reference}" \
            >&2

        return 6
    fi


    shift 3


    stoleus_lifecycle_require_registry || return $?


    registered_plugin_id="$(
        stoleus_registry_get_id_by_index \
            "$registry_index"
    )" || return $?


    if [[ "$registered_plugin_id" != "$plugin_id" ]]; then

        printf '%s\n' \
            "ERROR: Generic lifecycle plugin ID and Registry index do not match: ${plugin_id}" \
            >&2

        return 8
    fi


    stoleus_lifecycle_load_plugin \
        "$plugin_id" ||
        return $?


    if ! declare -F "$function_reference" >/dev/null 2>&1; then

        printf '%s\n' \
            "ERROR: Plugin '${plugin_id}' implementation does not define function: ${function_reference}" \
            >&2

        return 6
    fi


    "$function_reference" "$@"

    return $?
}


# ==============================================================================
# stoleus_lifecycle_invoke
# ==============================================================================
#
# Purpose:
#     Invoke one lifecycle function selected by an ExecutionPlan step.
#
# Arguments:
#
#     $1 = plugin ID
#     $2 = Registry index
#     $3 = lifecycle stage
#     $4 = lifecycle function reference
#     remaining arguments = optional ExecutionRequest arguments
#
# Return:
#
#     The exact return code produced by the lifecycle implementation.
# ==============================================================================

stoleus_lifecycle_invoke() {

    local plugin_id="${1:-}"
    local registry_index="${2:-}"
    local lifecycle_stage="${3:-}"
    local lifecycle_function="${4:-}"

    local registered_plugin_id=""


    if [[ -z "$plugin_id" ||
          -z "$registry_index" ||
          -z "$lifecycle_stage" ||
          -z "$lifecycle_function" ]]; then

        printf '%s\n' \
            "ERROR: Lifecycle invocation received incomplete plan-step metadata." \
            >&2

        return 2
    fi


    shift 4


    stoleus_lifecycle_require_registry || return $?


    registered_plugin_id="$(
        stoleus_registry_get_id_by_index \
            "$registry_index"
    )" || return $?


    if [[ "$registered_plugin_id" != "$plugin_id" ]]; then

        printf '%s\n' \
            "ERROR: ExecutionPlan plugin ID and Registry index do not match: ${plugin_id}" \
            >&2

        return 8
    fi


    stoleus_lifecycle_validate_plan_reference \
        "$registry_index" \
        "$lifecycle_stage" \
        "$lifecycle_function" ||
        return $?


    stoleus_lifecycle_load_plugin \
        "$plugin_id" ||
        return $?


    if ! declare -F "$lifecycle_function" >/dev/null 2>&1; then

        printf '%s\n' \
            "ERROR: Plugin '${plugin_id}' implementation does not define lifecycle function: ${lifecycle_function}" \
            >&2

        return 6
    fi


    "$lifecycle_function" "$@"

    return $?
}


# ==============================================================================
# stoleus_lifecycle_get_loaded
# ==============================================================================
#
# Output format:
#
#     plugin-id<TAB>implementation-path
# ==============================================================================

stoleus_lifecycle_get_loaded() {

    local loaded_position=0


    for loaded_position in "${!STOLEUS_LIFECYCLE_LOADED_PLUGIN_IDS[@]}"; do

        printf '%s\t%s\n' \
            "${STOLEUS_LIFECYCLE_LOADED_PLUGIN_IDS[$loaded_position]}" \
            "${STOLEUS_LIFECYCLE_LOADED_IMPLEMENTATIONS[$loaded_position]}"
    done


    return 0
}


# ==============================================================================
# stoleus_lifecycle_initialize
# ==============================================================================

stoleus_lifecycle_initialize() {

    if [[ "${STOLEUS_LIFECYCLE_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_lifecycle_reset || return $?


    STOLEUS_LIFECYCLE_INITIALIZED="true"

    return 0
}

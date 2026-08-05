#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Planning Subsystem
# ==============================================================================
#
# Purpose:
#     Convert one ExecutionRequest into an immutable ExecutionPlan.
#
# Processing flow:
#
#     ExecutionRequest
#         ↓
#     Target validation
#         ↓
#     Dependency expansion
#         ↓
#     Cycle detection
#         ↓
#     Deterministic dependency-first ordering
#         ↓
#     Lifecycle-stage expansion
#         ↓
#     Immutable ExecutionPlan
#
# Planning reads only immutable Registry metadata and Resolver APIs.
#
# Planning does not:
#
#     - discover plugins;
#     - parse manifests;
#     - modify Registry metadata;
#     - load plugin implementations;
#     - invoke lifecycle functions;
#     - modify infrastructure.
#
# Supported operations:
#
#     setup
#         Expand dependencies and add each available lifecycle stage in this
#         order:
#
#             install
#             configure
#             verify
#
#     install
#         Expand dependencies and add the install stage.
#
#     configure
#         Expand dependencies and add the configure stage.
#
#     verify
#         Expand dependencies and add the verify stage.
#
#     upgrade
#         Expand dependencies and add:
#
#             upgrade
#             verify
#
#     remove
#         Add only the requested plugin's remove stage.
#
#         Dependencies are deliberately not removed automatically because they
#         may be shared by other installed plugins.
#
# Public API:
#
#     stoleus_planning_initialize
#     stoleus_planning_create_request
#     stoleus_planning_build_plan
#     stoleus_planning_get_request
#     stoleus_planning_get_plugins
#     stoleus_planning_get_steps
#     stoleus_planning_is_plan_frozen
#     stoleus_planning_reset
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_PLANNING_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_PLANNING_SUBSYSTEM_LOADED="true"


# ==============================================================================
# ExecutionRequest State
# ==============================================================================

STOLEUS_PLANNING_REQUEST_TARGET=""
STOLEUS_PLANNING_REQUEST_OPERATION=""

declare -a STOLEUS_PLANNING_REQUEST_ARGUMENTS=()


# ==============================================================================
# Dependency-Traversal State
# ==============================================================================

declare -A STOLEUS_PLANNING_VISITING=()
declare -A STOLEUS_PLANNING_RESOLVED=()

declare -a STOLEUS_PLANNING_TRAVERSAL_STACK=()
declare -a STOLEUS_PLANNING_PLUGIN_ORDER=()


# ==============================================================================
# ExecutionPlan State
# ==============================================================================
#
# All step arrays use the same numeric index.
#
# A plan step contains:
#
#     plugin ID
#     Registry index
#     lifecycle stage
#     lifecycle function reference
#     whether the step receives ExecutionRequest arguments
# ==============================================================================

declare -a STOLEUS_PLAN_STEP_PLUGIN_IDS=()
declare -a STOLEUS_PLAN_STEP_REGISTRY_INDEXES=()
declare -a STOLEUS_PLAN_STEP_STAGES=()
declare -a STOLEUS_PLAN_STEP_FUNCTIONS=()
declare -a STOLEUS_PLAN_STEP_RECEIVES_ARGUMENTS=()


# ==============================================================================
# stoleus_planning_is_plan_frozen
# ==============================================================================

stoleus_planning_is_plan_frozen() {

    [[ "${STOLEUS_PLAN_FROZEN:-false}" == "true" ]]
}


# ==============================================================================
# stoleus_planning_reset_plan
# ==============================================================================
#
# Purpose:
#     Clear dependency traversal and ExecutionPlan state.
#
# The current ExecutionRequest is preserved.
# ==============================================================================

stoleus_planning_reset_plan() {

    STOLEUS_PLANNING_VISITING=()
    STOLEUS_PLANNING_RESOLVED=()

    STOLEUS_PLANNING_TRAVERSAL_STACK=()
    STOLEUS_PLANNING_PLUGIN_ORDER=()

    STOLEUS_PLAN_STEP_PLUGIN_IDS=()
    STOLEUS_PLAN_STEP_REGISTRY_INDEXES=()
    STOLEUS_PLAN_STEP_STAGES=()
    STOLEUS_PLAN_STEP_FUNCTIONS=()
    STOLEUS_PLAN_STEP_RECEIVES_ARGUMENTS=()

    STOLEUS_PLAN_FROZEN="false"


    return 0
}


# ==============================================================================
# stoleus_planning_reset
# ==============================================================================
#
# Purpose:
#     Clear the ExecutionRequest and ExecutionPlan.
#
# Intended usage:
#
#     - tests;
#     - development tooling;
#     - preparation for a new request in the same process.
# ==============================================================================

stoleus_planning_reset() {

    STOLEUS_PLANNING_REQUEST_TARGET=""
    STOLEUS_PLANNING_REQUEST_OPERATION=""
    STOLEUS_PLANNING_REQUEST_ARGUMENTS=()

    stoleus_planning_reset_plan || return $?


    return 0
}


# ==============================================================================
# stoleus_planning_validate_operation
# ==============================================================================

stoleus_planning_validate_operation() {

    local operation="${1:-}"


    case "$operation" in

        setup|install|configure|verify|upgrade|remove)
            return 0
            ;;

        "")

            printf '%s\n' \
                "ERROR: ExecutionRequest requires an operation." >&2

            return 2

            ;;

        *)

            printf '%s\n' \
                "ERROR: Unsupported execution operation: $operation" >&2

            return 2

            ;;
    esac
}


# ==============================================================================
# stoleus_planning_create_request
# ==============================================================================
#
# Purpose:
#     Create one immutable input request for Planning.
#
# Arguments:
#
#     $1 = target plugin ID
#     $2 = requested operation
#     remaining arguments = plugin-specific arguments
#
# Example:
#
#     stoleus_planning_create_request \
#         "server" \
#         "setup" \
#         "stage"
#
# Only one request may exist at a time. Call stoleus_planning_reset() before
# creating another request.
# ==============================================================================

stoleus_planning_create_request() {

    local target_plugin="${1:-}"
    local operation="${2:-}"


    if [[ "${STOLEUS_PLANNING_REQUEST_CREATED:-false}" == "true" ]]; then

        printf '%s\n' \
            "ERROR: An ExecutionRequest already exists. Reset Planning before creating another request." \
            >&2

        return 8
    fi


    if [[ -z "$target_plugin" ]]; then

        printf '%s\n' \
            "ERROR: ExecutionRequest requires a target plugin." >&2

        return 2
    fi


    if [[ ! "$target_plugin" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid ExecutionRequest target plugin: $target_plugin" \
            >&2

        return 6
    fi


    stoleus_planning_validate_operation \
        "$operation" ||
        return $?


    shift 2


    STOLEUS_PLANNING_REQUEST_TARGET="$target_plugin"
    STOLEUS_PLANNING_REQUEST_OPERATION="$operation"
    STOLEUS_PLANNING_REQUEST_ARGUMENTS=("$@")

    STOLEUS_PLANNING_REQUEST_CREATED="true"


    return 0
}


# ==============================================================================
# stoleus_planning_get_request
# ==============================================================================
#
# Output format:
#
#     target<TAB>operation<TAB>argument-count
# ==============================================================================

stoleus_planning_get_request() {

    if [[ "${STOLEUS_PLANNING_REQUEST_CREATED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: No ExecutionRequest has been created." >&2

        return 6
    fi


    printf '%s\t%s\t%s\n' \
        "$STOLEUS_PLANNING_REQUEST_TARGET" \
        "$STOLEUS_PLANNING_REQUEST_OPERATION" \
        "${#STOLEUS_PLANNING_REQUEST_ARGUMENTS[@]}"

    return 0
}


# ==============================================================================
# stoleus_planning_require_registry
# ==============================================================================

stoleus_planning_require_registry() {

    if [[ "${STOLEUS_RESOLVER_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Resolver must be initialized before Planning." >&2

        return 6
    fi


    stoleus_resolver_require_registry || return $?


    if [[ "${STOLEUS_RESOLVER_VALIDATED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Registry references must be validated before Planning." \
            >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_planning_get_lifecycle_function
# ==============================================================================
#
# Purpose:
#     Return the lifecycle function reference for one Registry plugin.
#
# Arguments:
#
#     $1 = Registry index
#     $2 = lifecycle stage
# ==============================================================================

stoleus_planning_get_lifecycle_function() {

    local registry_index="${1:-}"
    local lifecycle_stage="${2:-}"


    if [[ -z "$registry_index" ||
          ! "$registry_index" =~ ^[0-9]+$ ||
          -z "$lifecycle_stage" ]]; then

        printf '%s\n' \
            "ERROR: Lifecycle lookup requires Registry index and stage." \
            >&2

        return 2
    fi


    case "$lifecycle_stage" in

        install|configure|verify|upgrade|remove)

            stoleus_registry_get_field_by_index \
                "$registry_index" \
                "$lifecycle_stage"

            return $?

            ;;

        *)

            printf '%s\n' \
                "ERROR: Unsupported lifecycle stage: $lifecycle_stage" >&2

            return 2

            ;;
    esac
}


# ==============================================================================
# stoleus_planning_validate_target_operation
# ==============================================================================
#
# Purpose:
#     Verify that the requested target exposes the requested operation.
#
# Setup is valid when the target exposes at least one of:
#
#     install
#     configure
#     verify
#
# Upgrade is valid when the target exposes upgrade.
#
# Verify is not required for upgrade, but is added afterward when available.
# ==============================================================================

stoleus_planning_validate_target_operation() {

    local target_plugin="$STOLEUS_PLANNING_REQUEST_TARGET"
    local operation="$STOLEUS_PLANNING_REQUEST_OPERATION"

    local registry_index=""
    local lifecycle_function=""

    local install_function=""
    local configure_function=""
    local verify_function=""


    registry_index="$(
        stoleus_registry_get_index "$target_plugin"
    )" || return $?


    case "$operation" in

        setup)

            install_function="$(
                stoleus_planning_get_lifecycle_function \
                    "$registry_index" \
                    "install"
            )" || return $?


            configure_function="$(
                stoleus_planning_get_lifecycle_function \
                    "$registry_index" \
                    "configure"
            )" || return $?


            verify_function="$(
                stoleus_planning_get_lifecycle_function \
                    "$registry_index" \
                    "verify"
            )" || return $?


            if [[ -z "$install_function" &&
                  -z "$configure_function" &&
                  -z "$verify_function" ]]; then

                printf '%s\n' \
                    "ERROR: Target plugin '${target_plugin}' does not support setup." \
                    >&2

                return 6
            fi

            ;;


        install|configure|verify|upgrade|remove)

            lifecycle_function="$(
                stoleus_planning_get_lifecycle_function \
                    "$registry_index" \
                    "$operation"
            )" || return $?


            if [[ -z "$lifecycle_function" ]]; then

                printf '%s\n' \
                    "ERROR: Target plugin '${target_plugin}' does not support operation '${operation}'." \
                    >&2

                return 6
            fi

            ;;
    esac


    return 0
}


# ==============================================================================
# stoleus_planning_format_cycle
# ==============================================================================
#
# Purpose:
#     Format the current traversal path for a cycle diagnostic.
# ==============================================================================

stoleus_planning_format_cycle() {

    local repeated_plugin="${1:-}"
    local plugin_id=""
    local include="false"
    local result=""


    for plugin_id in "${STOLEUS_PLANNING_TRAVERSAL_STACK[@]}"; do

        if [[ "$plugin_id" == "$repeated_plugin" ]]; then
            include="true"
        fi


        if [[ "$include" == "true" ]]; then

            if [[ -n "$result" ]]; then
                result+=" -> "
            fi

            result+="$plugin_id"
        fi
    done


    if [[ -n "$result" ]]; then
        result+=" -> ${repeated_plugin}"
    else
        result="$repeated_plugin"
    fi


    printf '%s' "$result"

    return 0
}


# ==============================================================================
# stoleus_planning_resolve_node
# ==============================================================================
#
# Purpose:
#     Recursively add one plugin and its dependencies to dependency-first order.
#
# Arguments:
#
#     $1 = plugin ID
#
# Algorithm:
#
#     Depth-first traversal with:
#
#         visiting
#             currently in the active recursion path;
#
#         resolved
#             plugin and complete dependency subtree already ordered.
# ==============================================================================

stoleus_planning_resolve_node() {

    local plugin_id="${1:-}"
    local registry_index=""
    local dependency_list=""
    local dependency_id=""
    local cycle_path=""


    if [[ -z "$plugin_id" ]]; then

        printf '%s\n' \
            "ERROR: Dependency traversal requires a plugin ID." >&2

        return 2
    fi


    if [[ -n "${STOLEUS_PLANNING_RESOLVED[$plugin_id]+resolved}" ]]; then
        return 0
    fi


    if [[ -n "${STOLEUS_PLANNING_VISITING[$plugin_id]+visiting}" ]]; then

        cycle_path="$(
            stoleus_planning_format_cycle "$plugin_id"
        )"


        printf '%s\n' \
            "ERROR: Circular plugin dependency detected: ${cycle_path}" \
            >&2

        return 8
    fi


    registry_index="$(
        stoleus_registry_get_index "$plugin_id"
    )" || return $?


    STOLEUS_PLANNING_VISITING["$plugin_id"]="true"
    STOLEUS_PLANNING_TRAVERSAL_STACK+=("$plugin_id")


    dependency_list="$(
        stoleus_registry_get_field_by_index \
            "$registry_index" \
            "dependencies"
    )" || return $?


    while IFS= read -r dependency_id; do

        [[ -z "$dependency_id" ]] && continue


        stoleus_planning_resolve_node \
            "$dependency_id" ||
            return $?

    done < <(
        stoleus_resolver_parse_reference_list \
            "$dependency_list"
    )


    unset 'STOLEUS_PLANNING_VISITING[$plugin_id]'

    unset \
        'STOLEUS_PLANNING_TRAVERSAL_STACK[${#STOLEUS_PLANNING_TRAVERSAL_STACK[@]}-1]'


    STOLEUS_PLANNING_RESOLVED["$plugin_id"]="true"
    STOLEUS_PLANNING_PLUGIN_ORDER+=("$plugin_id")


    return 0
}


# ==============================================================================
# stoleus_planning_add_step
# ==============================================================================
#
# Purpose:
#     Append one lifecycle step when its function exists.
#
# Arguments:
#
#     $1 = plugin ID
#     $2 = lifecycle stage
#     $3 = receives request arguments: true or false
#
# Missing optional lifecycle functions are skipped.
# ==============================================================================

stoleus_planning_add_step() {

    local plugin_id="${1:-}"
    local lifecycle_stage="${2:-}"
    local receives_arguments="${3:-false}"

    local registry_index=""
    local lifecycle_function=""


    registry_index="$(
        stoleus_registry_get_index "$plugin_id"
    )" || return $?


    lifecycle_function="$(
        stoleus_planning_get_lifecycle_function \
            "$registry_index" \
            "$lifecycle_stage"
    )" || return $?


    if [[ -z "$lifecycle_function" ]]; then
        return 0
    fi


    STOLEUS_PLAN_STEP_PLUGIN_IDS+=("$plugin_id")
    STOLEUS_PLAN_STEP_REGISTRY_INDEXES+=("$registry_index")
    STOLEUS_PLAN_STEP_STAGES+=("$lifecycle_stage")
    STOLEUS_PLAN_STEP_FUNCTIONS+=("$lifecycle_function")
    STOLEUS_PLAN_STEP_RECEIVES_ARGUMENTS+=("$receives_arguments")


    return 0
}


# ==============================================================================
# stoleus_planning_expand_plugin_lifecycle
# ==============================================================================
#
# Purpose:
#     Expand one ordered plugin into lifecycle plan steps.
#
# Arguments:
#
#     $1 = plugin ID
# ==============================================================================

stoleus_planning_expand_plugin_lifecycle() {

    local plugin_id="${1:-}"
    local operation="$STOLEUS_PLANNING_REQUEST_OPERATION"
    local receives_arguments="false"


    if [[ "$plugin_id" == "$STOLEUS_PLANNING_REQUEST_TARGET" ]]; then
        receives_arguments="true"
    fi


    case "$operation" in

        setup)

            stoleus_planning_add_step \
                "$plugin_id" \
                "install" \
                "$receives_arguments" ||
                return $?


            stoleus_planning_add_step \
                "$plugin_id" \
                "configure" \
                "$receives_arguments" ||
                return $?


            stoleus_planning_add_step \
                "$plugin_id" \
                "verify" \
                "$receives_arguments" ||
                return $?

            ;;


        install|configure|verify)

            stoleus_planning_add_step \
                "$plugin_id" \
                "$operation" \
                "$receives_arguments" ||
                return $?

            ;;


        upgrade)

            stoleus_planning_add_step \
                "$plugin_id" \
                "upgrade" \
                "$receives_arguments" ||
                return $?


            stoleus_planning_add_step \
                "$plugin_id" \
                "verify" \
                "$receives_arguments" ||
                return $?

            ;;


        remove)

            stoleus_planning_add_step \
                "$plugin_id" \
                "remove" \
                "$receives_arguments" ||
                return $?

            ;;
    esac


    return 0
}


# ==============================================================================
# stoleus_planning_build_plan
# ==============================================================================
#
# Purpose:
#     Build and freeze the complete ExecutionPlan.
# ==============================================================================

stoleus_planning_build_plan() {

    local plugin_id=""


    if [[ "${STOLEUS_PLANNING_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Planning must be initialized before building a plan." \
            >&2

        return 6
    fi


    if [[ "${STOLEUS_PLANNING_REQUEST_CREATED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: An ExecutionRequest must be created before Planning." \
            >&2

        return 6
    fi


    if stoleus_planning_is_plan_frozen; then
        return 0
    fi


    stoleus_planning_require_registry || return $?
    stoleus_planning_validate_target_operation || return $?

    stoleus_planning_reset_plan || return $?


    if [[ "$STOLEUS_PLANNING_REQUEST_OPERATION" == "remove" ]]; then

        # ----------------------------------------------------------------------
        # Safe removal default:
        #
        # Remove only the explicitly requested plugin. Shared dependencies are
        # never removed implicitly.
        # ----------------------------------------------------------------------
        STOLEUS_PLANNING_PLUGIN_ORDER+=(
            "$STOLEUS_PLANNING_REQUEST_TARGET"
        )

    else

        stoleus_planning_resolve_node \
            "$STOLEUS_PLANNING_REQUEST_TARGET" ||
            return $?
    fi


    for plugin_id in "${STOLEUS_PLANNING_PLUGIN_ORDER[@]}"; do

        stoleus_planning_expand_plugin_lifecycle \
            "$plugin_id" ||
            return $?
    done


    if (( ${#STOLEUS_PLAN_STEP_PLUGIN_IDS[@]} == 0 )); then

        printf '%s\n' \
            "ERROR: Planning produced an empty ExecutionPlan." >&2

        return 6
    fi


    STOLEUS_PLAN_FROZEN="true"

    return 0
}


# ==============================================================================
# stoleus_planning_get_plugins
# ==============================================================================
#
# Output:
#
#     Dependency-first plugin IDs, one per line.
# ==============================================================================

stoleus_planning_get_plugins() {

    local plugin_id=""


    for plugin_id in "${STOLEUS_PLANNING_PLUGIN_ORDER[@]}"; do
        printf '%s\n' "$plugin_id"
    done


    return 0
}


# ==============================================================================
# stoleus_planning_get_steps
# ==============================================================================
#
# Output format:
#
#     step-number
#     plugin-id
#     registry-index
#     lifecycle-stage
#     lifecycle-function
#     receives-request-arguments
#
# Fields are separated by tabs.
# ==============================================================================

stoleus_planning_get_steps() {

    local step_index=0


    for step_index in "${!STOLEUS_PLAN_STEP_PLUGIN_IDS[@]}"; do

        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$((step_index + 1))" \
            "${STOLEUS_PLAN_STEP_PLUGIN_IDS[$step_index]}" \
            "${STOLEUS_PLAN_STEP_REGISTRY_INDEXES[$step_index]}" \
            "${STOLEUS_PLAN_STEP_STAGES[$step_index]}" \
            "${STOLEUS_PLAN_STEP_FUNCTIONS[$step_index]}" \
            "${STOLEUS_PLAN_STEP_RECEIVES_ARGUMENTS[$step_index]}"
    done


    return 0
}


# ==============================================================================
# stoleus_planning_initialize
# ==============================================================================

stoleus_planning_initialize() {

    if [[ "${STOLEUS_PLANNING_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_planning_reset || return $?

    STOLEUS_PLANNING_REQUEST_CREATED="false"
    STOLEUS_PLANNING_INITIALIZED="true"


    return 0
}

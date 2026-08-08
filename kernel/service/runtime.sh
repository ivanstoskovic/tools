#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Service Invocation Runtime
# ==============================================================================
#
# Purpose:
#     Invoke one contract operation through the provider selected by the
#     Service Provider Resolver.
#
# Invocation flow:
#
#     service ID + operation ID
#         ↓
#     resolve provider in the current shell
#         ↓
#     obtain provider plugin ID
#         ↓
#     obtain operation-function binding
#         ↓
#     load provider implementation through Lifecycle
#         ↓
#     invoke bound function with caller arguments
#
# Public API:
#
#     stoleus_service_runtime_initialize
#     stoleus_service_call
#     stoleus_service_get_provider
#     stoleus_service_get_operation
#     stoleus_service_runtime_get_last_call
#     stoleus_service_runtime_reset
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_SERVICE_RUNTIME_SUBSYSTEM_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_SERVICE_RUNTIME_SUBSYSTEM_LOADED="true"


# ==============================================================================
# Runtime State
# ==============================================================================

STOLEUS_SERVICE_LAST_SERVICE_ID=""
STOLEUS_SERVICE_LAST_OPERATION_ID=""
STOLEUS_SERVICE_LAST_PROVIDER_PLUGIN_ID=""
STOLEUS_SERVICE_LAST_FUNCTION=""
STOLEUS_SERVICE_LAST_EXIT_CODE="0"


# ==============================================================================
# stoleus_service_runtime_reset
# ==============================================================================

stoleus_service_runtime_reset() {

    STOLEUS_SERVICE_LAST_SERVICE_ID=""
    STOLEUS_SERVICE_LAST_OPERATION_ID=""
    STOLEUS_SERVICE_LAST_PROVIDER_PLUGIN_ID=""
    STOLEUS_SERVICE_LAST_FUNCTION=""
    STOLEUS_SERVICE_LAST_EXIT_CODE="0"


    return 0
}


# ==============================================================================
# stoleus_service_runtime_require_ready
# ==============================================================================

stoleus_service_runtime_require_ready() {

    if [[ "${STOLEUS_SERVICE_RUNTIME_INITIALIZED:-false}" != "true" ]]; then

        printf '%s\n' \
            "ERROR: Service Invocation Runtime must be initialized before use." \
            >&2

        return 6
    fi


    if ! stoleus_contract_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Service invocation requires a frozen Contract Registry." \
            >&2

        return 6
    fi


    if ! stoleus_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Service invocation requires a frozen Plugin Registry." \
            >&2

        return 6
    fi


    if ! stoleus_service_registry_is_frozen; then

        printf '%s\n' \
            "ERROR: Service invocation requires a frozen Service Registry." \
            >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_service_validate_request
# ==============================================================================

stoleus_service_validate_request() {

    local service_id="${1:-}"
    local operation_id="${2:-}"


    if [[ -z "$service_id" || -z "$operation_id" ]]; then

        printf '%s\n' \
            "ERROR: Service invocation requires service ID and operation ID." \
            >&2

        return 2
    fi


    if [[ ! "$service_id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid service ID: ${service_id}" >&2

        return 6
    fi


    if [[ ! "$operation_id" =~ ^[a-z][a-z0-9-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Invalid service operation ID: ${operation_id}" >&2

        return 6
    fi


    if ! stoleus_contract_registry_contains "$service_id"; then

        printf '%s\n' \
            "ERROR: Unknown service contract: ${service_id}" >&2

        return 6
    fi


    return 0
}


# ==============================================================================
# stoleus_service_get_provider
# ==============================================================================
#
# Purpose:
#     Resolve a service in the current shell and return only the selected
#     provider plugin ID.
#
# This function may populate the resolver cache and therefore must not perform
# its initial resolution through command substitution.
# ==============================================================================

stoleus_service_get_provider() {

    local service_id="${1:-}"


    if [[ -z "$service_id" ]]; then

        printf '%s\n' \
            "ERROR: Service provider lookup requires a service ID." >&2

        return 2
    fi


    stoleus_service_runtime_require_ready || return $?


    if ! stoleus_service_resolver_is_resolved "$service_id"; then

        stoleus_service_resolver_resolve \
            "$service_id" \
            >/dev/null ||
            return $?
    fi


    stoleus_service_resolver_get_provider_plugin \
        "$service_id"

    return $?
}


# ==============================================================================
# stoleus_service_get_operation
# ==============================================================================
#
# Purpose:
#     Resolve a service and return the selected provider function for one
#     contract operation.
#
# Output:
#
#     function-name
# ==============================================================================

stoleus_service_get_operation() {

    local service_id="${1:-}"
    local operation_id="${2:-}"

    local provider_plugin_id=""


    stoleus_service_validate_request \
        "$service_id" \
        "$operation_id" ||
        return $?


    stoleus_service_runtime_require_ready || return $?


    if ! stoleus_service_resolver_is_resolved "$service_id"; then

        stoleus_service_resolver_resolve \
            "$service_id" \
            >/dev/null ||
            return $?
    fi


    provider_plugin_id="$(
        stoleus_service_resolver_get_provider_plugin \
            "$service_id"
    )" || return $?


    stoleus_service_registry_get_operation_binding \
        "$service_id" \
        "$provider_plugin_id" \
        "$operation_id"

    return $?
}


# ==============================================================================
# stoleus_service_call
# ==============================================================================
#
# Arguments:
#
#     $1 = service ID
#     $2 = operation ID
#     remaining arguments = provider-operation arguments
#
# Return value:
#
#     The selected provider function's exit code.
#
# Provider stdout and stderr are preserved.
# ==============================================================================

stoleus_service_call() {

    local service_id="${1:-}"
    local operation_id="${2:-}"

    local provider_plugin_id=""
    local operation_function=""
    local exit_code=0


    stoleus_service_validate_request \
        "$service_id" \
        "$operation_id" ||
        return $?


    stoleus_service_runtime_require_ready || return $?


    shift 2


    # --------------------------------------------------------------------------
    # Resolve in the current shell.
    #
    # Do not put this call inside $(...), because resolution mutates the
    # provider cache.
    # --------------------------------------------------------------------------
    if ! stoleus_service_resolver_is_resolved "$service_id"; then

        stoleus_service_resolver_resolve \
            "$service_id" \
            >/dev/null ||
            return $?
    fi


    # --------------------------------------------------------------------------
    # Queries are now safe because the provider is already cached.
    # --------------------------------------------------------------------------
    provider_plugin_id="$(
        stoleus_service_resolver_get_provider_plugin \
            "$service_id"
    )" || return $?


    operation_function="$(
        stoleus_service_registry_get_operation_binding \
            "$service_id" \
            "$provider_plugin_id" \
            "$operation_id"
    )" || return $?


    # --------------------------------------------------------------------------
    # Load the provider implementation through the existing Lifecycle loader.
    # --------------------------------------------------------------------------
    stoleus_lifecycle_load_plugin \
        "$provider_plugin_id" ||
        return $?


    if ! declare -F "$operation_function" >/dev/null 2>&1; then

        printf '%s\n' \
            "ERROR: Provider '${provider_plugin_id}' does not define bound function '${operation_function}' for ${service_id}.${operation_id}." \
            >&2

        return 6
    fi


    STOLEUS_SERVICE_LAST_SERVICE_ID="$service_id"
    STOLEUS_SERVICE_LAST_OPERATION_ID="$operation_id"
    STOLEUS_SERVICE_LAST_PROVIDER_PLUGIN_ID="$provider_plugin_id"
    STOLEUS_SERVICE_LAST_FUNCTION="$operation_function"


    if "$operation_function" "$@"; then
        exit_code=0
    else
        exit_code=$?
    fi


    STOLEUS_SERVICE_LAST_EXIT_CODE="$exit_code"


    return "$exit_code"
}


# ==============================================================================
# stoleus_service_runtime_get_last_call
# ==============================================================================
#
# Output:
#
#     service-id<TAB>operation-id<TAB>provider-plugin-id<TAB>function<TAB>exit-code
# ==============================================================================

stoleus_service_runtime_get_last_call() {

    if [[ -z "$STOLEUS_SERVICE_LAST_SERVICE_ID" ]]; then
        return 0
    fi


    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$STOLEUS_SERVICE_LAST_SERVICE_ID" \
        "$STOLEUS_SERVICE_LAST_OPERATION_ID" \
        "$STOLEUS_SERVICE_LAST_PROVIDER_PLUGIN_ID" \
        "$STOLEUS_SERVICE_LAST_FUNCTION" \
        "$STOLEUS_SERVICE_LAST_EXIT_CODE"

    return 0
}


# ==============================================================================
# stoleus_service_runtime_initialize
# ==============================================================================

stoleus_service_runtime_initialize() {

    if [[ "${STOLEUS_SERVICE_RUNTIME_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    stoleus_service_runtime_reset || return $?


    STOLEUS_SERVICE_RUNTIME_INITIALIZED="true"

    return 0
}

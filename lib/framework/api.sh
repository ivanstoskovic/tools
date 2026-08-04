#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Framework API Registry
# ==============================================================================
#
# Purpose:
#     Register and validate the public functions exposed by Stoleus framework
#     modules.
#
# Why this registry exists:
#
#     Bash functions are loaded into one global namespace. Without an explicit
#     contract, there is no clear distinction between:
#
#         - public framework functions;
#         - internal implementation helpers.
#
#     This registry documents the supported API and verifies during bootstrap
#     that every declared public function actually exists.
#
# Example:
#
#     framework_register_api \
#         "text" \
#         log_info \
#         log_error \
#         write_text
#
# ==============================================================================
set -Eeuo pipefail


# ==============================================================================
# Framework API State
# ==============================================================================
#
# STOLEUS_FRAMEWORK_API_MODULES
#     Stores registered module names.
#
# STOLEUS_FRAMEWORK_API_FUNCTIONS
#     Stores entries in this format:
#
#         module:function
#
# Example:
#
#     text:log_info
#     filesystem:write_file
# ==============================================================================
declare -a STOLEUS_FRAMEWORK_API_MODULES=()
declare -a STOLEUS_FRAMEWORK_API_FUNCTIONS=()


# ==============================================================================
# framework_register_api
# ==============================================================================
#
# Purpose:
#     Register the public functions exposed by one framework module.
#
# Arguments:
#
#     $1
#         Module name.
#
#     Remaining arguments
#         Public function names exposed by that module.
#
# Example:
#
#     framework_register_api \
#         "os" \
#         download_file \
#         extract_tar_gz
# ==============================================================================
framework_register_api() {

    local module_name="${1:-}"
    local function_name

    local existing_module
    local existing_entry
    local api_entry


    if [[ -z "$module_name" ]]; then

        log_error \
            "framework_register_api requires a module name."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    shift


    if (( $# == 0 )); then

        log_error \
            "Framework module '${module_name}' did not declare any public functions."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    # --------------------------------------------------------------------------
    # Register the module once.
    # --------------------------------------------------------------------------
    for existing_module in "${STOLEUS_FRAMEWORK_API_MODULES[@]}"; do

        if [[ "$existing_module" == "$module_name" ]]; then

            log_error \
                "Framework API module is already registered: $module_name"

            return "${STOLEUS_EXIT_CONFLICT:-8}"
        fi
    done


    STOLEUS_FRAMEWORK_API_MODULES+=("$module_name")


    # --------------------------------------------------------------------------
    # Register every public function.
    # --------------------------------------------------------------------------
    for function_name in "$@"; do

        if [[ -z "$function_name" ]]; then

            log_error \
                "Framework module '${module_name}' contains an empty function name."

            return "${STOLEUS_EXIT_CONFIGURATION:-6}"
        fi


        if [[ ! "$function_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then

            log_error \
                "Invalid public function name in module '${module_name}': $function_name"

            return "${STOLEUS_EXIT_CONFIGURATION:-6}"
        fi


        api_entry="${module_name}:${function_name}"


        for existing_entry in "${STOLEUS_FRAMEWORK_API_FUNCTIONS[@]}"; do

            if [[ "$existing_entry" == "$api_entry" ]]; then

                log_error \
                    "Framework API function is already registered: $api_entry"

                return "${STOLEUS_EXIT_CONFLICT:-8}"
            fi
        done


        STOLEUS_FRAMEWORK_API_FUNCTIONS+=("$api_entry")
    done


    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# framework_verify_api
# ==============================================================================
#
# Purpose:
#     Verify that every function declared as public actually exists.
#
# This runs during framework bootstrap. A missing function indicates that:
#
#     - an implementation file was not loaded;
#     - a public function was renamed;
#     - an API contract is outdated;
#     - module loading order is incorrect.
# ==============================================================================
framework_verify_api() {

    local api_entry
    local module_name
    local function_name

    local failure_count=0


    log_debug "Verifying Stoleus framework public API."


    if (( ${#STOLEUS_FRAMEWORK_API_MODULES[@]} == 0 )); then

        log_error "No framework API modules were registered."

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    for api_entry in "${STOLEUS_FRAMEWORK_API_FUNCTIONS[@]}"; do

        module_name="${api_entry%%:*}"
        function_name="${api_entry#*:}"


        if ! declare -F "$function_name" >/dev/null 2>&1; then

            log_error \
                "Missing public framework function: ${module_name}.${function_name}"

            failure_count=$((failure_count + 1))
        fi
    done


    if (( failure_count > 0 )); then

        log_error \
            "Framework API verification failed; missing functions: $failure_count"

        return "${STOLEUS_EXIT_VERIFICATION:-7}"
    fi


    log_debug \
        "Framework API verification passed for ${#STOLEUS_FRAMEWORK_API_FUNCTIONS[@]} functions."

    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# framework_is_public_function
# ==============================================================================
#
# Purpose:
#     Determine whether a function is registered as part of the public
#     framework API.
#
# Arguments:
#
#     $1 = function name
#
# Return codes:
#
#     0 = public function
#     1 = function is not registered as public
#     2 = invalid argument
# ==============================================================================
framework_is_public_function() {

    local requested_function="${1:-}"
    local api_entry
    local registered_function


    if [[ -z "$requested_function" ]]; then

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    for api_entry in "${STOLEUS_FRAMEWORK_API_FUNCTIONS[@]}"; do

        registered_function="${api_entry#*:}"


        if [[ "$registered_function" == "$requested_function" ]]; then

            return "${STOLEUS_EXIT_SUCCESS:-0}"
        fi
    done


    return "${STOLEUS_EXIT_FAILURE:-1}"
}

# ==============================================================================
# framework_is_registered_module
# ==============================================================================
#
# Purpose:
#     Determine whether a framework API module is registered.
#
# Arguments:
#
#     $1 = framework module name
#
# Examples:
#
#     framework_is_registered_module "text"
#     framework_is_registered_module "filesystem"
#
# Return codes:
#
#     0 = module is registered
#     1 = module is not registered
#     2 = module name was not provided
# ==============================================================================
framework_is_registered_module() {

    local requested_module="${1:-}"
    local registered_module


    if [[ -z "$requested_module" ]]; then

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    for registered_module in "${STOLEUS_FRAMEWORK_API_MODULES[@]}"; do

        if [[ "$registered_module" == "$requested_module" ]]; then

            return "${STOLEUS_EXIT_SUCCESS:-0}"
        fi
    done


    return "${STOLEUS_EXIT_FAILURE:-1}"
}
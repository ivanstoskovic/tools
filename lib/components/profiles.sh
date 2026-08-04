#!/usr/bin/env bash

set -Eeuo pipefail


# ==============================================================================
# validate_server_profile
# ==============================================================================
#
# Purpose:
#     Validate a server profile before any component dependencies are executed.
#
# Why this validation runs before dependency execution:
#
#     The server component depends on:
#
#         chrony
#         firewall
#         docker
#         directories
#
#     Without pre-validation, an invalid or unsupported profile could cause all
#     dependencies to run before Stoleus discovers that the profile cannot be
#     configured.
#
# Usage:
#
#     validate_server_profile "app"
#     validate_server_profile "stage"
#
# Return codes:
#
#     0 = supported profile
#     2 = missing or unsupported profile
# ==============================================================================
validate_server_profile() {

    local profile="${1:-}"


    if [[ -z "$profile" ]]; then

        log_error "A server profile must be specified."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    case "$profile" in

        app|stage)

            return "${STOLEUS_EXIT_SUCCESS:-0}"

            ;;


        storage)

            log_error "The storage profile is not implemented yet."
            log_error "Its database ports must be restricted to the LAN."

            return "${STOLEUS_EXIT_USAGE:-2}"

            ;;


        *)

            log_error "Unknown server profile: $profile"

            return "${STOLEUS_EXIT_USAGE:-2}"

            ;;
    esac
}


# ==============================================================================
# setup_app_server
# ==============================================================================
#
# Purpose:
#     Complete application-server-specific configuration.
#
# Shared infrastructure dependencies are no longer executed here.
#
# They are resolved and executed by the component dependency graph before this
# function runs:
#
#     chrony
#     firewall
#     docker
#     directories
#
# Future application-server-only configuration belongs here.
# ==============================================================================
setup_app_server() {

    log_success \
        "Application-server profile configured successfully."

    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# setup_stage_server
# ==============================================================================
#
# Purpose:
#     Complete staging-server-specific configuration.
#
# Shared infrastructure dependencies are executed by the component dependency
# graph before this function runs.
#
# Future staging-specific configuration belongs here.
# ==============================================================================
setup_stage_server() {

    log_success \
        "Staging-server profile configured successfully."

    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# setup_server_profile
# ==============================================================================
#
# Purpose:
#     Execute the profile-specific finalization phase after shared dependencies
#     have completed.
#
# Usage:
#
#     setup_server_profile "app"
#     setup_server_profile "stage"
#
# Important:
#
#     This function no longer directly executes:
#
#         setup_chrony
#         setup_firewall
#         setup_docker
#         setup_application_directories
#
#     Those dependencies are declared by the server manifest and executed by
#     the component dependency graph.
# ==============================================================================
setup_server_profile() {

    local profile="${1:-}"


    require_root || return $?


    # --------------------------------------------------------------------------
    # Defensive validation.
    #
    # The registry validator already performs this before dependency execution,
    # but validation is repeated here so direct function calls remain safe.
    # --------------------------------------------------------------------------
    validate_server_profile "$profile" || return $?


    case "$profile" in

        app)

            setup_app_server || return $?

            ;;


        stage)

            setup_stage_server || return $?

            ;;
    esac


    return "${STOLEUS_EXIT_SUCCESS:-0}"
}
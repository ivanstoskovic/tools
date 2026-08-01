#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# setup_app_server
# ==============================================================================
#
# Purpose:
#     Configure the application-server baseline.
#
# The profile definition is intentionally declarative:
#
#     pipeline_begin
#     pipeline_step
#     pipeline_end
#
# The pipeline engine handles:
#
#     - step counting
#     - execution order
#     - progress output
#     - colored success/failure status
#     - failure summaries
# ==============================================================================
setup_app_server() {

    require_root || return 1

    pipeline_begin "Application server" || return 1

    pipeline_step "Chrony" setup_chrony || return 1
    pipeline_step "Firewall" setup_firewall || return 1
    pipeline_step "Docker" setup_docker || return 1
    pipeline_step "Directories" setup_application_directories || return 1

    pipeline_end
}


# ==============================================================================
# setup_stage_server
# ==============================================================================
#
# Purpose:
#     Configure the staging-server baseline.
#
# Staging currently uses the same baseline as the application server, but it
# remains a separate profile so staging-specific components can be added later.
# ==============================================================================
setup_stage_server() {

    require_root || return 1

    pipeline_begin "Staging server" || return 1

    pipeline_step "Chrony" setup_chrony || return 1
    pipeline_step "Firewall" setup_firewall || return 1
    pipeline_step "Docker" setup_docker || return 1
    pipeline_step "Directories" setup_application_directories || return 1

    pipeline_end
}

# ==============================================================================
# setup_server_profile
# ==============================================================================
#
# Purpose:
#     Route a server profile name to its setup implementation.
#
# Usage:
#
#     setup_server_profile "app"
#     setup_server_profile "stage"
#
# This is similar to a C# switch statement.
# ==============================================================================
setup_server_profile() {

    local profile="${1:-}"


    if [[ -z "$profile" ]]; then

        log_error "A server profile must be specified."

        return 2
    fi


    case "$profile" in

        app)

            setup_app_server

            ;;


        stage)

            setup_stage_server

            ;;


        storage)

            log_error "The storage profile is not implemented yet."
            log_error "Its database ports must be restricted to the LAN."

            return 2

            ;;


        *)

            log_error "Unknown server profile: $profile"

            return 2

            ;;
    esac
}
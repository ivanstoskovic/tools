#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Setup Command
# ==============================================================================
#
# This file implements:
#
#     stoleus setup ...
#
# Examples:
#
#     stoleus setup chrony
#
# In the future we can extend this command with:
#
#     stoleus setup docker
#     stoleus setup firewall
#     stoleus setup postgresql
#     stoleus setup server
#
# This file handles CLI routing only.
#
# The actual setup logic lives in:
#
#     lib/setup.sh
# ==============================================================================


# ------------------------------------------------------------------------------
# Enable strict Bash behavior.
# ------------------------------------------------------------------------------
set -Eeuo pipefail


# ------------------------------------------------------------------------------
# Load setup functions.
#
# PROJECT_ROOT is defined by bin/stoleus.
#
# After this line, functions such as:
#
#     setup_chrony
#
# become available.
# ------------------------------------------------------------------------------
source "${PROJECT_ROOT}/lib/setup.sh"


# ==============================================================================
# print_setup_help
# ==============================================================================
#
# Purpose:
#     Show the available setup components.
# ==============================================================================
print_setup_help() {

cat <<'HELP'
Stoleus Setup

Usage:
    stoleus setup <component>
    stoleus setup server <profile>

Available components:
    chrony      Install, enable, start, and verify Chrony
    firewall    Install and configure the UFW firewall
    docker      Install Docker Engine, Buildx, and Docker Compose
    server      Configure a complete server profile

Available server profiles:
    app         Application-server baseline
    stage       Staging-server baseline
    storage     Reserved; not implemented yet

Examples:
    sudo stoleus setup chrony
    sudo stoleus setup firewall
	sudo stoleus setup docker
    sudo stoleus setup server app
    sudo stoleus setup server stage
HELP
}


# ==============================================================================
# command_main
# ==============================================================================
#
# Entry point for:
#
#     stoleus setup ...
#
# `$1`
#     Contains the setup component requested by the user.
#
# Example:
#
#     stoleus setup chrony
#
# gives:
#
#     $1 = chrony
#
# `${1:-}`
#     Use the first argument if present.
#     Otherwise use an empty string.
# ==============================================================================
command_main() {

    local component="${1:-}"


    # --------------------------------------------------------------------------
    # No component provided.
    #
    # Example:
    #
    #     stoleus setup
    #
    # In this case we display help rather than guessing what the user wants.
    # --------------------------------------------------------------------------
    if [[ -z "$component" ]]; then

        print_setup_help

        return 2
    fi


    # --------------------------------------------------------------------------
    # Route the requested component.
    #
    # This is similar to a C# switch statement.
    # --------------------------------------------------------------------------
        case "$component" in

        # ----------------------------------------------------------------------
        # Install/configure Chrony.
        # ----------------------------------------------------------------------
        chrony)

            setup_chrony

            ;;


        # ----------------------------------------------------------------------
        # Install/configure the UFW firewall.
        # ----------------------------------------------------------------------
        firewall)

            setup_firewall

            ;;
			
		# ----------------------------------------------------------------------
        # Install and configure Docker Engine, Buildx, and Docker Compose.
        # ----------------------------------------------------------------------
        docker)

            setup_docker

            ;;

        # ----------------------------------------------------------------------
        # Configure a complete server profile.
        #
        # Examples:
        #
        #     stoleus setup server app
        #     stoleus setup server stage
        #
        # `${2:-}`
        #     The second argument contains the profile name.
        # ----------------------------------------------------------------------
        server)

            local profile="${2:-}"

            if [[ -z "$profile" ]]; then

                log_error "A server profile must be specified."
                echo

                print_setup_help

                return 2
            fi

            setup_server_profile "$profile"

            ;;
			
			
        # ----------------------------------------------------------------------
        # Help aliases.
        # ----------------------------------------------------------------------
        help|-h|--help)

            print_setup_help

            ;;


        # ----------------------------------------------------------------------
        # Unknown setup component.
        # ----------------------------------------------------------------------
        *)

            log_error "Unknown setup component: $component"
            echo

            print_setup_help

            return 2
            ;;
    esac
}
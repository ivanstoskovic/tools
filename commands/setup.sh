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
    chrony         Install, enable, start, and verify Chrony
    firewall       Install and configure the UFW firewall
    docker         Install Docker Engine, Buildx, and Docker Compose
    directories    Create the standard application-server directories
	github-runner  Install and register a GitHub Actions self-hosted runner
    server         Configure a complete server profile

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
	sudo stoleus setup directories
HELP
}


parse_github_runner_options() {

    GITHUB_RUNNER_URL=""
    GITHUB_RUNNER_SHORT_NAME=""
    GITHUB_RUNNER_LABELS="self-hosted,linux"
    GITHUB_RUNNER_USER="deployer"
	
	# Default GitHub Runner version.
    #
    # This version may be overridden with:
    #
    #     --version <version>
    #
    GITHUB_RUNNER_VERSION="2.334.0"

    while (( $# > 0 )); do

        case "$1" in

            --url)

                if (( $# < 2 )); then
                    log_error "--url requires a value."
                    return 2
                fi

                GITHUB_RUNNER_URL="$2"
                shift 2
                ;;

            --name)

                if (( $# < 2 )); then
                    log_error "--name requires a value."
                    return 2
                fi

                GITHUB_RUNNER_SHORT_NAME="$2"
                shift 2
                ;;

            --labels)

                if (( $# < 2 )); then
                    log_error "--labels requires a value."
                    return 2
                fi

                GITHUB_RUNNER_LABELS="$2"
                shift 2
                ;;

            --user)

                if (( $# < 2 )); then
                    log_error "--user requires a value."
                    return 2
                fi

                GITHUB_RUNNER_USER="$2"
                shift 2
                ;;
			
            --version)

                if (( $# < 2 )); then

                    log_error "--version requires a value."

                    return 2
                fi

                GITHUB_RUNNER_VERSION="$2"

                shift 2

                ;;

            *)

                log_error "Unknown GitHub Runner option: $1"
                return 2
                ;;
        esac
    done
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
    # In this case, display help rather than guessing what the user wants.
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
        # Install and configure Chrony.
        # ----------------------------------------------------------------------
        chrony)

            run_with_log_context \
                "chrony" \
                setup_chrony

            ;;


        # ----------------------------------------------------------------------
        # Install and configure the UFW firewall.
        # ----------------------------------------------------------------------
        firewall)

            run_with_log_context \
                "firewall" \
                setup_firewall

            ;;


        # ----------------------------------------------------------------------
        # Create and configure the standard application directories.
        # ----------------------------------------------------------------------
        directories)

            run_with_log_context \
                "directories" \
                setup_application_directories

            ;;


        # ----------------------------------------------------------------------
        # Install and configure Docker Engine, Buildx, and Docker Compose.
        # ----------------------------------------------------------------------
        docker)

            run_with_log_context \
                "docker" \
                setup_docker

            ;;


        # ----------------------------------------------------------------------
        # Configure a GitHub Actions self-hosted runner.
        #
        # Expected usage:
        #
        #     stoleus setup github-runner \
        #         --url https://github.com/OWNER/REPOSITORY \
        #         --name repository-name \
        #         --labels self-hosted,linux,x64
        #
        # The registration token is requested securely by the component.
        # ----------------------------------------------------------------------
        github-runner)

            shift

            parse_github_runner_options "$@" || return $?

            run_with_log_context \
                "github-runner" \
                github_runner_setup

            ;;


        # ----------------------------------------------------------------------
        # Configure a complete server profile.
        #
        # Examples:
        #
        #     stoleus setup server app
        #     stoleus setup server stage
        # ----------------------------------------------------------------------
        server)

            local profile="${2:-}"

            if [[ -z "$profile" ]]; then

                log_error "A server profile must be specified."
                echo

                print_setup_help

                return 2
            fi

            run_with_log_context \
                "server:${profile}" \
                setup_server_profile \
                "$profile"

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
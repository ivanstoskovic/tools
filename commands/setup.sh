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
#     lib/components/index.sh
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
source "${PROJECT_ROOT}/lib/components/index.sh"


# ==============================================================================
# print_setup_help
# ==============================================================================
#
# Purpose:
#     Display help for the `stoleus setup` command.
#
# Component list:
#
#     The available components are generated from the component registry.
#
#     This means:
#
#         - new registered components appear automatically;
#         - removed components disappear automatically;
#         - component descriptions come from their manifests;
#         - help output no longer duplicates component metadata.
#
# Server profiles remain explicit for now because they are arguments of the
# `server` component rather than independent registered components.
# ==============================================================================
print_setup_help() {

    cat <<'EOF'
Stoleus Setup

Usage:
    stoleus setup <component>
    stoleus setup server <profile>

Available components:
EOF


    component_print_registered \
        "    " \
        "16" ||
        return $?


    cat <<'EOF'

Available server profiles:
    app             Application-server baseline
    stage           Staging-server baseline
    storage         Reserved; not implemented yet

Examples:
    sudo stoleus setup chrony
    sudo stoleus setup firewall
    sudo stoleus setup docker
    sudo stoleus setup directories
    sudo stoleus setup github-runner \
        --url https://github.com/OWNER/REPOSITORY \
        --name repository-name \
        --labels self-hosted,linux,x64
    sudo stoleus setup server app
    sudo stoleus setup server stage
EOF


    return "${STOLEUS_EXIT_SUCCESS:-0}"
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
# Purpose:
#     Entry point for:
#
#         stoleus setup ...
#
# Syntax:
#
#     stoleus setup <component> [component arguments]
#
# Examples:
#
#     stoleus setup chrony
#
#     stoleus setup server stage
#
#     stoleus setup github-runner \
#         --url https://github.com/OWNER/REPOSITORY \
#         --name repository-name \
#         --labels self-hosted,linux,x64
#
# Registry-based routing:
#
#     Components are no longer routed through a hard-coded case branch.
#
#     Instead:
#
#         component ID
#             ↓
#         component registry
#             ↓
#         registered entry function
#             ↓
#         run_with_log_context()
#
# Temporary special handling:
#
#     GitHub Runner options are still parsed by:
#
#         parse_github_runner_options()
#
#     before the registered component entry function is executed.
#
#     Later, CLI argument parsing can become component metadata or a dedicated
#     component command adapter.
# ==============================================================================
command_main() {

    local component="${1:-}"


    # --------------------------------------------------------------------------
    # No component was supplied.
    #
    # Example:
    #
    #     stoleus setup
    #
    # Display setup help instead of guessing which component should run.
    # --------------------------------------------------------------------------
    if [[ -z "$component" ]]; then

        print_setup_help

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    # --------------------------------------------------------------------------
    # Handle setup-level help aliases.
    #
    # These values are setup command controls, not registered components.
    # --------------------------------------------------------------------------
    case "$component" in

        help|-h|--help)

            print_setup_help

            return "${STOLEUS_EXIT_SUCCESS:-0}"

            ;;
    esac


    # --------------------------------------------------------------------------
    # Remove the component ID.
    #
    # Before shift:
    #
    #     $1 = component ID
    #     $2... = component arguments
    #
    # After shift:
    #
    #     $1... = component arguments
    #
    # Example:
    #
    #     command_main "server" "stage"
    #
    # becomes:
    #
    #     component="server"
    #     $1="stage"
    # --------------------------------------------------------------------------
    shift


    # --------------------------------------------------------------------------
    # GitHub Runner currently has command-specific option parsing.
    #
    # Example remaining arguments:
    #
    #     --url https://github.com/OWNER/REPOSITORY
    #     --name repository-name
    #     --labels self-hosted,linux,x64
    #     --version 2.334.0
    #
    # parse_github_runner_options() stores the parsed values in the configuration
    # variables consumed by github_runner_setup().
    #
    # The parsed CLI arguments are therefore not forwarded to the registered
    # entry function afterward.
    # --------------------------------------------------------------------------
    if [[ "$component" == "github-runner" ]]; then

        parse_github_runner_options "$@" || return $?


        component_execute \
            "$component" ||
            return $?


        return "${STOLEUS_EXIT_SUCCESS:-0}"
    fi


    # --------------------------------------------------------------------------
    # Execute every other registered component generically.
    #
    # Examples:
    #
    #     component_execute "chrony"
    #
    #     component_execute "docker"
    #
    #     component_execute "server" "stage"
    #
    # Unknown components are rejected by component_execute().
    # --------------------------------------------------------------------------
    component_execute \
        "$component" \
        "$@" ||
        return $?


    return "${STOLEUS_EXIT_SUCCESS:-0}"
}
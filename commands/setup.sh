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

Available components:
    chrony      Install, enable, start, and verify Chrony

Examples:
    sudo stoleus setup chrony
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
        # Help aliases.
        # ----------------------------------------------------------------------
        help|-h|--help)

            print_setup_help

            ;;


        # ----------------------------------------------------------------------
        # Unknown setup component.
        # ----------------------------------------------------------------------
        *)

            echo "ERROR: Unknown setup component: $component" >&2
            echo

            print_setup_help

            return 2
            ;;
    esac
}
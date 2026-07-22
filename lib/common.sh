#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Shared Common Functions
# ==============================================================================
#
# This file contains reusable functions shared by multiple Stoleus commands.
#
# It is loaded by:
#
#     bin/stoleus
#
# using:
#
#     source "${PROJECT_ROOT}/lib/common.sh"
#
# Shared logic belongs here so command files do not duplicate the same code.
#
# This follows the DRY principle:
#
#     Don't Repeat Yourself
#
# ==============================================================================


# ------------------------------------------------------------------------------
# Enable strict Bash behavior.
#
# -E
#     Preserve ERR traps inside functions and subshells.
#
# -e
#     Stop the script when a command fails.
#
# -u
#     Treat undefined variables as errors.
#
# -o pipefail
#     Make a pipeline fail if any important command inside it fails.
# ------------------------------------------------------------------------------
set -Eeuo pipefail


# ==============================================================================
# Shared Path Constants
# ==============================================================================
#
# PROJECT_ROOT is defined by bin/stoleus BEFORE this file is sourced.
#
# Example:
#
#     PROJECT_ROOT=/c/Users/ivans/Desktop/Projects/TOOLS/tools
#
# We use readonly because these paths should not change during execution.
# ==============================================================================


# ------------------------------------------------------------------------------
# Directory containing command implementation files.
#
# Example:
#
#     /c/Users/ivans/Desktop/Projects/TOOLS/tools/commands
# ------------------------------------------------------------------------------
readonly STOLEUS_COMMANDS_DIR="${PROJECT_ROOT}/commands"


# ------------------------------------------------------------------------------
# File containing the current project version.
#
# Example:
#
#     /c/Users/ivans/Desktop/Projects/TOOLS/tools/VERSION
# ------------------------------------------------------------------------------
readonly STOLEUS_VERSION_FILE="${PROJECT_ROOT}/VERSION"


# ==============================================================================
# print_error
# ==============================================================================
#
# Purpose:
#     Print an error message to STDERR.
#
# Usage:
#
#     print_error "Docker is not installed"
#
# "$*"
#     Represents all arguments passed to this function combined as one string.
#
# >&2
#     Redirects the output from stdout to stderr.
# ==============================================================================
print_error() {

    echo "ERROR: $*" >&2
}


# ==============================================================================
# run_command
# ==============================================================================
#
# Purpose:
#     Load and execute one Stoleus command implementation.
#
# Example:
#
#     run_command "help"
#
# loads:
#
#     commands/help.sh
#
# Example:
#
#     run_command "version"
#
# loads:
#
#     commands/version.sh
#
# Each command file must expose:
#
#     command_main()
#
# ==============================================================================
run_command() {

    # --------------------------------------------------------------------------
    # Store the first argument passed to this function.
    #
    # Example:
    #
    #     run_command "help"
    #
    # means:
    #
    #     $1 = help
    #
    # local
    #     Restricts the variable to this function.
    # --------------------------------------------------------------------------
    local command_name="$1"


    # --------------------------------------------------------------------------
    # Remove the first positional argument.
    #
    # We have already saved it in:
    #
    #     command_name
    #
    # Any remaining arguments will later be forwarded to command_main().
    #
    # Example:
    #
    #     run_command "health" "--verbose"
    #
    # Before shift:
    #
    #     $1 = health
    #     $2 = --verbose
    #
    # After shift:
    #
    #     $1 = --verbose
    # --------------------------------------------------------------------------
    shift


    # --------------------------------------------------------------------------
    # Build the full file path for the command implementation.
    #
    # Example:
    #
    #     STOLEUS_COMMANDS_DIR=/home/ivan/tools/commands
    #     command_name=help
    #
    # becomes:
    #
    #     /home/ivan/tools/commands/help.sh
    # --------------------------------------------------------------------------
    local command_file="${STOLEUS_COMMANDS_DIR}/${command_name}.sh"


    # --------------------------------------------------------------------------
    # Verify that the command implementation exists.
    #
    # -f
    #     Tests whether the path exists and is a normal file.
    #
    # !
    #     Means logical NOT.
    #
    # Therefore:
    #
    #     [[ ! -f "$command_file" ]]
    #
    # means:
    #
    #     If the command file does NOT exist.
    # --------------------------------------------------------------------------
    if [[ ! -f "$command_file" ]]; then

        print_error "Command implementation not found: $command_name"

        return 1
    fi


    # --------------------------------------------------------------------------
    # Load the command implementation into the current Bash process.
    #
    # source
    #     Reads another Bash file and executes it in the CURRENT shell.
    #
    # After this line runs, functions inside that command file become available.
    #
    # In our design, every command file exposes:
    #
    #     command_main()
    # --------------------------------------------------------------------------
    source "$command_file"


    # --------------------------------------------------------------------------
    # Execute the command.
    #
    # "$@"
    #     Passes all remaining arguments to command_main().
    #
    # Example:
    #
    #     stoleus health --verbose
    #
    # eventually becomes:
    #
    #     command_main "--verbose"
    # --------------------------------------------------------------------------
    command_main "$@"
}


# ==============================================================================
# read_version
# ==============================================================================
#
# Purpose:
#     Read the current version from the VERSION file.
#
# The repository contains:
#
#     VERSION
#
# with content such as:
#
#     0.1.0
#
# We keep the version in one file so it becomes the single source of truth.
# ==============================================================================
read_version() {

    # --------------------------------------------------------------------------
    # Verify that VERSION exists and can be read.
    #
    # -r
    #     Checks whether the file is readable.
    # --------------------------------------------------------------------------
    if [[ ! -r "$STOLEUS_VERSION_FILE" ]]; then


        return 1
    fi


    #     Removes whitespace characters such as spaces, tabs, and newlines.
    #
    # Example:
    #
    # VERSION contains:
    #
    #     0.1.0
    #
    # followed by a newline.
    #
    # This command outputs:
    #
    #     0.1.0
    # --------------------------------------------------------------------------
    tr -d '[:space:]' < "$STOLEUS_VERSION_FILE"
}    # --------------------------------------------------------------------------
    # Read the VERSION file.
    #
    # <
    #     Redirects the file into the standard input of `tr`.
    #
    # tr -d '[:space:]'


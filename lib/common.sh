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
#     Make a pipeline fail if any command inside it fails.
# ------------------------------------------------------------------------------
set -Eeuo pipefail


# ==============================================================================
# Shared Path Constants
# ==============================================================================
#
# PROJECT_ROOT is defined by bin/stoleus before this file is sourced.
#
# Example:
#
#     PROJECT_ROOT=/home/ivan/tools
#
# We use readonly because these paths should not change during execution.
# ==============================================================================


# ------------------------------------------------------------------------------
# Directory containing command implementation files.
#
# Example:
#
#     /home/ivan/tools/commands
# ------------------------------------------------------------------------------
readonly STOLEUS_COMMANDS_DIR="${PROJECT_ROOT}/commands"


# ------------------------------------------------------------------------------
# File containing the current project version.
#
# Example:
#
#     /home/ivan/tools/VERSION
# ------------------------------------------------------------------------------
readonly STOLEUS_VERSION_FILE="${PROJECT_ROOT}/VERSION"


# ==============================================================================
# Console Output Helpers
# ==============================================================================
#
# These functions provide consistent console output across all Stoleus commands.
#
# Usage:
#
#     log_info "Installing Chrony..."
#     log_success "Chrony is running."
#     log_warning "Chrony is not synchronized yet."
#     log_error "Chrony installation failed."
#
# Informational, success, and warning messages are written to stdout.
#
# Error messages are written to stderr.
# ==============================================================================


# ==============================================================================
# log_info
# ==============================================================================
#
# Purpose:
#     Print an informational message.
#
# Usage:
#
#     log_info "Installing Chrony..."
# ==============================================================================
log_info() {

    local message="${1:-}"

    printf 'INFO: %s\n' "$message"
}


# ==============================================================================
# log_success
# ==============================================================================
#
# Purpose:
#     Print a successful-operation message.
#
# Usage:
#
#     log_success "Chrony is running."
# ==============================================================================
log_success() {

    local message="${1:-}"

    printf 'SUCCESS: %s\n' "$message"
}


# ==============================================================================
# log_warning
# ==============================================================================
#
# Purpose:
#     Print a warning message.
#
# Usage:
#
#     log_warning "Chrony is running but not synchronized yet."
# ==============================================================================
log_warning() {

    local message="${1:-}"

    printf 'WARNING: %s\n' "$message"
}


# ==============================================================================
# log_error
# ==============================================================================
#
# Purpose:
#     Print an error message to stderr.
#
# Usage:
#
#     log_error "Chrony installation failed."
#
# >&2
#     Redirects the output from stdout to stderr.
# ==============================================================================
log_error() {

    local message="${1:-}"

    printf 'ERROR: %s\n' "$message" >&2
}


# ==============================================================================
# print_error
# ==============================================================================
#
# Purpose:
#     Maintain compatibility with existing Stoleus code that already calls:
#
#         print_error "message"
#
# New code should normally use:
#
#     log_error "message"
#
# "$*"
#     Combines all arguments passed to the function into one string.
# ==============================================================================
print_error() {

    log_error "$*"
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
    #     If the command file does not exist.
    # --------------------------------------------------------------------------
    if [[ ! -f "$command_file" ]]; then

        log_error "Command implementation not found: $command_name"

        return 1
    fi


    # --------------------------------------------------------------------------
    # Load the command implementation into the current Bash process.
    #
    # source
    #     Reads another Bash file and executes it in the current shell.
    #
    # After this line runs, functions inside that command file become available.
    #
    # In our design, every command file exposes:
    #
    #     command_main()
    # --------------------------------------------------------------------------
    source "$command_file"


    # --------------------------------------------------------------------------
    # Verify that the command file exposed command_main().
    #
    # declare -F
    #     Checks whether a function with the specified name exists.
    #
    # This gives us a clear error instead of:
    #
    #     command_main: command not found
    # --------------------------------------------------------------------------
    if ! declare -F command_main >/dev/null 2>&1; then

        log_error "Command does not define command_main(): $command_name"

        return 1
    fi


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

        log_error "Version file is missing or unreadable: $STOLEUS_VERSION_FILE"

        return 1
    fi


    # --------------------------------------------------------------------------
    # Read the VERSION file.
    #
    # <
    #     Redirects the file into the standard input of tr.
    #
    # tr -d '[:space:]'
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
}
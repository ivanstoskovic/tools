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
#     Stop the script when an unexpected command fails.
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
readonly STOLEUS_COMMANDS_DIR="${PROJECT_ROOT}/commands"
readonly STOLEUS_VERSION_FILE="${PROJECT_ROOT}/VERSION"


# ==============================================================================
# Framework Modules
# ==============================================================================
#
# Load the modular framework libraries.
#
# Dependency order is important:
#
#     secrets
#         ↓
#     logging
#         ↓
#     output
#         ↓
#     filesystem
#         ↓
#     process
#         ↓
#     operating system
#
# ==============================================================================
# Text
# ==============================================================================
source "${PROJECT_ROOT}/lib/text/secrets.sh"
source "${PROJECT_ROOT}/lib/text/logging.sh"
source "${PROJECT_ROOT}/lib/text/output.sh"


# ==============================================================================
# Operating System
# ==============================================================================
source "${PROJECT_ROOT}/lib/os/downloads.sh"
source "${PROJECT_ROOT}/lib/os/archives.sh"


# ==============================================================================
# Filesystem
# ==============================================================================
source "${PROJECT_ROOT}/lib/filesystem/checksums.sh"
source "${PROJECT_ROOT}/lib/filesystem/directories.sh"
source "${PROJECT_ROOT}/lib/filesystem/backups.sh"
source "${PROJECT_ROOT}/lib/filesystem/files.sh"


# ==============================================================================
#
# Process
# ==============================================================================
source "${PROJECT_ROOT}/lib/process/execution.sh"


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
	# `local`
	#     Restricts the variable to this function.
	# --------------------------------------------------------------------------
    local command_name="${1:-}"


    # --------------------------------------------------------------------------
    # Validate the command name before continuing.
    # --------------------------------------------------------------------------
    if [[ -z "$command_name" ]]; then

        log_error "run_command was called without a command name."

        return 1
    fi


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
	#     STOLEUS_COMMANDS_DIR=/home/deployer/tools/commands
	#     command_name=help
	#
	# becomes:
	#
	#     /home/deployer/tools/commands/help.sh
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
	# --------------------------------------------------------------------------
    if [[ ! -f "$command_file" ]]; then

        log_error "Command implementation not found: $command_name"

        return 1
    fi


    # --------------------------------------------------------------------------
    # Remove an existing command_main function before loading another command.
    #
    # Because command files are sourced into the current shell, a previous
    # command_main definition could otherwise remain available.
    #
    # `unset -f`
    #     Removes a Bash function.
    #
    # `2>/dev/null || true`
    #     Suppresses the error if the function does not currently exist.
    # --------------------------------------------------------------------------
    unset -f command_main 2>/dev/null || true


    # --------------------------------------------------------------------------
    # Load the command implementation into the current Bash process.
    #
    # `source`
    #     Reads another Bash file and executes it in the current shell.
    # --------------------------------------------------------------------------
    source "$command_file"


    # --------------------------------------------------------------------------
    # Verify that the command file exposed command_main().
    #
    # `declare -F`
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

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
#
# PROJECT_ROOT is defined by bin/stoleus before this file is sourced.
#
# Example:
#
#     PROJECT_ROOT=/home/deployer/tools
#
# We use readonly because these paths should not change during execution.
# ==============================================================================


# ------------------------------------------------------------------------------
# Directory containing command implementation files.
#
# Example:
#
#     /home/deployer/tools/commands
# ------------------------------------------------------------------------------
readonly STOLEUS_COMMANDS_DIR="${PROJECT_ROOT}/commands"


# ------------------------------------------------------------------------------
# File containing the current project version.
#
# Example:
#
#     /home/deployer/tools/VERSION
# ------------------------------------------------------------------------------
readonly STOLEUS_VERSION_FILE="${PROJECT_ROOT}/VERSION"


# ==============================================================================
# Terminal Color Configuration
# ==============================================================================
#
# ANSI escape sequences allow supported terminals to display colored text.
#
# We use colors only when:
#
#     - stdout or stderr is connected to a terminal
#     - the NO_COLOR environment variable is not set
#     - the TERM environment variable is not "dumb"
#
# This prevents control characters from appearing in:
#
#     - redirected files
#     - CI/CD logs without terminal support
#     - cron output
#     - systemd logs
#
# The user can explicitly disable colors with:
#
#     NO_COLOR=1 stoleus health
#
# or:
#
#     sudo NO_COLOR=1 stoleus setup server app
#
# `$'\033[...m'`
#     Bash ANSI-C quoting used to create terminal escape sequences.
#
# Color codes:
#
#     31 = red
#     32 = green
#     33 = yellow
#     36 = cyan
#      0 = reset terminal formatting
# ==============================================================================

if {
    [[ -t 1 ]] || [[ -t 2 ]]
} && [[ -z "${NO_COLOR:-}" ]] && [[ "${TERM:-}" != "dumb" ]]; then

    readonly COLOR_RED=$'\033[0;31m'
    readonly COLOR_GREEN=$'\033[0;32m'
    readonly COLOR_YELLOW=$'\033[0;33m'
    readonly COLOR_CYAN=$'\033[0;36m'
    readonly COLOR_RESET=$'\033[0m'

else

    # --------------------------------------------------------------------------
    # Empty values disable coloring while allowing the same printing functions
    # to work unchanged.
    # --------------------------------------------------------------------------
    readonly COLOR_RED=""
    readonly COLOR_GREEN=""
    readonly COLOR_YELLOW=""
    readonly COLOR_CYAN=""
    readonly COLOR_RESET=""
fi


# ==============================================================================
# Console Output Helpers
# ==============================================================================
#
# These functions provide consistent console output across Stoleus commands.
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
#
# Information is displayed in cyan when terminal colors are available.
# ==============================================================================
log_info() {

    local message="${1:-}"

    printf '%sINFO:%s %s\n' \
        "$COLOR_CYAN" \
        "$COLOR_RESET" \
        "$message"
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
#
# Success output is displayed in green when terminal colors are available.
# ==============================================================================
log_success() {

    local message="${1:-}"

    printf '%sSUCCESS:%s %s\n' \
        "$COLOR_GREEN" \
        "$COLOR_RESET" \
        "$message"
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
#
# Warning output is displayed in yellow when terminal colors are available.
# ==============================================================================
log_warning() {

    local message="${1:-}"

    printf '%sWARNING:%s %s\n' \
        "$COLOR_YELLOW" \
        "$COLOR_RESET" \
        "$message"
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
# Error output is displayed in red when terminal colors are available.
#
# `>&2`
#     Redirects output from stdout to stderr.
# ==============================================================================
log_error() {

    local message="${1:-}"

    printf '%sERROR:%s %s\n' \
        "$COLOR_RED" \
        "$COLOR_RESET" \
        "$message" >&2
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
# print_step_success
# ==============================================================================
#
# Purpose:
#     Print the final successful status of a server-profile step.
#
# Usage:
#
#     print_step_success 1 3 "Chrony"
#
# Output:
#
#     [1/3] Chrony — OK
#
# The complete line is displayed in green when terminal colors are available.
#
# Arguments:
#
#     $1 = current step number
#     $2 = total number of steps
#     $3 = human-readable step name
# ==============================================================================
print_step_success() {

    local current_step="${1:-}"
    local total_steps="${2:-}"
    local step_name="${3:-}"


    # --------------------------------------------------------------------------
    # Validate required values before formatting the line.
    # --------------------------------------------------------------------------
    if [[ -z "$current_step" ]] ||
       [[ -z "$total_steps" ]] ||
       [[ -z "$step_name" ]]; then

        log_error "print_step_success received incomplete step information."

        return 1
    fi


    printf '%s[%s/%s] %s — OK%s\n' \
        "$COLOR_GREEN" \
        "$current_step" \
        "$total_steps" \
        "$step_name" \
        "$COLOR_RESET"
}


# ==============================================================================
# print_step_failure
# ==============================================================================
#
# Purpose:
#     Print the final failed status of a server-profile step.
#
# Usage:
#
#     print_step_failure 2 3 "Firewall"
#
# Output:
#
#     [2/3] Firewall — FAILED
#
# The complete line is displayed in red when terminal colors are available.
#
# Failed step lines are written to stderr.
#
# Arguments:
#
#     $1 = current step number
#     $2 = total number of steps
#     $3 = human-readable step name
# ==============================================================================
print_step_failure() {

    local current_step="${1:-}"
    local total_steps="${2:-}"
    local step_name="${3:-}"


    # --------------------------------------------------------------------------
    # Validate required values before formatting the line.
    # --------------------------------------------------------------------------
    if [[ -z "$current_step" ]] ||
       [[ -z "$total_steps" ]] ||
       [[ -z "$step_name" ]]; then

        log_error "print_step_failure received incomplete step information."

        return 1
    fi


    printf '%s[%s/%s] %s — FAILED%s\n' \
        "$COLOR_RED" \
        "$current_step" \
        "$total_steps" \
        "$step_name" \
        "$COLOR_RESET" >&2
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
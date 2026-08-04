#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Command Dispatcher
# ==============================================================================
#
# Purpose:
#     Locate, load, validate, and execute Stoleus command implementations.
#
# Every command file must expose:
#
#     command_main()
#
# Example:
#
#     run_command "setup" "chrony"
#
# loads:
#
#     commands/setup.sh
#
# and executes:
#
#     command_main "chrony"
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# run_command
# ==============================================================================
#
# Purpose:
#     Load and execute one Stoleus command implementation.
#
# Arguments:
#
#     $1
#         Command name.
#
#     Remaining arguments
#         Forwarded unchanged to command_main().
#
# Example:
#
#     run_command "setup" "chrony"
#
# becomes:
#
#     command_main "chrony"
# ==============================================================================
run_command() {

    local command_name="${1:-}"
    local command_file


    # --------------------------------------------------------------------------
    # A command name is required.
    # --------------------------------------------------------------------------
    if [[ -z "$command_name" ]]; then

        log_error "run_command was called without a command name."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    # --------------------------------------------------------------------------
    # Remove the command name from the positional arguments.
    #
    # The remaining arguments belong to the command implementation.
    # --------------------------------------------------------------------------
    shift


    # --------------------------------------------------------------------------
    # Resolve the command implementation path.
    #
    # Example:
    #
    #     setup
    #
    # becomes:
    #
    #     commands/setup.sh
    # --------------------------------------------------------------------------
    command_file="${STOLEUS_COMMANDS_DIR}/${command_name}.sh"


    if [[ ! -f "$command_file" ]]; then

        log_error "Command implementation not found: $command_name"

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    # --------------------------------------------------------------------------
    # Remove a previous command_main() definition before sourcing another command.
    #
    # Command files are sourced into the same Bash process, so an earlier
    # definition could otherwise remain available.
    # --------------------------------------------------------------------------
    unset -f command_main 2>/dev/null || true


    # --------------------------------------------------------------------------
    # Load the command implementation into the current Bash process.
    # --------------------------------------------------------------------------
    source "$command_file"


    # --------------------------------------------------------------------------
    # Verify the command contract.
    #
    # Every command implementation must expose command_main().
    # --------------------------------------------------------------------------
    if ! declare -F command_main >/dev/null 2>&1; then

        log_error "Command does not define command_main(): $command_name"

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    # --------------------------------------------------------------------------
    # Forward all remaining arguments while preserving argument boundaries.
    # --------------------------------------------------------------------------
    command_main "$@" || return $?


    return "${STOLEUS_EXIT_SUCCESS:-0}"
}
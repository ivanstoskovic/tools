#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Version Command
# ==============================================================================
#
# This file implements:
#
#     stoleus version
#
# It is loaded by:
#
#     run_command "version"
#
# from:
#
#     lib/common.sh
#
# Just like commands/help.sh, this file exposes:
#
#     command_main()
#
# That keeps every command implementation consistent.
# ==============================================================================


# ------------------------------------------------------------------------------
# Enable strict Bash behavior.
#
# -E
#     Preserve ERR traps inside functions/subshells.
#
# -e
#     Stop when a command fails.
#
# -u
#     Treat undefined variables as errors.
#
# -o pipefail
#     Treat failures inside pipelines correctly.
# ------------------------------------------------------------------------------
set -Eeuo pipefail


# ==============================================================================
# command_main
# ==============================================================================
#
# Entry function for:
#
#     stoleus version
#
# The actual version number is NOT hardcoded here.
#
# Instead, we call:
#
#     read_version
#
# which is defined inside:
#
#     lib/common.sh
#
# That function reads the value from:
#
#     VERSION
#
# This gives us one source of truth for the current project version.
# ==============================================================================
command_main() {

    # --------------------------------------------------------------------------
    # $(read_version)
    #
    # This is command substitution.
    #
    # Bash executes:
    #
    #     read_version
    #
    # and replaces:
    #
    #     $(read_version)
    #
    # with the output returned by that function.
    #
    # Example:
    #
    # If VERSION contains:
    #
    #     0.1.0
    #
    # then:
    #
    #     $(read_version)
    #
    # becomes:
    #
    #     0.1.0
    # --------------------------------------------------------------------------

    # --------------------------------------------------------------------------
    # printf
    #
    # `printf` prints formatted text.
    #
    # We could use:
    #
    #     echo "stoleus-tools v$(read_version)"
    #
    # but `printf` is generally more predictable in scripts.
    #
    # %s
    #     Placeholder for a string value.
    #
    # \n
    #     Newline character.
    #
    # So:
    #
    #     printf 'stoleus-tools v%s\n' "0.1.0"
    #
    # prints:
    #
    #     stoleus-tools v0.1.0
    # --------------------------------------------------------------------------
    printf 'stoleus-tools v%s\n' "$(read_version)"
}

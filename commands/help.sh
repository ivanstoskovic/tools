#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Help Command
# ==============================================================================
#
# This file implements:
#
#     stoleus help
#
# It is loaded by:
#
#     run_command "help"
#
# from:
#
#     lib/common.sh
#
# Every command file exposes the same public function:
#
#     command_main()
#
# This gives our command dispatcher a consistent interface.
#
# Think of it like every command implementing the same contract:
#
#     command_main "$@"
#
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
#     Treat pipeline failures correctly.
# ------------------------------------------------------------------------------
set -Eeuo pipefail


# ==============================================================================
# command_main
# ==============================================================================
#
# This is the entry function for the `help` command.
#
# The dispatcher in lib/common.sh expects every command implementation to
# provide a function with this exact name.
#
# Later:
#
#     commands/version.sh
#     commands/health.sh
#     commands/docker.sh
#
# will also implement:
#
#     command_main()
#
# ==============================================================================
command_main() {

    # --------------------------------------------------------------------------
    # `cat <<'HELP'`
    #
    # This is called a HEREDOC (Here Document).
    #
    # It allows us to write a multi-line block of text without needing many
    # separate echo commands.
    #
    # Everything between:
    #
    #     <<'HELP'
    #
    # and:
    #
    #     HELP
    #
    # is sent to `cat`, which prints it to the terminal.
    #
    # The quotes around 'HELP' are important.
    #
    # They prevent Bash from expanding variables or special characters inside
    # the text.
    #
    # Example:
    #
    #     $HOME
    #
    # would be printed literally instead of being replaced with the user's
    # home directory.
    # --------------------------------------------------------------------------
    cat <<'HELP'
Stoleus Tools

Usage:
    stoleus <command> [options]

Available commands:
    help        Show this help message
    version     Show the installed Stoleus Tools version

Aliases:
    -h, --help
    -v, --version

Examples:
    stoleus help
    stoleus version
HELP
}

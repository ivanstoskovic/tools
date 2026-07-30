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
# Current command implementations include:
#
#     commands/help.sh
#     commands/version.sh
#     commands/health.sh
#     commands/setup.sh
#
# Each implements:
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
    # The quotes around 'HELP' prevent Bash from expanding variables or special
    # characters inside the help text.
    # --------------------------------------------------------------------------
    cat <<'HELP'
Stoleus Tools

Usage:
    stoleus <command> [options]

Available commands:
    help        Show this help message
    version     Show the installed Stoleus Tools version
    health      Check server health
    setup       Install and configure server components

Setup components:
    Setup components:
    chrony      Install, enable, start, and verify Chrony
    firewall    Install and configure the UFW firewall
    server      Configure a complete server profile

Aliases:
    -h, --help
    -v, --version

Examples:
    stoleus help
    stoleus version
    sudo stoleus health
    stoleus setup help
    sudo stoleus setup chrony
    sudo stoleus setup firewall
    sudo stoleus setup server app
    sudo stoleus setup server stage
HELP
}
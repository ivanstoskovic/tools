#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Health Command
# ==============================================================================
#
# This file implements:
#
#     stoleus health
#
# Its responsibility is to:
#
#   1. Load the health-check library.
#   2. Print the report header.
#   3. Run the health checks.
#   4. Print the summary.
#   5. Return an appropriate exit code.
#
# The actual health-check logic belongs in:
#
#     lib/health.sh
#
# ==============================================================================


# ------------------------------------------------------------------------------
# Enable strict Bash behavior.
#
# -E
#     Preserve ERR traps inside functions and subshells.
#
# -e
#     Stop on unexpected command failure.
#
# -u
#     Treat undefined variables as errors.
#
# -o pipefail
#     Make pipelines fail if an important command inside them fails.
# ------------------------------------------------------------------------------
set -Eeuo pipefail


# ------------------------------------------------------------------------------
# Load the health-check library.
#
# PROJECT_ROOT was created by:
#
#     bin/stoleus
#
# and is available because commands are sourced into the same Bash process.
#
# After this line, functions such as:
#
#     health_pass
#     health_warn
#     health_fail
#     health_skip
#
# become available.
# ------------------------------------------------------------------------------
source "${PROJECT_ROOT}/lib/health.sh"


# ==============================================================================
# print_health_header
# ==============================================================================
#
# Purpose:
#     Print the beginning of the health report.
#
# `hostname`
#     Returns the current machine hostname.
#
# Example:
#
#     stoleusapp
#
# `date`
#     Prints the current system date and time.
# ==============================================================================
print_health_header() {

    echo
    echo "============================================================"
    echo "              STOLEUS SERVER HEALTH REPORT"
    echo "============================================================"

    printf '%-16s %s\n' "Server:" "$(hostname)"
    printf '%-16s %s\n' "Generated:" "$(date '+%Y-%m-%d %H:%M:%S %Z')"

    echo "------------------------------------------------------------"
}


# ==============================================================================
# print_health_summary
# ==============================================================================
#
# Purpose:
#     Print the final result after all health checks have completed.
#
# HEALTH_FAILURES and HEALTH_WARNINGS are global counters maintained by:
#
#     lib/health.sh
#
# The logic is:
#
#     failures > 0
#         -> server is unhealthy
#
#     failures == 0 and warnings > 0
#         -> server is healthy but needs attention
#
#     failures == 0 and warnings == 0
#         -> server is healthy
# ==============================================================================
print_health_summary() {

    echo "------------------------------------------------------------"

    printf '%-16s %s\n' "Failures:" "$HEALTH_FAILURES"
    printf '%-16s %s\n' "Warnings:" "$HEALTH_WARNINGS"

    echo

    # --------------------------------------------------------------------------
    # Bash arithmetic condition.
    #
    # (( ... ))
    #     Evaluates an integer expression.
    #
    # Example:
    #
    #     (( HEALTH_FAILURES > 0 ))
    #
    # means:
    #
    #     Is HEALTH_FAILURES greater than zero?
    # --------------------------------------------------------------------------
    if (( HEALTH_FAILURES > 0 )); then

        echo "Overall status: UNHEALTHY"

    elif (( HEALTH_WARNINGS > 0 )); then

        echo "Overall status: HEALTHY WITH WARNINGS"

    else

        echo "Overall status: HEALTHY"
    fi

    echo "============================================================"
    echo
}


# ==============================================================================
# command_main
# ==============================================================================
#
# This function is the public entry point for:
#
#     stoleus health
#
# lib/common.sh calls this function after sourcing this command file.
# ==============================================================================
command_main() {

    # Reset counters before every health run.
    #
    # This matters because command files are sourced into the same Bash process.
    HEALTH_FAILURES=0
    HEALTH_WARNINGS=0

    print_health_header


    # --------------------------------------------------------------------------
    # For now, we are only testing the reporting framework.
    #
    # These are temporary example checks.
    #
    # Later we will replace them with real checks such as:
    #
    #     check_time_sync
    #     check_ssh
    #     check_docker
    #     check_postgresql
    #     check_disk_space
    #
    # --------------------------------------------------------------------------
    check_time_sync
	check_ssh
	check_firewall
	check_docker
	check_docker_compose
	check_postgresql
	check_disk_usage
	check_memory
	check_github_runners
	check_network
	check_logical_volume_manager
	
    print_health_summary


    # --------------------------------------------------------------------------
    # Exit-code behavior
    #
    # If at least one health check failed:
    #
    #     return 1
    #
    # Otherwise:
    #
    #     return 0
    #
    # Remember:
    #
    #     0     = success
    #     non-0 = failure
    #
    # This will later allow:
    #
    #     systemd
    #     GitHub Actions
    #     monitoring
    #
    # to understand whether the server is healthy.
    # --------------------------------------------------------------------------
    if (( HEALTH_FAILURES > 0 )); then
        return 1
    fi

    return 0
}
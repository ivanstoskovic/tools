#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# Stoleus Logging Configuration
# ==============================================================================
#
# STOLEUS_LOG_LEVEL
#     Minimum level that should be displayed.
#
# Supported values:
#
#     DEBUG
#     INFO
#     WARNING
#     ERROR
#
# Default:
#
#     INFO
#
# STOLEUS_LOG_CONTEXT
#     Optional name of the currently executing component or subsystem.
#
# Examples:
#
#     docker
#     github-runner
#     pipeline
#
# STOLEUS_COLOR_MODE
#     Controls ANSI terminal colors.
#
# Supported values:
#
#     auto
#         Enable colors only when stderr is connected to a terminal.
#
#     always
#         Always emit colors.
#
#     never
#         Never emit colors.
#
# The standard NO_COLOR environment variable also disables colors.
# ==============================================================================
STOLEUS_LOG_LEVEL="${STOLEUS_LOG_LEVEL:-INFO}"
STOLEUS_LOG_CONTEXT="${STOLEUS_LOG_CONTEXT:-}"
STOLEUS_COLOR_MODE="${STOLEUS_COLOR_MODE:-auto}"



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
# set_log_context
# ==============================================================================
#
# Purpose:
#     Set the component or subsystem name included in subsequent log messages.
#
# Usage:
#
#     set_log_context "docker"
#
# Result:
#
#     [2026-08-02 15:42:18] INFO     [docker] Starting Docker setup.
# ==============================================================================
set_log_context() {

    local context="${1:-}"


    if [[ -z "$context" ]]; then

        log_error "set_log_context was called without a context name."

        return 2
    fi


    STOLEUS_LOG_CONTEXT="$context"

    return 0
}


# ==============================================================================
# get_timestamp
# ==============================================================================
#
# Purpose:
#     Return the current local date and time in a consistent format.
#
# Output:
#
#     2026-08-02 15:42:18
#
# stdout:
#     Reserved for the timestamp result.
# ==============================================================================
get_timestamp() {

    date '+%Y-%m-%d %H:%M:%S'
}


# ==============================================================================
# log_message
# ==============================================================================
#
# Purpose:
#     Format and print one Stoleus log message.
#
# Usage:
#
#     log_message "INFO" "Starting Docker setup."
#
# Output format:
#
#     [2026-08-02 15:42:18] INFO     [docker] Starting Docker setup.
#
# Important:
#
#     All log messages are written to stderr.
#
#     stdout remains available for:
#
#         - function return values
#         - generated paths
#         - service names
#         - command output intended for the caller
# ==============================================================================
log_message() {

    local level="${1:-}"
    local message="${2:-}"

	local safe_message
    local timestamp
    local normalized_level
    local context_part=""
    local color_start=""
    local color_reset=""


    if [[ -z "$level" ]]; then

        printf 'ERROR: log_message was called without a level.\n' >&2

        return 2
    fi


    if [[ -z "$message" ]]; then

        printf 'ERROR: log_message was called without a message.\n' >&2

        return 2
    fi


    if ! should_log_level "$level"; then

        local filter_result=$?

        if (( filter_result == 1 )); then

            return 0
        fi

        return "$filter_result"
    fi


    timestamp="$(get_timestamp)" || {

        printf 'ERROR: Failed to generate log timestamp.\n' >&2

        return 1
    }


    normalized_level="${level^^}"


    if [[ "$normalized_level" == "WARN" ]]; then

        normalized_level="WARNING"
    fi


    if [[ -n "$STOLEUS_LOG_CONTEXT" ]]; then

        context_part=" [${STOLEUS_LOG_CONTEXT}]"
    fi


    if should_use_log_colors; then

        color_start="$(get_log_level_color "$normalized_level")"
        color_reset=$'\033[0m'
    fi
	
	if ! safe_message="$(
		redact_text "$message"
	)"; then

		safe_message="$message"
	fi


    printf \
        '[%s] %b%-8s%b%s %s\n' \
        "$timestamp" \
        "$color_start" \
        "$normalized_level" \
        "$color_reset" \
        "$context_part" \
        "$safe_message" >&2

    return 0
}



# ==============================================================================
# clear_log_context
# ==============================================================================
#
# Purpose:
#     Remove the current logging context.
# ==============================================================================
clear_log_context() {

    STOLEUS_LOG_CONTEXT=""

    return 0
}


# ==============================================================================
# get_log_level_priority
# ==============================================================================
#
# Purpose:
#     Map a textual log level to a numeric priority.
#
# Lower numbers are more verbose.
#
# Priorities:
#
#     DEBUG   = 10
#     INFO    = 20
#     SUCCESS = 20
#     WARNING = 30
#     ERROR   = 40
#
# stdout:
#     Reserved for the numeric priority.
# ==============================================================================
get_log_level_priority() {

    local level="${1:-}"


    case "${level^^}" in

        DEBUG)

            printf '10\n'
            ;;

        INFO|SUCCESS)

            printf '20\n'
            ;;

        WARNING|WARN)

            printf '30\n'
            ;;

        ERROR)

            printf '40\n'
            ;;

        *)

            return 1
            ;;
    esac
}


# ==============================================================================
# should_log_level
# ==============================================================================
#
# Purpose:
#     Decide whether a message should be displayed according to the configured
#     minimum log level.
#
# Return codes:
#
#     0 = display the message
#     1 = suppress the message
#     2 = invalid log-level configuration
# ==============================================================================
should_log_level() {

    local message_level="${1:-}"

    local configured_priority
    local message_priority


    if ! configured_priority="$(
        get_log_level_priority "$STOLEUS_LOG_LEVEL"
    )"; then

        printf \
            'ERROR: Invalid STOLEUS_LOG_LEVEL: %s\n' \
            "$STOLEUS_LOG_LEVEL" >&2

        return 2
    fi


    if ! message_priority="$(
        get_log_level_priority "$message_level"
    )"; then

        printf \
            'ERROR: Invalid message log level: %s\n' \
            "$message_level" >&2

        return 2
    fi


    (( message_priority >= configured_priority ))
}


# ==============================================================================
# should_use_log_colors
# ==============================================================================
#
# Purpose:
#     Determine whether ANSI colors should be emitted.
#
# Return codes:
#
#     0 = use colors
#     1 = do not use colors
# ==============================================================================
should_use_log_colors() {

    # --------------------------------------------------------------------------
    # NO_COLOR is a widely used convention for disabling terminal colors.
    # --------------------------------------------------------------------------
    if [[ -n "${NO_COLOR:-}" ]]; then

        return 1
    fi


    case "${STOLEUS_COLOR_MODE,,}" in

        always)

            return 0
            ;;

        never)

            return 1
            ;;

        auto)

            [[ -t 2 ]]
            ;;

        *)

            printf \
                'ERROR: Invalid STOLEUS_COLOR_MODE: %s\n' \
                "$STOLEUS_COLOR_MODE" >&2

            return 1
            ;;
    esac
}


# ==============================================================================
# get_log_level_color
# ==============================================================================
#
# Purpose:
#     Return the ANSI color code associated with a log level.
#
# stdout:
#     Reserved for the color-code result.
# ==============================================================================
get_log_level_color() {

    local level="${1:-}"


    case "${level^^}" in

        DEBUG)

            printf '\033[2m'
            ;;

        INFO)

            printf '\033[36m'
            ;;

        SUCCESS)

            printf '\033[32m'
            ;;

        WARNING|WARN)

            printf '\033[33m'
            ;;

        ERROR)

            printf '\033[31m'
            ;;

        *)

            printf ''
            ;;
    esac
}


# ==============================================================================
# Logging Convenience Functions
# ==============================================================================
#
# These functions preserve the existing Stoleus logging API.
#
# Existing component code does not need to change.
# ==============================================================================

log_debug() {

    log_message "DEBUG" "${1:-}"
}


log_info() {

    log_message "INFO" "${1:-}"
}


log_success() {

    log_message "SUCCESS" "${1:-}"
}


log_warning() {

    log_message "WARNING" "${1:-}"
}


log_error() {

    log_message "ERROR" "${1:-}"
}


# ==============================================================================
# print_error
# ==============================================================================
#
# Purpose:
#     Preserve compatibility with existing code that still calls print_error().
# ==============================================================================
print_error() {

    log_error "$*"
}


#!/usr/bin/env bash

set -Eeuo pipefail


# ==============================================================================
# get_monotonic_time
# ==============================================================================
#
# Purpose:
#     Return a timestamp suitable for measuring elapsed execution time.
#
# Why not use the normal date/time:
#
#     The system clock can move forwards or backwards because of NTP
#     synchronization or manual changes.
#
#     Bash SECONDS provides elapsed shell time and is suitable for simple
#     duration measurements.
#
# Output:
#     Number of seconds since the current Bash process started.
# ==============================================================================
get_monotonic_time() {

    printf '%s\n' "$SECONDS"
}


# ==============================================================================
# format_duration
# ==============================================================================
#
# Purpose:
#     Format an elapsed number of seconds for display.
#
# Arguments:
#
#     $1 = duration in whole seconds
#
# Examples:
#
#     4     -> 4s
#     75    -> 1m 15s
#     3672  -> 1h 1m 12s
# ==============================================================================
format_duration() {

    local total_seconds="${1:-}"

    local hours
    local minutes
    local seconds


    if [[ ! "$total_seconds" =~ ^[0-9]+$ ]]; then

        log_error "Invalid duration value: $total_seconds"

        return 2
    fi


    hours=$((total_seconds / 3600))
    minutes=$(((total_seconds % 3600) / 60))
    seconds=$((total_seconds % 60))


    if (( hours > 0 )); then

        printf '%dh %dm %ds\n' \
            "$hours" \
            "$minutes" \
            "$seconds"

    elif (( minutes > 0 )); then

        printf '%dm %ds\n' \
            "$minutes" \
            "$seconds"

    else

        printf '%ds\n' "$seconds"
    fi
}


# ==============================================================================
# log_failure_summary
# ==============================================================================
#
# Purpose:
#     Print a consistent command-failure summary.
# ==============================================================================
log_failure_summary() {

    local operation="${1:-Unknown operation}"
    local exit_code="${2:-1}"
    local duration="${3:-unknown}"
    local suggestion="${4:-Review the preceding error messages.}"


    log_error "Operation failed."

    printf '%s\n' \
        "------------------------------------------------------------" >&2

    printf 'Operation:  %s\n' "$operation" >&2
    printf 'Exit code:  %s\n' "$exit_code" >&2
    printf 'Duration:   %s\n' "$duration" >&2
    printf 'Next step:  %s\n' "$suggestion" >&2

    printf '%s\n' \
        "------------------------------------------------------------" >&2
}

# ==============================================================================
# run_with_log_context
# ==============================================================================
#
# Purpose:
#     Execute a function with logging context and duration tracking.
#
# Usage:
#
#     run_with_log_context "docker" setup_docker
#
# Arguments:
#
#     $1 = logging context
#     $2 = function to execute
#     remaining arguments are passed to that function
# ==============================================================================
run_with_log_context() {

    local context="${1:-}"
    local function_name="${2:-}"

    local started_at
    local finished_at
    local duration
    local exit_code=0


    if [[ -z "$context" ]]; then

        log_error "run_with_log_context requires a context."

        return 2
    fi


    if [[ -z "$function_name" ]]; then

        log_error "run_with_log_context requires a function name."

        return 2
    fi


    if ! declare -F "$function_name" >/dev/null 2>&1; then

        log_error "Function does not exist: $function_name"

        return 2
    fi


    shift 2

    set_log_context "$context"

    started_at="$(get_monotonic_time)"


    "$function_name" "$@" || exit_code=$?


    finished_at="$(get_monotonic_time)"

    duration="$(
        format_duration "$((finished_at - started_at))"
    )"


    if (( exit_code == 0 )); then

        log_success "Command completed in ${duration}."

    else

		log_failure_summary \
			"$context" \
			"$exit_code" \
			"$duration" \
			"Review the error immediately above and rerun after correcting it."
    fi


    clear_log_context

    return "$exit_code"
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


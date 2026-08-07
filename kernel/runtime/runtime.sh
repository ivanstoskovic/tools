#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Runtime Utilities
# ==============================================================================
#
# Purpose:
#     Provide shared, deterministic runtime primitives used by execution-like
#     kernel subsystems.
#
# Internal API:
#
#     stoleus_runtime_initialize
#     stoleus_runtime_now
#     stoleus_runtime_now_ms
#     stoleus_runtime_duration_ms
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Load Guard
# ==============================================================================

if [[ "${STOLEUS_RUNTIME_LOADED:-false}" == "true" ]]; then
    return 0
fi


STOLEUS_RUNTIME_LOADED="true"


# ==============================================================================
# stoleus_runtime_now
# ==============================================================================
#
# Output:
#
#     UTC timestamp in YYYY-MM-DDTHH:MM:SSZ format.
# ==============================================================================

stoleus_runtime_now() {

    date -u '+%Y-%m-%dT%H:%M:%SZ'

    return $?
}


# ==============================================================================
# stoleus_runtime_now_ms
# ==============================================================================
#
# Output:
#
#     Milliseconds since the Unix epoch.
#
# GNU date supports %3N. The fallback preserves compatibility on platforms
# whose date implementation does not support nanosecond formatting.
# ==============================================================================

stoleus_runtime_now_ms() {

    local timestamp=""


    if timestamp="$(date +%s%3N 2>/dev/null)" &&
       [[ "$timestamp" =~ ^[0-9]+$ ]]; then

        printf '%s\n' "$timestamp"

        return 0
    fi


    timestamp="$(date +%s)" || return $?


    if [[ ! "$timestamp" =~ ^[0-9]+$ ]]; then

        printf '%s\n' \
            "ERROR: Runtime clock returned a nonnumeric epoch value." >&2

        return 6
    fi


    printf '%s\n' "$((timestamp * 1000))"

    return 0
}


# ==============================================================================
# stoleus_runtime_create_id
# ==============================================================================
#
# Arguments:
#
#     $1 = identifier prefix
#     $2 = optional discriminator
#
# Output:
#
#     <prefix>-<UTC timestamp>-<PID>[-<discriminator>]
# ==============================================================================

stoleus_runtime_create_id() {

    local prefix="${1:-}"
    local discriminator="${2:-}"

    local timestamp=""


    if [[ -z "$prefix" ||
          ! "$prefix" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then

        printf '%s\n' \
            "ERROR: Runtime ID creation requires a valid prefix." >&2

        return 2
    fi


    if [[ -n "$discriminator" &&
          ! "$discriminator" =~ ^[a-zA-Z0-9_-]+$ ]]; then

        printf '%s\n' \
            "ERROR: Runtime ID discriminator is invalid: ${discriminator}" \
            >&2

        return 2
    fi


    timestamp="$(
        date -u '+%Y%m%dT%H%M%S%N'
    )" || return $?


    if [[ ! "$timestamp" =~ ^[0-9]{8}T[0-9]{6}[0-9]+$ ]]; then

        # Some date implementations may not support %N.
        timestamp="$(
            date -u '+%Y%m%dT%H%M%S'
        )" || return $?


        if [[ ! "$timestamp" =~ ^[0-9]{8}T[0-9]{6}$ ]]; then

            printf '%s\n' \
                "ERROR: Runtime clock returned an invalid ID timestamp." >&2

            return 6
        fi
    fi


    if [[ -n "$discriminator" ]]; then

        printf '%s-%s-%s-%s\n' \
            "$prefix" \
            "$timestamp" \
            "$$" \
            "$discriminator"

    else

        printf '%s-%s-%s\n' \
            "$prefix" \
            "$timestamp" \
            "$$"
    fi


    return 0
}


# ==============================================================================
# stoleus_runtime_duration_ms
# ==============================================================================
#
# Arguments:
#
#     $1 = start time in epoch milliseconds
#     $2 = finish time in epoch milliseconds
#
# Negative durations are normalized to zero so a clock adjustment cannot create
# invalid result metadata.
# ==============================================================================

stoleus_runtime_duration_ms() {

    local started_ms="${1:-}"
    local finished_ms="${2:-}"

    local duration_ms=0


    if [[ -z "$started_ms" ||
          ! "$started_ms" =~ ^[0-9]+$ ||
          -z "$finished_ms" ||
          ! "$finished_ms" =~ ^[0-9]+$ ]]; then

        printf '%s\n' \
            "ERROR: Runtime duration calculation requires numeric timestamps." \
            >&2

        return 2
    fi


    duration_ms="$((finished_ms - started_ms))"


    if (( duration_ms < 0 )); then
        duration_ms=0
    fi


    printf '%s\n' "$duration_ms"

    return 0
}


# ==============================================================================
# stoleus_runtime_initialize
# ==============================================================================

stoleus_runtime_initialize() {

    if [[ "${STOLEUS_RUNTIME_INITIALIZED:-false}" == "true" ]]; then
        return 0
    fi


    STOLEUS_RUNTIME_INITIALIZED="true"


    return 0
}

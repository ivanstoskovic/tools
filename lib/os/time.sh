#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Time Verification
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# verify_remote_clock_skew
# ==============================================================================
#
# Purpose:
#     Compare the local system clock with the HTTP Date header returned by a
#     trusted HTTPS endpoint.
#
# Usage:
#
#     verify_remote_clock_skew \
#         "https://github.com" \
#         "5"
#
# Arguments:
#
#     $1 = HTTPS URL used as the independent time reference
#     $2 = maximum permitted difference in seconds
#
# Return codes:
#
#     0 = clock difference is within the permitted threshold
#     2 = invalid arguments
#     3 = required command is unavailable
#     4 = remote request failed
#     7 = clock-skew verification failed
# ==============================================================================
verify_remote_clock_skew() {

    local reference_url="${1:-https://github.com}"
    local maximum_skew_seconds="${2:-5}"

    local response_headers
    local remote_date
    local remote_epoch
    local local_epoch
    local clock_difference


    log_info \
        "Verifying system clock against external reference: $reference_url"


    # --------------------------------------------------------------------------
    # Validate arguments.
    # --------------------------------------------------------------------------
    if [[ "$reference_url" != https://* ]]; then

        log_error \
            "Clock verification requires an HTTPS reference URL."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if [[ ! "$maximum_skew_seconds" =~ ^[0-9]+$ ]]; then

        log_error \
            "Maximum clock skew must be a non-negative whole number."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    # --------------------------------------------------------------------------
    # Verify required commands.
    # --------------------------------------------------------------------------
    if ! command -v curl >/dev/null 2>&1; then

        log_error "Clock verification requires curl."

        return "${STOLEUS_EXIT_DEPENDENCY:-3}"
    fi


    if ! command -v date >/dev/null 2>&1; then

        log_error "Clock verification requires date."

        return "${STOLEUS_EXIT_DEPENDENCY:-3}"
    fi


    # --------------------------------------------------------------------------
    # Request only HTTP headers.
    #
    # --head
    #     Request headers without downloading the response body.
    #
    # --location
    #     Follow redirects.
    #
    # --fail
    #     Treat HTTP error responses as failures.
    #
    # --max-time
    #     Prevent the verification from hanging indefinitely.
    # --------------------------------------------------------------------------
    if ! response_headers="$(
        curl \
            --head \
            --location \
            --fail \
            --silent \
            --show-error \
            --max-time 15 \
            "$reference_url"
    )"; then

        log_error \
            "Failed to retrieve external clock reference: $reference_url"

        return "${STOLEUS_EXIT_NETWORK:-4}"
    fi


    # --------------------------------------------------------------------------
    # A redirected request may contain multiple Date headers.
    #
    # Use the final Date header returned by the destination server.
    # --------------------------------------------------------------------------
    remote_date="$(
        printf '%s\n' "$response_headers" |
            grep -i '^date:' |
            tail -n 1 |
            sed -E 's/^[Dd][Aa][Tt][Ee]:[[:space:]]*//' |
            tr -d '\r'
    )"


    if [[ -z "$remote_date" ]]; then

        log_error \
            "External response did not contain a readable Date header."

        return "${STOLEUS_EXIT_VERIFICATION:-7}"
    fi


    # --------------------------------------------------------------------------
    # Convert both timestamps to Unix epoch seconds.
    #
    # Ubuntu's GNU date understands standard HTTP-date values such as:
    #
    #     Sun, 03 Aug 2026 00:44:37 GMT
    # --------------------------------------------------------------------------
    if ! remote_epoch="$(
        date --date="$remote_date" '+%s'
    )"; then

        log_error \
            "Could not parse external Date header: $remote_date"

        return "${STOLEUS_EXIT_VERIFICATION:-7}"
    fi


    local_epoch="$(date -u '+%s')"


    # --------------------------------------------------------------------------
    # Calculate the absolute difference.
    # --------------------------------------------------------------------------
    clock_difference=$((local_epoch - remote_epoch))


    if (( clock_difference < 0 )); then

        clock_difference=$((-clock_difference))
    fi


    log_debug "Local epoch: $local_epoch"
    log_debug "Remote epoch: $remote_epoch"
    log_debug "Clock difference: ${clock_difference}s"


    if (( clock_difference > maximum_skew_seconds )); then

        log_error \
            "System clock differs from external time by ${clock_difference}s."

        log_error \
            "Maximum permitted clock difference is ${maximum_skew_seconds}s."

        return "${STOLEUS_EXIT_VERIFICATION:-7}"
    fi


    log_success \
        "External clock verification passed; difference is ${clock_difference}s."

    return "${STOLEUS_EXIT_SUCCESS:-0}"
}
#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# write_text
# ==============================================================================
#
# Purpose:
#     Write text to stdout, optionally ensuring exactly one final newline.
#
# Arguments:
#
#     $1 = text
#     $2 = ensure final newline: true or false
# ==============================================================================
write_text() {

    local text="${1-}"
    local ensure_newline="${2:-true}"


    if [[ "$ensure_newline" != "true" ]] &&
       [[ "$ensure_newline" != "false" ]]; then

        log_error "ensure_newline must be true or false."

        return 2
    fi


    if [[ "$ensure_newline" == "false" ]]; then

        printf '%s' "$text"

        return 0
    fi


    # Remove all trailing newline characters, then add exactly one.
    while [[ "$text" == *$'\n' ]]; do

        text="${text%$'\n'}"
    done


    printf '%s\n' "$text"
}
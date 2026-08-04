#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Version Information
# ==============================================================================
#
# Purpose:
#     Provide access to the installed Stoleus version.
#
# The VERSION file is the single source of truth.
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# read_version
# ==============================================================================
#
# Purpose:
#     Read and normalize the current Stoleus version.
#
# Example VERSION content:
#
#     1.0.0
#
# Output:
#
#     1.0.0
# ==============================================================================
read_version() {

    if [[ ! -r "$STOLEUS_VERSION_FILE" ]]; then

        log_error \
            "Version file is missing or unreadable: $STOLEUS_VERSION_FILE"

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    tr -d '[:space:]' < "$STOLEUS_VERSION_FILE"

    return "${STOLEUS_EXIT_SUCCESS:-0}"
}
#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Text Encoding
# ==============================================================================

set -Eeuo pipefail

validate_utf8() {
    local text="${1-}"

    if ! command -v iconv >/dev/null 2>&1; then

		log_debug \
			"iconv is unavailable; UTF-8 validation was skipped."

		return "${STOLEUS_EXIT_SUCCESS:-0}"
	fi

    if ! printf '%s' "$text" | iconv --from-code=UTF-8 --to-code=UTF-8 >/dev/null 2>&1; then
        log_error "Text contains invalid UTF-8 data."
        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi

    return "${STOLEUS_EXIT_SUCCESS:-0}"
}

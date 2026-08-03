#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Text Normalization
# ==============================================================================

set -Eeuo pipefail

normalize_line_endings() {
    local text="${1-}"
    local line_endings="${2:-LF}"

    case "${line_endings^^}" in
        LF)
            text="${text//$'\r\n'/$'\n'}"
            text="${text//$'\r'/$'\n'}"
            ;;
        CRLF)
            text="${text//$'\r\n'/$'\n'}"
            text="${text//$'\r'/$'\n'}"
            text="${text//$'\n'/$'\r\n'}"
            ;;
        *)
            log_error "Unsupported line-ending style: $line_endings"
            log_error "Supported values: LF, CRLF"
            return "${STOLEUS_EXIT_USAGE:-2}"
            ;;
    esac

    printf '%s' "$text"
    return "${STOLEUS_EXIT_SUCCESS:-0}"
}

strip_trailing_whitespace() {
    local text="${1-}"
    printf '%s' "$text" | sed -E 's/[[:blank:]]+$//'
    return "${STOLEUS_EXIT_SUCCESS:-0}"
}

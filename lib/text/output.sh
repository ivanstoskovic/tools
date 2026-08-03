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
    local ending_mode="${2:-newline}"
    local line_endings="${3:-LF}"
    local should_strip_trailing_whitespace="${4:-false}"
    local should_validate_utf8="${5:-true}"
    local normalized_text
    local newline_sequence

    case "${ending_mode,,}" in
        true) ending_mode="newline" ;;
        false) ending_mode="none" ;;
        none|newline|blank-line) ;;
        *)
            log_error "Unsupported text ending mode: $ending_mode"
            log_error "Supported values: none, newline, blank-line"
            return "${STOLEUS_EXIT_USAGE:-2}"
            ;;
    esac

    case "${line_endings^^}" in
        LF) newline_sequence=$'\n' ;;
        CRLF) newline_sequence=$'\r\n' ;;
        *)
            log_error "Unsupported line-ending style: $line_endings"
            log_error "Supported values: LF, CRLF"
            return "${STOLEUS_EXIT_USAGE:-2}"
            ;;
    esac

    if [[ "$should_strip_trailing_whitespace" != "true" ]] && [[ "$should_strip_trailing_whitespace" != "false" ]]; then
        log_error "strip_trailing_whitespace must be true or false."
        return "${STOLEUS_EXIT_USAGE:-2}"
    fi

    if [[ "$should_validate_utf8" != "true" ]] && [[ "$should_validate_utf8" != "false" ]]; then
        log_error "validate_utf8 must be true or false."
        return "${STOLEUS_EXIT_USAGE:-2}"
    fi

    text="${text//$'\r\n'/$'\n'}"
    text="${text//$'\r'/$'\n'}"

    while [[ "$text" == *$'\n' ]]; do
        text="${text%$'\n'}"
    done

    if [[ "$should_strip_trailing_whitespace" == "true" ]]; then
        normalized_text="$(strip_trailing_whitespace "$text")"
    else
        normalized_text="$text"
    fi

    if [[ "$should_validate_utf8" == "true" ]]; then
        validate_utf8 "$normalized_text" || return $?
    fi

    if [[ "${line_endings^^}" == "CRLF" ]]; then
        normalized_text="${normalized_text//$'\n'/$'\r\n'}"
    fi

    case "$ending_mode" in
        none) printf '%s' "$normalized_text" ;;
        newline) printf '%s%s' "$normalized_text" "$newline_sequence" ;;
        blank-line) printf '%s%s%s' "$normalized_text" "$newline_sequence" "$newline_sequence" ;;
    esac

    return "${STOLEUS_EXIT_SUCCESS:-0}"
}
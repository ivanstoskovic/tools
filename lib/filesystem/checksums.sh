#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# verify_sha256
# ==============================================================================
#
# Purpose:
#     Verify that a file matches an expected SHA-256 checksum.
#
# Usage:
#
#     verify_sha256 \
#         "/tmp/application.tar.gz" \
#         "0123456789abcdef..."
#
# Arguments:
#
#     $1 = file path
#     $2 = expected SHA-256 checksum
#
# The function supports:
#
#     sha256sum
#
# and falls back to:
#
#     shasum -a 256
#
# Return codes:
#
#     0 = checksum matches
#     1 = checksum does not match or could not be calculated
#     2 = invalid arguments
# ==============================================================================
verify_sha256() {

    local file_path="${1:-}"
    local expected_checksum="${2:-}"

    local actual_checksum
    local checksum_pattern='^[A-Fa-f0-9]{64}$'


    log_info "Verifying SHA-256 checksum."


    if [[ -z "$file_path" ]]; then

        log_error "verify_sha256 was called without a file path."

        return 2
    fi


    if [[ -z "$expected_checksum" ]]; then

        log_error "verify_sha256 was called without an expected checksum."

        return 2
    fi


    if [[ ! -f "$file_path" ]]; then

        log_error "Checksum target does not exist: $file_path"

        return 1
    fi


    if [[ ! "$expected_checksum" =~ $checksum_pattern ]]; then

        log_error "Invalid SHA-256 checksum format."

        return 2
    fi


    expected_checksum="${expected_checksum,,}"


    if command -v sha256sum >/dev/null 2>&1; then

        actual_checksum="$(
            sha256sum -- "$file_path" |
                awk '{print $1}'
        )"

    elif command -v shasum >/dev/null 2>&1; then

        actual_checksum="$(
            shasum -a 256 -- "$file_path" |
                awk '{print $1}'
        )"

    else

        log_error "Neither sha256sum nor shasum is available."

        return 1
    fi


    actual_checksum="${actual_checksum,,}"


    if [[ "$actual_checksum" != "$expected_checksum" ]]; then

        log_error "SHA-256 checksum verification failed."
        log_error "Expected: $expected_checksum"
        log_error "Actual:   $actual_checksum"

        return 1
    fi


    log_success "SHA-256 checksum verified successfully."

    return 0
}
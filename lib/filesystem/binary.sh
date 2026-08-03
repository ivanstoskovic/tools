#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Binary File Helpers
# ==============================================================================

set -Eeuo pipefail

write_binary_file() {
    local source_path="${1:-}"
    local destination_path="${2:-}"
    local destination_directory
    local temporary_file

    if [[ -z "$source_path" ]]; then
        log_error "write_binary_file requires a source path."
        return "${STOLEUS_EXIT_USAGE:-2}"
    fi

    if [[ -z "$destination_path" ]]; then
        log_error "write_binary_file requires a destination path."
        return "${STOLEUS_EXIT_USAGE:-2}"
    fi

    if [[ ! -f "$source_path" ]]; then
        log_error "Binary source file does not exist: $source_path"
        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi

    destination_directory="$(dirname -- "$destination_path")"
    if [[ ! -d "$destination_directory" ]]; then
        log_error "Binary destination directory does not exist: $destination_directory"
        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi

    temporary_file="$(mktemp "${destination_directory}/.stoleus-binary.XXXXXX")" || {
        log_error "Failed to create a temporary binary file."
        return "${STOLEUS_EXIT_FAILURE:-1}"
    }

    if ! cp -- "$source_path" "$temporary_file"; then
        rm -f -- "$temporary_file"
        log_error "Failed to copy binary data from: $source_path"
        return "${STOLEUS_EXIT_FAILURE:-1}"
    fi

    if ! mv -f -- "$temporary_file" "$destination_path"; then
        rm -f -- "$temporary_file"
        log_error "Failed to replace binary destination: $destination_path"
        return "${STOLEUS_EXIT_FAILURE:-1}"
    fi

    log_success "Binary file written successfully: $destination_path"
    return "${STOLEUS_EXIT_SUCCESS:-0}"
}

write_binary_stream() {
    local destination_path="${1:-}"
    local destination_directory
    local temporary_file

    if [[ -z "$destination_path" ]]; then
        log_error "write_binary_stream requires a destination path."
        return "${STOLEUS_EXIT_USAGE:-2}"
    fi

    destination_directory="$(dirname -- "$destination_path")"
    if [[ ! -d "$destination_directory" ]]; then
        log_error "Binary destination directory does not exist: $destination_directory"
        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi

    temporary_file="$(mktemp "${destination_directory}/.stoleus-binary.XXXXXX")" || {
        log_error "Failed to create a temporary binary file."
        return "${STOLEUS_EXIT_FAILURE:-1}"
    }

    if ! cat > "$temporary_file"; then
        rm -f -- "$temporary_file"
        log_error "Failed to read binary data from stdin."
        return "${STOLEUS_EXIT_FAILURE:-1}"
    fi

    if ! mv -f -- "$temporary_file" "$destination_path"; then
        rm -f -- "$temporary_file"
        log_error "Failed to replace binary destination: $destination_path"
        return "${STOLEUS_EXIT_FAILURE:-1}"
    fi

    log_success "Binary stream written successfully: $destination_path"
    return "${STOLEUS_EXIT_SUCCESS:-0}"
}

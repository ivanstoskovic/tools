#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# backup_file
# ==============================================================================
#
# Purpose:
#     Copy an existing file to a specified backup location.
#
# Usage:
#
#     backup_file \
#         "/etc/application/config.conf" \
#         "/etc/application/config.conf.bak"
#
# Arguments:
#
#     $1 = source file
#     $2 = backup file
#
# File permissions, ownership, and timestamps are preserved where supported.
# ==============================================================================
backup_file() {

    local source_path="${1:-}"
    local backup_path="${2:-}"
    local backup_directory


    log_info "Preparing file backup."


    if [[ -z "$source_path" ]]; then

        log_error "backup_file was called without a source path."

        return 2
    fi


    if [[ -z "$backup_path" ]]; then

        log_error "backup_file was called without a backup path."

        return 2
    fi


    require_command "cp" || return 1
    require_command "dirname" || return 1


    if [[ ! -f "$source_path" ]]; then

        log_error "Backup source does not exist: $source_path"

        return 1
    fi


    backup_directory="$(dirname -- "$backup_path")"


    if [[ ! -d "$backup_directory" ]]; then

        log_error "Backup directory does not exist: $backup_directory"

        return 1
    fi


    log_info "Backing up file: $source_path"
    log_info "Backup destination: $backup_path"


    if ! cp \
        --archive \
        --force \
        -- "$source_path" "$backup_path"; then

        log_error "Failed to back up file: $source_path"

        return 1
    fi


    if [[ ! -f "$backup_path" ]]; then

        log_error "Backup file could not be verified: $backup_path"

        return 1
    fi


    log_success "File backed up successfully: $backup_path"

    return 0
}


# ==============================================================================
# restore_file
# ==============================================================================
#
# Purpose:
#     Restore a file from a previously created backup.
#
# Usage:
#
#     restore_file \
#         "/etc/application/config.conf.bak" \
#         "/etc/application/config.conf"
#
# Arguments:
#
#     $1 = backup file
#     $2 = destination file
# ==============================================================================
restore_file() {

    local backup_path="${1:-}"
    local destination_path="${2:-}"
    local destination_directory


    log_info "Preparing file restoration."


    if [[ -z "$backup_path" ]]; then

        log_error "restore_file was called without a backup path."

        return 2
    fi


    if [[ -z "$destination_path" ]]; then

        log_error "restore_file was called without a destination path."

        return 2
    fi


    require_command "cp" || return 1
    require_command "dirname" || return 1


    if [[ ! -f "$backup_path" ]]; then

        log_error "Backup file does not exist: $backup_path"

        return 1
    fi


    destination_directory="$(dirname -- "$destination_path")"


    if [[ ! -d "$destination_directory" ]]; then

        log_error \
            "Restore destination directory does not exist: $destination_directory"

        return 1
    fi


    log_info "Restoring backup: $backup_path"
    log_info "Restore destination: $destination_path"


    if ! cp \
        --archive \
        --force \
        -- "$backup_path" "$destination_path"; then

        log_error "Failed to restore file: $destination_path"

        return 1
    fi


    log_success "File restored successfully: $destination_path"

    return 0
}

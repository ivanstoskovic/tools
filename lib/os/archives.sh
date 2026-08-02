#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# extract_tar_gz
# ==============================================================================
#
# Purpose:
#     Extract a gzip-compressed TAR archive into an existing directory.
#
# Usage:
#
#     extract_tar_gz \
#         "/tmp/application.tar.gz" \
#         "/opt/application"
#
# Arguments:
#
#     $1 = archive path
#     $2 = destination directory
#
# Return codes:
#
#     0 = archive extracted successfully
#     1 = extraction or verification failed
#     2 = invalid arguments
# ==============================================================================
extract_tar_gz() {

    local archive_path="${1:-}"
    local destination_directory="${2:-}"


    log_info "Preparing TAR.GZ archive extraction."


    if [[ -z "$archive_path" ]]; then

        log_error "extract_tar_gz was called without an archive path."

        return 2
    fi


    if [[ -z "$destination_directory" ]]; then

        log_error "extract_tar_gz was called without a destination directory."

        return 2
    fi


    require_command "tar" || return 1


    if [[ ! -f "$archive_path" ]]; then

        log_error "Archive does not exist: $archive_path"

        return 1
    fi


    if [[ ! -s "$archive_path" ]]; then

        log_error "Archive is empty: $archive_path"

        return 1
    fi


    if [[ ! -d "$destination_directory" ]]; then

        log_error \
            "Archive destination directory does not exist: $destination_directory"

        return 1
    fi


    log_info "Extracting archive: $archive_path"
    log_info "Extraction destination: $destination_directory"


    if ! tar \
        --extract \
        --gzip \
        --file "$archive_path" \
        --directory "$destination_directory"; then

        log_error "Failed to extract archive: $archive_path"

        return 1
    fi


    log_success \
        "Archive extracted successfully: $destination_directory"

    return 0
}
#!/usr/bin/env bash

set -Eeuo pipefail


# ==============================================================================
# download_file
# ==============================================================================
#
# Purpose:
#     Download a file from an HTTPS URL to a specified destination.
#
# Usage:
#
#     download_file \
#         "https://example.com/archive.tar.gz" \
#         "/tmp/archive.tar.gz"
#
# Arguments:
#
#     $1 = source URL
#     $2 = destination file path
#
# Safety:
#
#     - accepts HTTPS URLs only;
#     - validates required arguments;
#     - requires the destination directory to exist;
#     - downloads into a temporary file first;
#     - moves the temporary file into place only after a successful download;
#     - removes partial downloads when an error occurs;
#     - does not suppress curl error messages.
#
# Why use a temporary file:
#
#     Writing directly to the final destination could leave a partial or corrupt
#     file if the network connection fails.
#
#     The final destination is updated only after curl completes successfully.
#
# Return codes:
#
#     0 = file downloaded successfully
#     1 = download or verification failed
#     2 = invalid arguments
# ==============================================================================
download_file() {

    local source_url="${1:-}"
    local destination_path="${2:-}"

    local destination_directory
    local temporary_file


    log_info "Preparing file download."


    # --------------------------------------------------------------------------
    # Validate required arguments.
    # --------------------------------------------------------------------------
    if [[ -z "$source_url" ]]; then

        log_error "download_file was called without a source URL."

        return 2
    fi


    if [[ -z "$destination_path" ]]; then

        log_error "download_file was called without a destination path."

        return 2
    fi


    # --------------------------------------------------------------------------
    # Restrict downloads to encrypted HTTPS connections.
    # --------------------------------------------------------------------------
    if [[ "$source_url" != https://* ]]; then

        log_error "Only HTTPS downloads are allowed: $source_url"

        return 2
    fi


    require_command "curl" || return 1
    require_command "dirname" || return 1
    require_command "mktemp" || return 1
    require_command "mv" || return 1
    require_command "rm" || return 1


    # --------------------------------------------------------------------------
    # Determine and validate the parent directory.
    #
    # The helper deliberately does not create directories automatically.
    # Directory creation belongs to the component or setup operation that owns
    # the destination.
    # --------------------------------------------------------------------------
    destination_directory="$(dirname -- "$destination_path")"


    if [[ ! -d "$destination_directory" ]]; then

        log_error \
            "Download destination directory does not exist: $destination_directory"

        return 1
    fi


    # --------------------------------------------------------------------------
    # Create the temporary file in the same directory as the final destination.
    #
    # This allows the final `mv` operation to remain on the same filesystem and
    # therefore behave atomically.
    # --------------------------------------------------------------------------
    if ! temporary_file="$(
        mktemp "${destination_directory}/.stoleus-download.XXXXXX"
    )"; then

        log_error "Failed to create a temporary download file."

        return 1
    fi


    log_info "Downloading: $source_url"
    log_info "Destination: $destination_path"


    # --------------------------------------------------------------------------
    # curl options:
    #
    #     --fail
    #         Treat HTTP 4xx and 5xx responses as failures.
    #
    #     --location
    #         Follow redirects.
    #
    #     --show-error
    #         Display useful errors even when silent mode is enabled.
    #
    #     --silent
    #         Hide the progress meter while preserving error output.
    #
    #     --output
    #         Write the response to the temporary file.
    # --------------------------------------------------------------------------
    if ! curl \
        --fail \
        --location \
        --silent \
        --show-error \
        --output "$temporary_file" \
        "$source_url"; then

        rm -f -- "$temporary_file"

        log_error "Failed to download file: $source_url"

        return 1
    fi


    # --------------------------------------------------------------------------
    # Reject an empty response before replacing the destination.
    # --------------------------------------------------------------------------
    if [[ ! -s "$temporary_file" ]]; then

        rm -f -- "$temporary_file"

        log_error "Downloaded file is empty: $source_url"

        return 1
    fi


    # --------------------------------------------------------------------------
    # Move the completed temporary file into its final location.
    # --------------------------------------------------------------------------
    if ! mv -f -- "$temporary_file" "$destination_path"; then

        rm -f -- "$temporary_file"

        log_error "Failed to move downloaded file to: $destination_path"

        return 1
    fi


    log_success "File downloaded successfully: $destination_path"

    return 0
}
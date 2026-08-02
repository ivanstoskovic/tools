#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Shared Common Functions
# ==============================================================================
#
# This file contains reusable functions shared by multiple Stoleus commands.
#
# It is loaded by:
#
#     bin/stoleus
#
# using:
#
#     source "${PROJECT_ROOT}/lib/common.sh"
#
# Shared logic belongs here so command files do not duplicate the same code.
#
# This follows the DRY principle:
#
#     Don't Repeat Yourself
#
# ==============================================================================


# ------------------------------------------------------------------------------
# Enable strict Bash behavior.
#
# -E
#     Preserve ERR traps inside functions and subshells.
#
# -e
#     Stop the script when an unexpected command fails.
#
# -u
#     Treat undefined variables as errors.
#
# -o pipefail
#     Make a pipeline fail if any important command inside it fails.
# ------------------------------------------------------------------------------
set -Eeuo pipefail


# ==============================================================================
# Shared Path Constants
# ==============================================================================
#
# PROJECT_ROOT is defined by bin/stoleus before this file is sourced.
#
# Example:
#
#     PROJECT_ROOT=/home/deployer/tools
#
# We use readonly because these paths should not change during execution.
# ==============================================================================


# ------------------------------------------------------------------------------
# Directory containing command implementation files.
#
# Example:
#
#     /home/deployer/tools/commands
# ------------------------------------------------------------------------------
readonly STOLEUS_COMMANDS_DIR="${PROJECT_ROOT}/commands"


# ------------------------------------------------------------------------------
# File containing the current project version.
#
# Example:
#
#     /home/deployer/tools/VERSION
# ------------------------------------------------------------------------------
readonly STOLEUS_VERSION_FILE="${PROJECT_ROOT}/VERSION"


# ==============================================================================
# Terminal Color Configuration
# ==============================================================================
#
# ANSI escape sequences allow supported terminals to display colored text.
#
# We use colors only when:
#
#     - stdout or stderr is connected to a terminal
#     - the NO_COLOR environment variable is not set
#     - the TERM environment variable is not "dumb"
#
# This prevents control characters from appearing in:
#
#     - redirected files
#     - CI/CD logs without terminal support
#     - cron output
#     - systemd logs
#
# The user can explicitly disable colors with:
#
#     NO_COLOR=1 stoleus health
#
# or:
#
#     sudo NO_COLOR=1 stoleus setup server app
#
# `$'\033[...m'`
#     Bash ANSI-C quoting used to create terminal escape sequences.
#
# Color codes:
#
#     31 = red
#     32 = green
#     33 = yellow
#     36 = cyan
#      0 = reset terminal formatting
# ==============================================================================

if {
    [[ -t 1 ]] || [[ -t 2 ]]
} && [[ -z "${NO_COLOR:-}" ]] && [[ "${TERM:-}" != "dumb" ]]; then

    readonly COLOR_RED=$'\033[0;31m'
    readonly COLOR_GREEN=$'\033[0;32m'
    readonly COLOR_YELLOW=$'\033[0;33m'
    readonly COLOR_CYAN=$'\033[0;36m'
    readonly COLOR_RESET=$'\033[0m'

else

    # --------------------------------------------------------------------------
    # Empty values disable coloring while allowing the same printing functions
    # to work unchanged.
    # --------------------------------------------------------------------------
    readonly COLOR_RED=""
    readonly COLOR_GREEN=""
    readonly COLOR_YELLOW=""
    readonly COLOR_CYAN=""
    readonly COLOR_RESET=""
fi


# ==============================================================================
# Console Output Helpers
# ==============================================================================
#
# These functions provide consistent console output across Stoleus commands.
#
# Usage:
#
#     log_info "Installing Chrony..."
#     log_success "Chrony is running."
#     log_warning "Chrony is not synchronized yet."
#     log_error "Chrony installation failed."
#
# Informational, success, and warning messages are written to stdout.
#
# Error messages are written to stderr.
# ==============================================================================


# ==============================================================================
# log_info
# ==============================================================================
#
# Purpose:
#     Print an informational message.
#
# Usage:
#
#     log_info "Installing Chrony..."
#
# Information is displayed in cyan when terminal colors are available.
# ==============================================================================
log_info() {

    local message="${1:-}"

    printf '%sINFO:%s %s\n' \
        "$COLOR_CYAN" \
        "$COLOR_RESET" \
        "$message"
}


# ==============================================================================
# log_success
# ==============================================================================
#
# Purpose:
#     Print a successful-operation message.
#
# Usage:
#
#     log_success "Chrony is running."
#
# Success output is displayed in green when terminal colors are available.
# ==============================================================================
log_success() {

    local message="${1:-}"

    printf '%sSUCCESS:%s %s\n' \
        "$COLOR_GREEN" \
        "$COLOR_RESET" \
        "$message"
}


# ==============================================================================
# log_warning
# ==============================================================================
#
# Purpose:
#     Print a warning message.
#
# Usage:
#
#     log_warning "Chrony is running but not synchronized yet."
#
# Warning output is displayed in yellow when terminal colors are available.
# ==============================================================================
log_warning() {

    local message="${1:-}"

    printf '%sWARNING:%s %s\n' \
        "$COLOR_YELLOW" \
        "$COLOR_RESET" \
        "$message"
}


# ==============================================================================
# log_error
# ==============================================================================
#
# Purpose:
#     Print an error message to stderr.
#
# Usage:
#
#     log_error "Chrony installation failed."
#
# Error output is displayed in red when terminal colors are available.
#
# `>&2`
#     Redirects output from stdout to stderr.
# ==============================================================================
log_error() {

    local message="${1:-}"

    printf '%sERROR:%s %s\n' \
        "$COLOR_RED" \
        "$COLOR_RESET" \
        "$message" >&2
}


# ==============================================================================
# print_error
# ==============================================================================
#
# Purpose:
#     Maintain compatibility with existing Stoleus code that already calls:
#
#         print_error "message"
#
# New code should normally use:
#
#     log_error "message"
#
# "$*"
#     Combines all arguments passed to the function into one string.
# ==============================================================================
print_error() {

    log_error "$*"
}


# ==============================================================================
# print_step_success
# ==============================================================================
#
# Purpose:
#     Print the final successful status of a server-profile step.
#
# Usage:
#
#     print_step_success 1 3 "Chrony"
#
# Output:
#
#     [1/3] Chrony — OK
#
# The complete line is displayed in green when terminal colors are available.
#
# Arguments:
#
#     $1 = current step number
#     $2 = total number of steps
#     $3 = human-readable step name
# ==============================================================================
print_step_success() {

    local current_step="${1:-}"
    local total_steps="${2:-}"
    local step_name="${3:-}"


    # --------------------------------------------------------------------------
    # Validate required values before formatting the line.
    # --------------------------------------------------------------------------
    if [[ -z "$current_step" ]] ||
       [[ -z "$total_steps" ]] ||
       [[ -z "$step_name" ]]; then

        log_error "print_step_success received incomplete step information."

        return 1
    fi


    printf '%s[%s/%s] %s — OK%s\n' \
        "$COLOR_GREEN" \
        "$current_step" \
        "$total_steps" \
        "$step_name" \
        "$COLOR_RESET"
}


# ==============================================================================
# print_step_failure
# ==============================================================================
#
# Purpose:
#     Print the final failed status of a server-profile step.
#
# Usage:
#
#     print_step_failure 2 3 "Firewall"
#
# Output:
#
#     [2/3] Firewall — FAILED
#
# The complete line is displayed in red when terminal colors are available.
#
# Failed step lines are written to stderr.
#
# Arguments:
#
#     $1 = current step number
#     $2 = total number of steps
#     $3 = human-readable step name
# ==============================================================================
print_step_failure() {

    local current_step="${1:-}"
    local total_steps="${2:-}"
    local step_name="${3:-}"


    # --------------------------------------------------------------------------
    # Validate required values before formatting the line.
    # --------------------------------------------------------------------------
    if [[ -z "$current_step" ]] ||
       [[ -z "$total_steps" ]] ||
       [[ -z "$step_name" ]]; then

        log_error "print_step_failure received incomplete step information."

        return 1
    fi


    printf '%s[%s/%s] %s — FAILED%s\n' \
        "$COLOR_RED" \
        "$current_step" \
        "$total_steps" \
        "$step_name" \
        "$COLOR_RESET" >&2
}

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


# ==============================================================================
# create_directory
# ==============================================================================
#
# Purpose:
#     Create or configure a directory.
#
# Usage:
#
#     create_directory "/opt/application"
#
#     create_directory \
#         "/opt/application" \
#         "0755" \
#         "deployer" \
#         "deployer"
#
# Arguments:
#
#     $1 = directory path
#     $2 = permissions; optional, defaults to 0755
#     $3 = owner; optional
#     $4 = group; optional
#
# Owner and group must either both be provided or both omitted.
#
# Return codes:
#
#     0 = directory is ready
#     1 = directory creation or configuration failed
#     2 = invalid arguments
# ==============================================================================
create_directory() {

    local directory_path="${1:-}"
    local directory_mode="${2:-0755}"
    local owner_name="${3:-}"
    local group_name="${4:-}"

    local -a install_arguments=()


    log_info "Preparing directory creation."


    if [[ -z "$directory_path" ]]; then

        log_error "create_directory was called without a directory path."

        return 2
    fi


    if [[ ! "$directory_mode" =~ ^[0-7]{3,4}$ ]]; then

        log_error "Invalid directory permissions: $directory_mode"

        return 2
    fi


    if {
        [[ -n "$owner_name" ]] && [[ -z "$group_name" ]]
    } || {
        [[ -z "$owner_name" ]] && [[ -n "$group_name" ]]
    }; then

        log_error "Directory owner and group must be provided together."

        return 2
    fi


    require_command "install" || return 1


    install_arguments=(
        -d
        -m "$directory_mode"
    )


    if [[ -n "$owner_name" ]]; then

        if ! id -u "$owner_name" >/dev/null 2>&1; then

            log_error "Directory owner does not exist: $owner_name"

            return 1
        fi


        if ! getent group "$group_name" >/dev/null 2>&1; then

            log_error "Directory group does not exist: $group_name"

            return 1
        fi


        install_arguments+=(
            -o "$owner_name"
            -g "$group_name"
        )
    fi


    log_info "Creating or configuring directory: $directory_path"


    if ! install "${install_arguments[@]}" "$directory_path"; then

        log_error "Failed to create directory: $directory_path"

        return 1
    fi


    log_success "Directory is ready: $directory_path"

    return 0
}


# ==============================================================================
# remove_directory
# ==============================================================================
#
# Purpose:
#     Remove a directory and all content inside it.
#
# Usage:
#
#     remove_directory "/opt/runners/example"
#
# Safety:
#
#     - requires an absolute path;
#     - refuses to remove critical top-level Linux directories;
#     - treats a missing directory as already removed;
#     - does not follow a symbolic link as a directory tree.
#
# Return codes:
#
#     0 = directory removed or already absent
#     1 = removal failed
#     2 = unsafe or invalid argument
# ==============================================================================
remove_directory() {

    local directory_path="${1:-}"


    log_info "Preparing directory removal."


    if [[ -z "$directory_path" ]]; then

        log_error "remove_directory was called without a directory path."

        return 2
    fi


    if [[ "$directory_path" != /* ]]; then

        log_error "Directory removal requires an absolute path."

        return 2
    fi


    case "$directory_path" in

        /|\
        /bin|\
        /boot|\
        /dev|\
        /etc|\
        /home|\
        /lib|\
        /lib64|\
        /opt|\
        /proc|\
        /root|\
        /run|\
        /sbin|\
        /srv|\
        /sys|\
        /tmp|\
        /usr|\
        /var)

            log_error \
                "Refusing to remove protected system directory: $directory_path"

            return 2
            ;;
    esac


    require_command "rm" || return 1


    if [[ ! -e "$directory_path" ]] &&
       [[ ! -L "$directory_path" ]]; then

        log_info "Directory is already absent: $directory_path"

        return 0
    fi


    if [[ ! -d "$directory_path" ]] &&
       [[ ! -L "$directory_path" ]]; then

        log_error "Removal target is not a directory: $directory_path"

        return 1
    fi


    log_info "Removing directory: $directory_path"


    if ! rm -rf -- "$directory_path"; then

        log_error "Failed to remove directory: $directory_path"

        return 1
    fi


    if [[ -e "$directory_path" ]] ||
       [[ -L "$directory_path" ]]; then

        log_error "Directory still exists after removal: $directory_path"

        return 1
    fi


    log_success "Directory removed successfully: $directory_path"

    return 0
}


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


# ==============================================================================
# write_file
# ==============================================================================
#
# Purpose:
#     Replace the complete content of a text file safely.
#
# Usage:
#
#     write_file \
#         "/etc/application/config.conf" \
#         "$configuration_content"
#
# Arguments:
#
#     $1 = destination file
#     $2 = complete text content
#
# The file is written through a temporary file before replacing the destination.
# ==============================================================================
write_file() {

    local destination_path="${1:-}"
    local file_content="${2-}"

    local destination_directory
    local temporary_file


    log_info "Preparing file write."


    if [[ -z "$destination_path" ]]; then

        log_error "write_file was called without a destination path."

        return 2
    fi


    require_command "dirname" || return 1
    require_command "mktemp" || return 1
    require_command "mv" || return 1
    require_command "rm" || return 1


    destination_directory="$(dirname -- "$destination_path")"


    if [[ ! -d "$destination_directory" ]]; then

        log_error \
            "File destination directory does not exist: $destination_directory"

        return 1
    fi


    if ! temporary_file="$(
        mktemp "${destination_directory}/.stoleus-write.XXXXXX"
    )"; then

        log_error "Failed to create a temporary file."

        return 1
    fi


    if ! write_text "$file_content" "$ensure_newline" > "$temporary_file"; then

        rm -f -- "$temporary_file"

        log_error "Failed to write temporary file content."

        return 1
    fi


    if ! mv -f -- "$temporary_file" "$destination_path"; then

        rm -f -- "$temporary_file"

        log_error "Failed to replace file: $destination_path"

        return 1
    fi


    log_success "File written successfully: $destination_path"

    return 0
}


# ==============================================================================
# append_file
# ==============================================================================
#
# Purpose:
#     Append text to the end of a file.
#
# Usage:
#
#     append_file \
#         "/etc/application/config.conf" \
#         "$additional_content"
#
# The file is created when it does not already exist.
# ==============================================================================
append_file() {

    local destination_path="${1:-}"
    local file_content="${2-}"

    local destination_directory


    log_info "Preparing file append."


    if [[ -z "$destination_path" ]]; then

        log_error "append_file was called without a destination path."

        return 2
    fi


    require_command "dirname" || return 1


    destination_directory="$(dirname -- "$destination_path")"


    if [[ ! -d "$destination_directory" ]]; then

        log_error \
            "File destination directory does not exist: $destination_directory"

        return 1
    fi


    if ! write_text "$file_content" "$ensure_newline" >> "$destination_path"; then

        log_error "Failed to append content to: $destination_path"

        return 1
    fi


    log_success "Content appended successfully: $destination_path"

    return 0
}


# ==============================================================================
# replace_line
# ==============================================================================
#
# Purpose:
#     Replace every complete line matching an extended regular expression.
#
# Usage:
#
#     replace_line \
#         "/etc/application/config.conf" \
#         '^Port[[:space:]]*=' \
#         'Port=8080'
#
# Arguments:
#
#     $1 = file path
#     $2 = extended regular-expression pattern
#     $3 = complete replacement line
#
# Behavior:
#
#     - matching lines are replaced completely;
#     - non-matching lines remain unchanged;
#     - file ownership and permissions are preserved;
#     - the operation fails when no line matches.
#
# Return codes:
#
#     0 = one or more lines replaced
#     1 = replacement failed or no match was found
#     2 = invalid arguments
# ==============================================================================
replace_line() {

    local file_path="${1:-}"
    local search_pattern="${2:-}"
    local replacement_line="${3-}"

    local file_directory
    local temporary_file
    local awk_exit_code


    log_info "Preparing line replacement."


    if [[ -z "$file_path" ]]; then

        log_error "replace_line was called without a file path."

        return 2
    fi


    if [[ -z "$search_pattern" ]]; then

        log_error "replace_line was called without a search pattern."

        return 2
    fi


    require_command "awk" || return 1
    require_command "cat" || return 1
    require_command "dirname" || return 1
    require_command "mktemp" || return 1
    require_command "rm" || return 1


    if [[ ! -f "$file_path" ]]; then

        log_error "Line replacement target does not exist: $file_path"

        return 1
    fi


    file_directory="$(dirname -- "$file_path")"


    if ! temporary_file="$(
        mktemp "${file_directory}/.stoleus-replace.XXXXXX"
    )"; then

        log_error "Failed to create a temporary replacement file."

        return 1
    fi


    if awk \
        -v pattern="$search_pattern" \
        -v replacement="$replacement_line" '
            $0 ~ pattern {
                print replacement
                matched = 1
                next
            }

            {
                print
            }

            END {
                if (!matched) {
                    exit 3
                }
            }
        ' "$file_path" > "$temporary_file"; then

        awk_exit_code=0

    else

        awk_exit_code=$?
    fi


    if (( awk_exit_code == 3 )); then

        rm -f -- "$temporary_file"

        log_error "No line matched the requested pattern: $search_pattern"

        return 1
    fi


    if (( awk_exit_code != 0 )); then

        rm -f -- "$temporary_file"

        log_error "Failed to process file: $file_path"

        return 1
    fi


    # --------------------------------------------------------------------------
    # Writing through `cat` preserves the existing file inode, ownership, and
    # permissions.
    # --------------------------------------------------------------------------
    if ! cat "$temporary_file" > "$file_path"; then

        rm -f -- "$temporary_file"

        log_error "Failed to update file: $file_path"

        return 1
    fi


    rm -f -- "$temporary_file"

    log_success "Matching line replaced successfully: $file_path"

    return 0
}


# ==============================================================================
# run_command
# ==============================================================================
#
# Purpose:
#     Load and execute one Stoleus command implementation.
#
# Example:
#
#     run_command "help"
#
# loads:
#
#     commands/help.sh
#
# Example:
#
#     run_command "version"
#
# loads:
#
#     commands/version.sh
#
# Each command file must expose:
#
#     command_main()
#
# ==============================================================================
run_command() {

    # --------------------------------------------------------------------------
    # Store the first argument passed to this function.
    #
    # Example:
#
#     run_command "help"
#
# means:
#
#     $1 = help
#
# `local`
#     Restricts the variable to this function.
# --------------------------------------------------------------------------
    local command_name="${1:-}"


    # --------------------------------------------------------------------------
    # Validate the command name before continuing.
    # --------------------------------------------------------------------------
    if [[ -z "$command_name" ]]; then

        log_error "run_command was called without a command name."

        return 1
    fi


    # --------------------------------------------------------------------------
    # Remove the first positional argument.
    #
    # We have already saved it in:
#
#     command_name
#
# Any remaining arguments will later be forwarded to command_main().
#
# Example:
#
#     run_command "health" "--verbose"
#
# Before shift:
#
#     $1 = health
#     $2 = --verbose
#
# After shift:
#
#     $1 = --verbose
# --------------------------------------------------------------------------
    shift


    # --------------------------------------------------------------------------
    # Build the full file path for the command implementation.
    #
    # Example:
#
#     STOLEUS_COMMANDS_DIR=/home/deployer/tools/commands
#     command_name=help
#
# becomes:
#
#     /home/deployer/tools/commands/help.sh
# --------------------------------------------------------------------------
    local command_file="${STOLEUS_COMMANDS_DIR}/${command_name}.sh"


    # --------------------------------------------------------------------------
    # Verify that the command implementation exists.
    #
    # -f
#     Tests whether the path exists and is a normal file.
#
# !
#     Means logical NOT.
# --------------------------------------------------------------------------
    if [[ ! -f "$command_file" ]]; then

        log_error "Command implementation not found: $command_name"

        return 1
    fi


    # --------------------------------------------------------------------------
    # Remove an existing command_main function before loading another command.
    #
    # Because command files are sourced into the current shell, a previous
    # command_main definition could otherwise remain available.
    #
    # `unset -f`
    #     Removes a Bash function.
    #
    # `2>/dev/null || true`
    #     Suppresses the error if the function does not currently exist.
    # --------------------------------------------------------------------------
    unset -f command_main 2>/dev/null || true


    # --------------------------------------------------------------------------
    # Load the command implementation into the current Bash process.
    #
    # `source`
    #     Reads another Bash file and executes it in the current shell.
    # --------------------------------------------------------------------------
    source "$command_file"


    # --------------------------------------------------------------------------
    # Verify that the command file exposed command_main().
    #
    # `declare -F`
    #     Checks whether a function with the specified name exists.
    #
    # This gives us a clear error instead of:
#
#     command_main: command not found
# --------------------------------------------------------------------------
    if ! declare -F command_main >/dev/null 2>&1; then

        log_error "Command does not define command_main(): $command_name"

        return 1
    fi


    # --------------------------------------------------------------------------
    # Execute the command.
    #
    # "$@"
    #     Passes all remaining arguments to command_main().
    #
    # Example:
#
#     stoleus health --verbose
#
# eventually becomes:
#
#     command_main "--verbose"
# --------------------------------------------------------------------------
    command_main "$@"
}


# ==============================================================================
# read_version
# ==============================================================================
#
# Purpose:
#     Read the current version from the VERSION file.
#
# The repository contains:
#
#     VERSION
#
# with content such as:
#
#     0.1.0
#
# We keep the version in one file so it becomes the single source of truth.
# ==============================================================================
read_version() {

    # --------------------------------------------------------------------------
    # Verify that VERSION exists and can be read.
    #
    # -r
    #     Checks whether the file is readable.
    # --------------------------------------------------------------------------
    if [[ ! -r "$STOLEUS_VERSION_FILE" ]]; then

        log_error "Version file is missing or unreadable: $STOLEUS_VERSION_FILE"

        return 1
    fi


    # --------------------------------------------------------------------------
    # Read the VERSION file.
    #
    # <
    #     Redirects the file into the standard input of tr.
    #
    # tr -d '[:space:]'
    #     Removes whitespace characters such as spaces, tabs, and newlines.
    #
    # Example:
#
# VERSION contains:
#
#     0.1.0
#
# followed by a newline.
#
# This command outputs:
#
#     0.1.0
# --------------------------------------------------------------------------
    tr -d '[:space:]' < "$STOLEUS_VERSION_FILE"
}
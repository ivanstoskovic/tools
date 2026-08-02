#!/usr/bin/env bash

set -Eeuo pipefail


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

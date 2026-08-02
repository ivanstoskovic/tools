#!/usr/bin/env bash

set -Eeuo pipefail

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
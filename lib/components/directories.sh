#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# ensure_directory
# ==============================================================================
#
# Purpose:
#     Ensure that a directory exists with the required owner, group, and
#     permissions.
#
# Usage:
#
#     ensure_directory \
#         "/opt/apps" \
#         "deployer" \
#         "deployer" \
#         "0755"
#
# Arguments:
#
#     $1 = directory path
#     $2 = owner
#     $3 = group
#     $4 = permissions
#
# Idempotency:
#
#     - an existing directory is reused
#     - ownership is corrected when necessary
#     - permissions are corrected when necessary
# ==============================================================================
ensure_directory() {

    local directory_path="${1:-}"
    local owner_name="${2:-}"
    local group_name="${3:-}"
    local directory_mode="${4:-}"


    require_root || return 1
    require_command "install" || return 1
    require_command "chown" || return 1
    require_command "chmod" || return 1


    if [[ -z "$directory_path" ]]; then

        log_error "ensure_directory was called without a directory path."

        return 2
    fi


    if [[ -z "$owner_name" ]]; then

        log_error "No owner was specified for directory: $directory_path"

        return 2
    fi


    if [[ -z "$group_name" ]]; then

        log_error "No group was specified for directory: $directory_path"

        return 2
    fi


    if [[ ! "$directory_mode" =~ ^[0-7]{4}$ ]]; then

        log_error \
            "Invalid directory mode for ${directory_path}: ${directory_mode}"

        return 2
    fi


    # --------------------------------------------------------------------------
    # Verify that the requested user exists.
    #
    # `id -u`
    #     Returns the numeric user ID when the user exists.
    # --------------------------------------------------------------------------
    if ! id -u "$owner_name" >/dev/null 2>&1; then

        log_error "Directory owner does not exist: $owner_name"

        return 1
    fi


    # --------------------------------------------------------------------------
    # Verify that the requested group exists.
    #
    # `getent group`
    #     Queries the operating system's group database.
    # --------------------------------------------------------------------------
    if ! getent group "$group_name" >/dev/null 2>&1; then

        log_error "Directory group does not exist: $group_name"

        return 1
    fi


    # --------------------------------------------------------------------------
    # `install -d`
    #     Creates the directory and any missing parent directories.
    #
    # `-m`
    #     Applies the requested permissions.
    #
    # `-o`
    #     Sets the owner.
    #
    # `-g`
    #     Sets the group.
    #
    # Running this against an existing directory is safe.
    # --------------------------------------------------------------------------
    log_info "Ensuring directory: $directory_path"


    if ! install \
        -d \
        -m "$directory_mode" \
        -o "$owner_name" \
        -g "$group_name" \
        "$directory_path"; then

        log_error "Failed to create or configure directory: $directory_path"

        return 1
    fi


    log_success "Directory is ready: $directory_path"
}


# ==============================================================================
# verify_directory
# ==============================================================================
#
# Purpose:
#     Verify that a directory exists and has the expected owner, group, and
#     permissions.
# ==============================================================================
verify_directory() {

    local directory_path="${1:-}"
    local expected_owner="${2:-}"
    local expected_group="${3:-}"
    local expected_mode="${4:-}"

    local actual_owner
    local actual_group
    local actual_mode


    require_command "stat" || return 1


    if [[ ! -d "$directory_path" ]]; then

        log_error "Directory does not exist: $directory_path"

        return 1
    fi


    # --------------------------------------------------------------------------
    # GNU stat format fields:
    #
    #     %U = owner name
    #     %G = group name
    #     %a = permissions in octal form, without a leading zero
    # --------------------------------------------------------------------------
    actual_owner="$(stat -c '%U' "$directory_path")"
    actual_group="$(stat -c '%G' "$directory_path")"
    actual_mode="$(stat -c '%a' "$directory_path")"


    if [[ "$actual_owner" != "$expected_owner" ]]; then

        log_error \
            "Unexpected owner for ${directory_path}: ${actual_owner}"

        return 1
    fi


    if [[ "$actual_group" != "$expected_group" ]]; then

        log_error \
            "Unexpected group for ${directory_path}: ${actual_group}"

        return 1
    fi


    # --------------------------------------------------------------------------
    # stat returns:
    #
    #     755
    #
    # while our desired configuration is written as:
    #
    #     0755
    #
    # Remove one leading zero before comparing.
    # --------------------------------------------------------------------------
    expected_mode="${expected_mode#0}"


    if [[ "$actual_mode" != "$expected_mode" ]]; then

        log_error \
            "Unexpected permissions for ${directory_path}: ${actual_mode}"

        return 1
    fi


    return 0
}


# ==============================================================================
# setup_application_directories
# ==============================================================================
#
# Purpose:
#     Create the standard filesystem layout used by Stoleus application and
#     staging servers.
#
# Directories:
#
#     /opt/apps
#         Deployed application files and Compose projects.
#
#     /opt/backups
#         Local temporary backup storage.
#
#     /opt/runners
#         GitHub Actions self-hosted runner installations.
#
#     /opt/scripts
#         Administrative and deployment scripts.
#
#     /var/log/stoleus
#         Logs generated by Stoleus-managed workflows.
#
# Ownership:
#
#     deployer:deployer
#
# Permissions:
#
#     0755
# ==============================================================================
setup_application_directories() {

    local owner_name="deployer"
    local group_name="deployer"
    local directory_mode="0755"

    local -a directories=(
        "/opt/apps"
        "/opt/backups"
        "/opt/runners"
        "/opt/scripts"
        "/var/log/stoleus"
    )

    local directory_path


    require_root || return 1

    log_info "Starting application-directory setup."


    for directory_path in "${directories[@]}"; do

        ensure_directory \
            "$directory_path" \
            "$owner_name" \
            "$group_name" \
            "$directory_mode" || return 1
    done


    for directory_path in "${directories[@]}"; do

        verify_directory \
            "$directory_path" \
            "$owner_name" \
            "$group_name" \
            "$directory_mode" || return 1
    done


    log_success "Application directories configured successfully."
}

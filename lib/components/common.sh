#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# Internal setup state
# ==============================================================================
#
# This variable prevents `apt-get update` from running repeatedly during one
# Stoleus execution.
#
# Example:
#
#     ensure_package_installed "ufw"
#     ensure_package_installed "curl"
#
# Package metadata is updated only once, even if multiple packages are installed.
# ==============================================================================
APT_METADATA_UPDATED=0


# ==============================================================================
# require_root
# ==============================================================================
#
# Purpose:
#     Verify that the current process is running as root.
#
# `$EUID`
#     Effective user ID of the current process.
#
# Root always has:
#
#     EUID = 0
#
# This function is kept under the name `require_root` because it already exists
# in the current Stoleus implementation.
# ==============================================================================
require_root() {

    if [[ "$EUID" -ne 0 ]]; then

        log_error "This command requires root privileges."
        log_error "Run it with sudo."

        return 1
    fi
}

# ==============================================================================
# require_command
# ==============================================================================
#
# Purpose:
#     Verify that a required executable exists.
#
# Usage:
#
#     require_command "systemctl"
#     require_command "apt-get"
#
# `command -v`
#     Searches for a command in the current PATH.
#
# Output is redirected because we only need the exit code.
# ==============================================================================
require_command() {

    local command_name="${1:-}"


    if [[ -z "$command_name" ]]; then

        log_error "require_command was called without a command name."

        return 1
    fi


    if command -v "$command_name" >/dev/null 2>&1; then

        return 0
    fi


    log_error "Required command is not available: $command_name"

    return 1
}


# ==============================================================================
# is_package_installed
# ==============================================================================
#
# Purpose:
#     Determine whether a Debian package is already installed.
#
# Usage:
#
#     if is_package_installed "chrony"; then
#         ...
#     fi
#
# `dpkg-query`
#     Reads the local Debian package database.
#
# Expected installed status:
#
#     install ok installed
# ==============================================================================
is_package_installed() {

    local package_name="${1:-}"


    if [[ -z "$package_name" ]]; then

        return 1
    fi


    dpkg-query \
        --show \
        --showformat='${Status}' \
        "$package_name" 2>/dev/null |
        grep -q '^install ok installed$'
}


# ==============================================================================
# update_apt_metadata
# ==============================================================================
#
# Purpose:
#     Update APT package metadata once per Stoleus execution.
#
# `apt-get update`
#     Downloads the latest package indexes.
#
# It does not upgrade installed software.
# ==============================================================================
update_apt_metadata() {

    require_command "apt-get"


    if [[ "$APT_METADATA_UPDATED" -eq 1 ]]; then

        log_info "APT package metadata was already updated during this run."

        return 0
    fi


    log_info "Updating APT package metadata..."


    if ! apt-get update; then

        log_error "Failed to update APT package metadata."

        return 1
    fi


    APT_METADATA_UPDATED=1

    log_success "APT package metadata updated."
}


# ==============================================================================
# ensure_package_installed
# ==============================================================================
#
# Purpose:
#     Ensure that a Debian package is installed.
#
# Usage:
#
#     ensure_package_installed "chrony"
#     ensure_package_installed "ufw"
#
# Idempotency:
#     If the package is already installed, nothing is changed.
# ==============================================================================
ensure_package_installed() {

    local package_name="${1:-}"


    if [[ -z "$package_name" ]]; then

        log_error "ensure_package_installed was called without a package name."

        return 1
    fi


    require_root
    require_command "dpkg-query"
    require_command "apt-get"


    if is_package_installed "$package_name"; then

        log_info "Package is already installed: $package_name"

        return 0
    fi


    log_info "Package is not installed: $package_name"

    update_apt_metadata

    log_info "Installing package: $package_name"


    if ! apt-get install -y "$package_name"; then

        log_error "Failed to install package: $package_name"

        return 1
    fi


    if ! is_package_installed "$package_name"; then

        log_error "Package installation could not be verified: $package_name"

        return 1
    fi


    log_success "Package installed: $package_name"
}


# ==============================================================================
# ensure_service_enabled
# ==============================================================================
#
# Purpose:
#     Ensure that a systemd service starts automatically after boot.
#
# Usage:
#
#     ensure_service_enabled "chrony.service"
#
# Idempotency:
#     An already-enabled service is not enabled again.
# ==============================================================================
ensure_service_enabled() {

    local service_name="${1:-}"


    if [[ -z "$service_name" ]]; then

        log_error "ensure_service_enabled was called without a service name."

        return 1
    fi


    require_root
    require_command "systemctl"


    if systemctl is-enabled --quiet "$service_name"; then

        log_info "Service is already enabled: $service_name"

        return 0
    fi


    log_info "Enabling service: $service_name"


    if ! systemctl enable "$service_name"; then

        log_error "Failed to enable service: $service_name"

        return 1
    fi


    if ! systemctl is-enabled --quiet "$service_name"; then

        log_error "Service enablement could not be verified: $service_name"

        return 1
    fi


    log_success "Service enabled: $service_name"
}


# ==============================================================================
# ensure_service_running
# ==============================================================================
#
# Purpose:
#     Ensure that a systemd service is currently running.
#
# Usage:
#
#     ensure_service_running "chrony.service"
#
# Idempotency:
#     An already-running service is not started again.
# ==============================================================================
ensure_service_running() {

    local service_name="${1:-}"


    if [[ -z "$service_name" ]]; then

        log_error "ensure_service_running was called without a service name."

        return 1
    fi


    require_root
    require_command "systemctl"


    if systemctl is-active --quiet "$service_name"; then

        log_info "Service is already running: $service_name"

        return 0
    fi


    log_info "Starting service: $service_name"


    if ! systemctl start "$service_name"; then

        log_error "Failed to start service: $service_name"

        return 1
    fi


    if ! systemctl is-active --quiet "$service_name"; then

        log_error "Service startup could not be verified: $service_name"

        return 1
    fi


    log_success "Service started: $service_name"
}


# ==============================================================================
# ensure_service_enabled_and_running
# ==============================================================================
#
# Purpose:
#     Ensure that a systemd service:
#
#         1. Starts automatically after boot.
#         2. Is currently running.
#
# Usage:
#
#     ensure_service_enabled_and_running "chrony.service"
# ==============================================================================
ensure_service_enabled_and_running() {

    local service_name="${1:-}"


    if [[ -z "$service_name" ]]; then

        log_error \
            "ensure_service_enabled_and_running was called without a service name."

        return 1
    fi


    ensure_service_enabled "$service_name"
    ensure_service_running "$service_name"

    log_success "Service is enabled and running: $service_name"
}
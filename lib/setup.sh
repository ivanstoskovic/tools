#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Setup Library
# ==============================================================================
#
# Purpose:
#     Contains reusable installation and configuration functions used by:
#
#         stoleus setup ...
#
# This file is responsible for making system changes.
#
# Unlike `stoleus health`, setup commands ARE allowed to:
#
#     - install packages
#     - enable services
#     - start services
#     - change configuration
#
# Because these are privileged operations, setup commands are expected to run
# as root.
#
# The first component we implement is Chrony.
# ==============================================================================


# ------------------------------------------------------------------------------
# Enable strict Bash behavior.
# ------------------------------------------------------------------------------
set -Eeuo pipefail


# ==============================================================================
# require_root
# ==============================================================================
#
# Purpose:
#     Stop execution if the current user is not root.
#
# `$EUID`
#     Effective user ID of the current process.
#
# Root always has:
#
#     EUID = 0
#
# Example:
#
#     sudo stoleus setup chrony
#
# runs the command as root.
# ==============================================================================
require_root() {

    if [[ "$EUID" -ne 0 ]]; then

        log_error "This command requires root privileges."
        log_error "Run it with sudo."

        return 1
    fi
}


# ==============================================================================
# setup_chrony
# ==============================================================================
#
# Purpose:
#     Ensure Chrony is installed, enabled, running, and synchronized.
#
# This function is designed to be IDEMPOTENT.
#
# That means running:
#
#     sudo stoleus setup chrony
#
# repeatedly should be safe.
#
# Desired state:
#
#     1. Chrony is installed.
#     2. chrony.service is enabled at boot.
#     3. chrony.service is running.
#     4. Chrony reports normal synchronization.
#
# ==============================================================================
setup_chrony() {

    # --------------------------------------------------------------------------
    # This function changes the operating system, so root is mandatory.
    # --------------------------------------------------------------------------
    require_root


    # --------------------------------------------------------------------------
    # Verify that APT exists.
    #
    # Stoleus currently targets Ubuntu/Debian systems.
    #
    # apt-get is preferred over apt in scripts because its command-line
    # interface is intended to be stable for automation.
    # --------------------------------------------------------------------------
    if ! command -v apt-get >/dev/null 2>&1; then

        log_error "apt-get is not available."
        log_error "Chrony setup currently supports Ubuntu/Debian systems."

        return 1
    fi


    # --------------------------------------------------------------------------
    # Check whether Chrony is already installed.
    #
    # chronyc is installed as part of the chrony package.
    # --------------------------------------------------------------------------
    if command -v chronyc >/dev/null 2>&1; then

        log_info "Chrony is already installed."

    else

        log_info "Chrony is not installed."
        log_info "Updating package metadata..."

        apt-get update

        log_info "Installing Chrony..."

        apt-get install -y chrony

        log_success "Chrony package installed."
    fi


    # --------------------------------------------------------------------------
    # Verify that systemd tooling is available.
    # --------------------------------------------------------------------------
    if ! command -v systemctl >/dev/null 2>&1; then

        log_error "systemctl is not available."

        return 1
    fi


    # --------------------------------------------------------------------------
    # Enable Chrony at boot and start it immediately.
    #
    # --now means:
    #
    #     enable at boot
    #     AND
    #     start immediately
    #
    # Running this repeatedly is safe.
    # --------------------------------------------------------------------------
    log_info "Enabling and starting Chrony..."

    systemctl enable --now chrony.service


    # --------------------------------------------------------------------------
    # Verify that the service is currently active.
    # --------------------------------------------------------------------------
    if ! systemctl is-active --quiet chrony.service; then

        log_error "Chrony service is not running."

        return 1
    fi

    log_success "Chrony service is running."


    # --------------------------------------------------------------------------
    # Give Chrony a few seconds after service startup before checking its
    # synchronization state.
    # --------------------------------------------------------------------------
    log_info "Waiting for Chrony synchronization..."

    sleep 3


    # --------------------------------------------------------------------------
    # Verify synchronization.
    #
    # chronyc tracking
    #
    # normally contains:
    #
    #     Leap status : Normal
    #
    # when synchronization is healthy.
    # --------------------------------------------------------------------------
    if chronyc tracking 2>/dev/null |
        grep -qE 'Leap status[[:space:]]*:[[:space:]]*Normal'; then

        log_success "Chrony is installed, running, and synchronized."

        return 0
    fi


    # --------------------------------------------------------------------------
    # Chrony can be healthy and running while still waiting for the first valid
    # synchronization sample, especially immediately after installation.
    # --------------------------------------------------------------------------
    log_warning "Chrony is running but is not synchronized yet."

    return 1
}
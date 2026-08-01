#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# ensure_ufw_rule
# ==============================================================================
#
# Purpose:
#     Ensure that a UFW allow rule exists.
#
# Usage:
#
#     ensure_ufw_rule "OpenSSH"
#     ensure_ufw_rule "80/tcp"
#     ensure_ufw_rule "443/tcp"
#
# UFW commands are idempotent. Adding an existing rule does not create a
# harmful duplicate, but we still check first so the output remains clean.
# ==============================================================================
ensure_ufw_rule() {

    local rule="${1:-}"


    if [[ -z "$rule" ]]; then

        log_error "ensure_ufw_rule was called without a rule."

        return 1
    fi


    require_root
    require_command "ufw"


    if ufw status |
        grep -Fq "$rule"; then

        log_info "Firewall rule already exists: $rule"

        return 0
    fi


    log_info "Adding firewall rule: $rule"


    if ! ufw allow "$rule"; then

        log_error "Failed to add firewall rule: $rule"

        return 1
    fi


    log_success "Firewall rule added: $rule"
}


# ==============================================================================
# ensure_ufw_defaults
# ==============================================================================
#
# Purpose:
#     Configure the baseline firewall policy:
#
#         incoming traffic -> deny
#         outgoing traffic -> allow
#
# These commands are safe to run repeatedly.
# ==============================================================================
ensure_ufw_defaults() {

    require_root
    require_command "ufw"


    log_info "Setting default incoming policy to deny."

    if ! ufw default deny incoming; then

        log_error "Failed to configure the default incoming policy."

        return 1
    fi


    log_info "Setting default outgoing policy to allow."

    if ! ufw default allow outgoing; then

        log_error "Failed to configure the default outgoing policy."

        return 1
    fi


    log_success "Firewall default policies configured."
}


# ==============================================================================
# ensure_ufw_enabled
# ==============================================================================
#
# Purpose:
#     Ensure that UFW is enabled.
#
# Important:
#     The SSH rule must be created before calling this function. Otherwise,
#     enabling the firewall could block the active SSH connection.
# ==============================================================================
ensure_ufw_enabled() {

    require_root
    require_command "ufw"


    if ufw status |
        grep -q '^Status: active$'; then

        log_info "UFW is already active."

        return 0
    fi


    log_info "Enabling UFW."


    # --------------------------------------------------------------------------
    # --force
    #
    # Suppresses UFW's interactive confirmation prompt.
    #
    # This is safe here because setup_firewall() adds the SSH rule before
    # calling this function.
    # --------------------------------------------------------------------------
    if ! ufw --force enable; then

        log_error "Failed to enable UFW."

        return 1
    fi


    if ! ufw status |
        grep -q '^Status: active$'; then

        log_error "UFW activation could not be verified."

        return 1
    fi


    log_success "UFW is active."
}


# ==============================================================================
# verify_firewall_configuration
# ==============================================================================
#
# Purpose:
#     Verify that:
#
#         - UFW is active
#         - an SSH allow rule exists
#
# HTTP and HTTPS are part of the current baseline and are also verified.
# ==============================================================================
verify_firewall_configuration() {

    local ufw_status


    require_command "ufw"


    ufw_status="$(ufw status)"


    if ! grep -q '^Status: active$' <<< "$ufw_status"; then

        log_error "Firewall verification failed: UFW is not active."

        return 1
    fi


    if ! grep -Eq \
        'OpenSSH|22/tcp' <<< "$ufw_status"; then

        log_error "Firewall verification failed: SSH is not allowed."

        return 1
    fi


    if ! grep -Fq '80/tcp' <<< "$ufw_status"; then

        log_error "Firewall verification failed: HTTP is not allowed."

        return 1
    fi


    if ! grep -Fq '443/tcp' <<< "$ufw_status"; then

        log_error "Firewall verification failed: HTTPS is not allowed."

        return 1
    fi


    log_success "Firewall configuration verified."
}


# ==============================================================================
# setup_firewall
# ==============================================================================
#
# Purpose:
#     Install and configure the baseline UFW firewall.
#
# Order matters:
#
#     1. Install UFW.
#     2. Set default policies.
#     3. Allow SSH.
#     4. Allow HTTP.
#     5. Allow HTTPS.
#     6. Enable UFW.
#     7. Verify the configuration.
# ==============================================================================
setup_firewall() {

    require_root || return 1

    log_info "Starting firewall setup."

    ensure_package_installed "ufw" || return 1

    ensure_ufw_defaults || return 1

    # --------------------------------------------------------------------------
    # SSH must be allowed before UFW is enabled.
    # --------------------------------------------------------------------------
    ensure_ufw_rule "OpenSSH" || return 1

    ensure_ufw_rule "80/tcp" || return 1
    ensure_ufw_rule "443/tcp" || return 1

    ensure_ufw_enabled || return 1

    verify_firewall_configuration || return 1

    log_success "Firewall setup completed successfully."
}

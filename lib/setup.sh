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
# Setup functions are allowed to modify the operating system by:
#
#     - installing packages
#     - enabling services
#     - starting services
#     - changing configuration
#
# Setup commands must therefore be executed as root.
#
# Example:
#
#     sudo stoleus setup chrony
#
# ==============================================================================


# ------------------------------------------------------------------------------
# Enable strict Bash behavior.
# ------------------------------------------------------------------------------
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


# ==============================================================================
# verify_chrony_synchronization
# ==============================================================================
#
# Purpose:
#     Wait for Chrony to report normal synchronization.
#
# Chrony can require several seconds after installation or startup before it
# obtains a valid time sample.
#
# The function performs:
#
#     10 attempts
#     3 seconds between attempts
#
# Maximum wait:
#
#     approximately 30 seconds
# ==============================================================================
verify_chrony_synchronization() {

    local maximum_attempts=10
    local current_attempt=1


    require_command "chronyc"
    require_command "grep"


    log_info "Waiting for Chrony synchronization..."


    while [[ "$current_attempt" -le "$maximum_attempts" ]]; do

        if chronyc tracking 2>/dev/null |
            grep -qE 'Leap status[[:space:]]*:[[:space:]]*Normal'; then

            log_success "Chrony is synchronized."

            return 0
        fi


        if [[ "$current_attempt" -lt "$maximum_attempts" ]]; then

            log_info \
                "Chrony synchronization attempt ${current_attempt}/${maximum_attempts}."

            sleep 3
        fi


        ((current_attempt += 1))
    done


    log_error "Chrony is running but synchronization was not confirmed."

    return 1
}

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

# ==============================================================================
# setup_chrony
# ==============================================================================
#
# Purpose:
#     Ensure that Chrony is:
#
#         - installed
#         - enabled at boot
#         - currently running
#         - synchronized
# ==============================================================================
setup_chrony() {

    require_root || return 1

    log_info "Starting Chrony setup."

    ensure_package_installed "chrony" || return 1

    ensure_service_enabled_and_running "chrony.service" || return 1

    verify_chrony_synchronization || return 1

    log_success "Chrony setup completed successfully."
}

# ==============================================================================
# Server profile execution state
# ==============================================================================
#
# These variables track the execution of the currently running server profile.
#
# They are reset by:
#
#     begin_server_profile
#
# before each profile starts.
# ==============================================================================
PROFILE_NAME=""
PROFILE_TOTAL_STEPS=0
PROFILE_CURRENT_STEP=0
PROFILE_COMPLETED_STEPS=0
PROFILE_FAILED_STEP=""


# ==============================================================================
# begin_server_profile
# ==============================================================================
#
# Purpose:
#     Initialize execution state for a server profile.
#
# Usage:
#
#     begin_server_profile "Application server" 2
#
# Arguments:
#
#     $1 - Human-readable profile name
#     $2 - Total number of steps in the profile
# ==============================================================================
begin_server_profile() {

    local profile_name="${1:-}"
    local total_steps="${2:-0}"


    if [[ -z "$profile_name" ]]; then

        log_error "begin_server_profile was called without a profile name."

        return 1
    fi


    if [[ ! "$total_steps" =~ ^[1-9][0-9]*$ ]]; then

        log_error "The profile step count must be a positive integer."

        return 1
    fi


    PROFILE_NAME="$profile_name"
    PROFILE_TOTAL_STEPS="$total_steps"
    PROFILE_CURRENT_STEP=0
    PROFILE_COMPLETED_STEPS=0
    PROFILE_FAILED_STEP=""

    echo
    log_info "Starting profile: $PROFILE_NAME"
    log_info "Total steps: $PROFILE_TOTAL_STEPS"
}


# ==============================================================================
# run_profile_step
# ==============================================================================
#
# Purpose:
#     Execute one function as a profile step.
#
# Usage:
#
#     run_profile_step "Chrony" setup_chrony
#     run_profile_step "Firewall" setup_firewall
#
# Arguments:
#
#     $1 - Human-readable step name
#     $2 - Function to execute
#     $3... - Optional arguments passed to the function
#
# Return codes:
#
#     0 - Step completed successfully
#     1 - Step failed
#     2 - Invalid arguments
# ==============================================================================
run_profile_step() {

    local step_name="${1:-}"
    local step_function="${2:-}"


    if [[ -z "$step_name" ]]; then

        log_error "run_profile_step was called without a step name."

        return 2
    fi


    if [[ -z "$step_function" ]]; then

        log_error "No function was provided for profile step: $step_name"

        return 2
    fi


    if ! declare -F "$step_function" >/dev/null 2>&1; then

        log_error "Profile step function does not exist: $step_function"

        return 2
    fi


    # --------------------------------------------------------------------------
    # Remove the step name and function name from the argument list.
    #
    # Any remaining arguments are passed to the step function.
    # --------------------------------------------------------------------------
    shift 2


    PROFILE_CURRENT_STEP=$((PROFILE_CURRENT_STEP + 1))

    echo
    printf '[%d/%d] %s\n' \
        "$PROFILE_CURRENT_STEP" \
        "$PROFILE_TOTAL_STEPS" \
        "$step_name"


    if "$step_function" "$@"; then

        PROFILE_COMPLETED_STEPS=$((PROFILE_COMPLETED_STEPS + 1))

        log_success "Profile step completed: $step_name"

        return 0
    fi


    PROFILE_FAILED_STEP="$step_name"

    log_error "Profile step failed: $step_name"

    return 1
}


# ==============================================================================
# complete_server_profile
# ==============================================================================
#
# Purpose:
#     Verify and report successful profile completion.
# ==============================================================================
complete_server_profile() {

    echo


    if [[ "$PROFILE_COMPLETED_STEPS" -ne "$PROFILE_TOTAL_STEPS" ]]; then

        log_error "Profile did not complete all expected steps."
        log_error \
            "Completed ${PROFILE_COMPLETED_STEPS}/${PROFILE_TOTAL_STEPS} steps."

        return 1
    fi


    log_success \
    "${PROFILE_NAME} profile completed successfully: ${PROFILE_COMPLETED_STEPS}/${PROFILE_TOTAL_STEPS} steps."
}


# ==============================================================================
# fail_server_profile
# ==============================================================================
#
# Purpose:
#     Print a consistent failure summary for the current profile.
# ==============================================================================
fail_server_profile() {

    echo

    log_error "$PROFILE_NAME profile failed."
    log_error \
        "Completed ${PROFILE_COMPLETED_STEPS}/${PROFILE_TOTAL_STEPS} steps."


    if [[ -n "$PROFILE_FAILED_STEP" ]]; then

        log_error "Failed step: $PROFILE_FAILED_STEP"
    fi


    return 1
}

# ==============================================================================
# setup_app_server
# ==============================================================================
#
# Purpose:
#     Configure the common baseline for an application server.
#
# Current steps:
#
#     1. Chrony
#     2. Firewall
# ==============================================================================
setup_app_server() {

    require_root || return 1

    begin_server_profile "Application server" 2 || return 1


    if ! run_profile_step "Chrony" setup_chrony; then

        fail_server_profile

        return 1
    fi


    if ! run_profile_step "Firewall" setup_firewall; then

        fail_server_profile

        return 1
    fi


    complete_server_profile
}


# ==============================================================================
# setup_stage_server
# ==============================================================================
#
# Purpose:
#     Configure the staging-server baseline.
#
# The staging server currently uses the same components as the application
# server, but remains a separate profile for future staging-specific settings.
# ==============================================================================
setup_stage_server() {

    require_root || return 1

    begin_server_profile "Staging server" 2 || return 1


    if ! run_profile_step "Chrony" setup_chrony; then

        fail_server_profile

        return 1
    fi


    if ! run_profile_step "Firewall" setup_firewall; then

        fail_server_profile

        return 1
    fi


    complete_server_profile
}


# ==============================================================================
# setup_server_profile
# ==============================================================================
#
# Purpose:
#     Route a server profile name to its setup implementation.
#
# Usage:
#
#     setup_server_profile "app"
#     setup_server_profile "stage"
#
# This is similar to a C# switch statement.
# ==============================================================================
setup_server_profile() {

    local profile="${1:-}"


    if [[ -z "$profile" ]]; then

        log_error "A server profile must be specified."

        return 2
    fi


    case "$profile" in

        app)

            setup_app_server

            ;;


        stage)

            setup_stage_server

            ;;


        storage)

            log_error "The storage profile is not implemented yet."
            log_error "Its database ports must be restricted to the LAN."

            return 2

            ;;


        *)

            log_error "Unknown server profile: $profile"

            return 2

            ;;
    esac
}
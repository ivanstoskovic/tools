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
#     Verify that Chrony has a valid synchronization source and that the local
#     system clock is actually close to synchronized time.
#
# Why checking only "Leap status: Normal" is insufficient:
#
#     Chrony can report:
#
#         Leap status : Normal
#
#     while still gradually correcting a very large clock difference.
#
# We therefore verify both:
#
#     1. Leap status is Normal.
#     2. System time offset is no greater than one second.
#
# If the remaining offset is larger than one second, we run:
#
#     chronyc makestep
#
# This immediately applies the outstanding clock correction rather than waiting
# for Chrony to adjust it gradually.
# ==============================================================================
verify_chrony_synchronization() {

    local maximum_attempts=10
    local current_attempt=1
    local maximum_offset_seconds="1.0"

    local tracking_output
    local leap_status
    local system_time_offset
    local absolute_offset


    require_root || return 1
    require_command "chronyc" || return 1
    require_command "awk" || return 1


    log_info "Waiting for Chrony synchronization..."


    while (( current_attempt <= maximum_attempts )); do

        # ----------------------------------------------------------------------
        # Read the complete Chrony tracking report once per attempt.
        # ----------------------------------------------------------------------
        if ! tracking_output="$(chronyc tracking 2>&1)"; then

            log_warning \
                "Unable to read Chrony tracking information on attempt ${current_attempt}/${maximum_attempts}."

        else

            # ------------------------------------------------------------------
            # Extract the Leap status.
            #
            # Example:
            #
            #     Leap status     : Normal
            #
            # Output:
            #
            #     Normal
            # ------------------------------------------------------------------
            leap_status="$(
                awk -F ':' '
                    /^Leap status/ {
                        value = $2
                        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                        print value
                        exit
                    }
                ' <<< "$tracking_output"
            )"


            # ------------------------------------------------------------------
            # Extract the signed System time offset.
            #
            # Examples:
            #
            #     System time : 5.200000000 seconds slow of NTP time
            #         -> -5.200000000
            #
            #     System time : 0.300000000 seconds fast of NTP time
            #         -> 0.300000000
            #
            # The sign is not important for the threshold, but preserving it
            # makes diagnostic output accurate.
            # ------------------------------------------------------------------
            system_time_offset="$(
                awk '
                    /^System time/ {
                        offset = $4

                        if ($6 == "slow") {
                            offset = -offset
                        }

                        print offset
                        exit
                    }
                ' <<< "$tracking_output"
            )"


            # ------------------------------------------------------------------
            # Validate that the extracted offset is numeric.
            # ------------------------------------------------------------------
            if [[ "$system_time_offset" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then

                # --------------------------------------------------------------
                # Convert the signed offset to an absolute value.
                # --------------------------------------------------------------
                absolute_offset="$(
                    awk -v value="$system_time_offset" '
                        BEGIN {
                            if (value < 0) {
                                value = -value
                            }

                            printf "%.9f", value
                        }
                    '
                )"


                # --------------------------------------------------------------
                # The server is healthy only when:
                #
                #     Leap status = Normal
                #     absolute offset <= 1 second
                # --------------------------------------------------------------
                if [[ "$leap_status" == "Normal" ]] &&
                   awk \
                       -v offset="$absolute_offset" \
                       -v maximum="$maximum_offset_seconds" \
                       'BEGIN { exit !(offset <= maximum) }'; then

                    log_success \
                        "Chrony is synchronized; system-time offset is ${absolute_offset} seconds."

                    return 0
                fi


                # --------------------------------------------------------------
                # Chrony has a valid source, but the local clock is still far
                # away from synchronized time.
                #
                # Apply the outstanding correction immediately.
                # --------------------------------------------------------------
                if [[ "$leap_status" == "Normal" ]] &&
                   awk \
                       -v offset="$absolute_offset" \
                       -v maximum="$maximum_offset_seconds" \
                       'BEGIN { exit !(offset > maximum) }'; then

                    log_warning \
                        "System-time offset is ${absolute_offset} seconds; applying an immediate Chrony step."


                    if ! chronyc makestep; then

                        log_error "Chrony failed to apply the clock correction."

                        return 1
                    fi
                fi
            else

                log_warning \
                    "Chrony did not return a readable system-time offset."
            fi
        fi


        if (( current_attempt < maximum_attempts )); then

            log_info \
                "Chrony verification attempt ${current_attempt}/${maximum_attempts} was not yet successful."

            sleep 3
        fi


        current_attempt=$((current_attempt + 1))
    done


    log_error \
        "Chrony synchronization was not confirmed within the allowed time."

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
# detect_docker_package_conflicts
# ==============================================================================
#
# Purpose:
#     Detect distribution-provided or otherwise conflicting Docker packages
#     before installing Docker Engine from Docker's official repository.
#
# Docker documents these packages as potential conflicts:
#
#     docker.io
#     docker-compose
#     docker-compose-v2
#     docker-doc
#     podman-docker
#     containerd
#     runc
#
# We deliberately do NOT remove packages automatically.
#
# Automatic package removal can affect:
#
#     - existing containers
#     - existing Docker configuration
#     - other software that depends on containerd or runc
#
# If conflicting packages are present and Docker CE is not already installed,
# the setup stops and reports exactly what must be reviewed.
# ==============================================================================
detect_docker_package_conflicts() {

    local -a conflicting_packages=(
        "docker.io"
        "docker-compose"
        "docker-compose-v2"
        "docker-doc"
        "podman-docker"
        "containerd"
        "runc"
    )

    local -a installed_conflicts=()
    local package_name


    # --------------------------------------------------------------------------
    # If Docker CE is already installed, the machine is already using the
    # official package family, so we do not treat auxiliary installed packages
    # as a migration blocker.
    # --------------------------------------------------------------------------
    if is_package_installed "docker-ce"; then

        return 0
    fi


    for package_name in "${conflicting_packages[@]}"; do

        if is_package_installed "$package_name"; then

            installed_conflicts+=("$package_name")
        fi
    done


    if (( ${#installed_conflicts[@]} == 0 )); then

        return 0
    fi


    log_error "Conflicting Docker packages are installed:"
    
    for package_name in "${installed_conflicts[@]}"; do
        log_error "  - $package_name"
    done


    log_error \
        "Stoleus will not remove existing container packages automatically."

    return 1
}


# ==============================================================================
# ensure_apt_keyring_directory
# ==============================================================================
#
# Purpose:
#     Ensure that the standard APT keyring directory exists.
#
# Docker's repository signing key will be stored at:
#
#     /etc/apt/keyrings/docker.asc
#
# `install -d`
#     Creates a directory.
#
# `-m 0755`
#     Sets directory permissions to:
#
#         owner  = read, write, execute
#         group  = read, execute
#         others = read, execute
# ==============================================================================
ensure_apt_keyring_directory() {

    local keyring_directory="/etc/apt/keyrings"


    require_root || return 1
    require_command "install" || return 1


    if [[ -d "$keyring_directory" ]]; then

        log_info "APT keyring directory already exists: $keyring_directory"

        return 0
    fi


    log_info "Creating APT keyring directory: $keyring_directory"


    if ! install -m 0755 -d "$keyring_directory"; then

        log_error "Failed to create APT keyring directory."

        return 1
    fi


    log_success "APT keyring directory created."
}


# ==============================================================================
# remove_legacy_docker_repository
# ==============================================================================
#
# Purpose:
#     Prevent Docker's official APT repository from being configured twice.
#
# Older installations may use:
#
#     /etc/apt/sources.list.d/docker.list
#
# The current Stoleus configuration uses:
#
#     /etc/apt/sources.list.d/docker.sources
#
# If both files point to Docker's official Ubuntu repository, APT prints:
#
#     Target Packages ... is configured multiple times
#
# Safety:
#     We remove docker.list only when it clearly references Docker's official
#     Ubuntu repository.
#
#     If the file exists but contains another repository, Stoleus stops instead
#     of deleting an unknown administrator-managed configuration.
# ==============================================================================
remove_legacy_docker_repository() {

    local legacy_repository_file="/etc/apt/sources.list.d/docker.list"
    local official_repository_url="https://download.docker.com/linux/ubuntu"


    require_root || return 1


    if [[ ! -e "$legacy_repository_file" ]]; then

        return 0
    fi


    if [[ ! -f "$legacy_repository_file" ]]; then

        log_error \
            "Legacy Docker repository path exists but is not a normal file: $legacy_repository_file"

        return 1
    fi


    if grep -Fq \
        "$official_repository_url" \
        "$legacy_repository_file"; then

        log_info \
            "Removing legacy Docker repository definition: $legacy_repository_file"


        if ! rm -f "$legacy_repository_file"; then

            log_error \
                "Failed to remove the legacy Docker repository definition."

            return 1
        fi


        # ----------------------------------------------------------------------
        # The APT source configuration changed.
        # ----------------------------------------------------------------------
        APT_METADATA_UPDATED=0

        log_success \
            "Legacy Docker repository definition removed."

        return 0
    fi


    log_error \
        "The legacy Docker repository file contains an unrecognized configuration: $legacy_repository_file"

    log_error \
        "Stoleus will not remove it automatically."

    return 1
}


# ==============================================================================
# configure_docker_repository
# ==============================================================================
#
# Purpose:
#     Configure Docker's official Ubuntu APT repository.
#
# Files created:
#
#     /etc/apt/keyrings/docker.asc
#     /etc/apt/sources.list.d/docker.sources
#
# The `.sources` file format is the modern deb822 APT source format.
#
# This function is idempotent:
#
#     - existing correct signing key is reused
#     - existing correct repository definition is reused
#     - package metadata is refreshed only when repository configuration changes
# ==============================================================================
configure_docker_repository() {

    local architecture
    local ubuntu_codename
    local expected_repository
    local temporary_file

    local keyring_file="/etc/apt/keyrings/docker.asc"
    local repository_file="/etc/apt/sources.list.d/docker.sources"


    require_root || return 1

    ensure_package_installed "ca-certificates" || return 1
    ensure_package_installed "curl" || return 1

    require_command "curl" || return 1
    require_command "dpkg" || return 1
    require_command "install" || return 1
    require_command "mktemp" || return 1
    require_command "cmp" || return 1

    ensure_apt_keyring_directory || return 1
	
	remove_legacy_docker_repository || return 1

    # --------------------------------------------------------------------------
    # Determine the package architecture.
    #
    # Typical result:
    #
    #     amd64
    # --------------------------------------------------------------------------
    architecture="$(dpkg --print-architecture)"


    # --------------------------------------------------------------------------
    # Read the Ubuntu release codename.
    #
    # Examples:
    #
    #     noble
    #     resolute
    #
    # Some Ubuntu derivatives provide UBUNTU_CODENAME, while standard Ubuntu
    # normally provides VERSION_CODENAME.
    # --------------------------------------------------------------------------
    ubuntu_codename="$(
        . /etc/os-release

        printf '%s' \
            "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    )"


    if [[ -z "$architecture" ]]; then

        log_error "Could not determine the operating-system architecture."

        return 1
    fi


    if [[ -z "$ubuntu_codename" ]]; then

        log_error "Could not determine the Ubuntu release codename."

        return 1
    fi


    log_info "Docker repository architecture: $architecture"
    log_info "Docker repository Ubuntu codename: $ubuntu_codename"


    # --------------------------------------------------------------------------
    # Download Docker's signing key only when it is missing.
    #
    # Native curl errors remain visible.
    # --------------------------------------------------------------------------
    if [[ -f "$keyring_file" ]]; then

        log_info "Docker repository signing key already exists."

    else

        log_info "Downloading Docker repository signing key."


        if ! curl \
            --fail \
            --silent \
            --show-error \
            --location \
            "https://download.docker.com/linux/ubuntu/gpg" \
            --output "$keyring_file"; then

            log_error "Failed to download Docker repository signing key."

            return 1
        fi


        if ! chmod a+r "$keyring_file"; then

            log_error "Failed to set Docker signing-key permissions."

            return 1
        fi


        log_success "Docker repository signing key installed."
    fi


    # --------------------------------------------------------------------------
    # Build the expected repository definition.
    #
    # We first write it to a temporary file so we can compare it safely with
    # an existing configuration.
    # --------------------------------------------------------------------------
    temporary_file="$(mktemp)"


    expected_repository="$(
        cat <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${ubuntu_codename}
Components: stable
Architectures: ${architecture}
Signed-By: ${keyring_file}
EOF
    )"


    printf '%s\n' "$expected_repository" > "$temporary_file"


    # --------------------------------------------------------------------------
    # If the existing source file exactly matches the expected configuration,
    # no repository change is required.
    # --------------------------------------------------------------------------
    if [[ -f "$repository_file" ]] &&
       cmp --silent "$temporary_file" "$repository_file"; then

        rm -f "$temporary_file"

        log_info "Docker APT repository is already configured."

        return 0
    fi


    log_info "Configuring Docker APT repository."


    if ! install \
        -m 0644 \
        "$temporary_file" \
        "$repository_file"; then

        rm -f "$temporary_file"

        log_error "Failed to configure Docker APT repository."

        return 1
    fi


    rm -f "$temporary_file"


    # --------------------------------------------------------------------------
    # The repository changed, so package metadata must be refreshed even if
    # another package triggered apt-get update earlier in this execution.
    # --------------------------------------------------------------------------
    APT_METADATA_UPDATED=0

    update_apt_metadata || return 1

    log_success "Docker APT repository configured."
}


# ==============================================================================
# verify_docker_repository_packages
# ==============================================================================
#
# Purpose:
#     Confirm that APT can find Docker CE from the configured repository.
#
# This prevents an unclear installation failure when:
#
#     - the Ubuntu release is not available in Docker's repository
#     - the source definition is incorrect
#     - repository metadata failed to load
#
# `apt-cache policy`
#     Displays available package versions.
#
# `Candidate: (none)`
#     Means APT cannot install the package.
# ==============================================================================
verify_docker_repository_packages() {

    local candidate_version


    require_command "apt-cache" || return 1


    candidate_version="$(
        apt-cache policy docker-ce |
            awk '/Candidate:/ {print $2; exit}'
    )"


    if [[ -z "$candidate_version" ]] ||
       [[ "$candidate_version" == "(none)" ]]; then

        log_error \
            "Docker CE is not available for this configured Ubuntu release."

        return 1
    fi


    log_info "Docker CE candidate version: $candidate_version"

    return 0
}


# ==============================================================================
# verify_docker_installation
# ==============================================================================
#
# Purpose:
#     Verify the complete Docker installation.
#
# Checks:
#
#     - Docker CLI
#     - Docker daemon
#     - Docker Compose plugin
#     - Docker Buildx plugin
#     - docker.service enabled
#     - docker.service active
#
# Commands print their version information so the report remains transparent.
# ==============================================================================
verify_docker_installation() {

    require_command "docker" || return 1
    require_command "systemctl" || return 1


    log_info "Verifying Docker Engine."

    docker --version || {
        log_error "Docker Engine verification failed."
        return 1
    }


    log_info "Verifying Docker Compose."

    docker compose version || {
        log_error "Docker Compose plugin verification failed."
        return 1
    }


    log_info "Verifying Docker Buildx."

    docker buildx version || {
        log_error "Docker Buildx plugin verification failed."
        return 1
    }


    if ! systemctl is-enabled --quiet docker.service; then

        log_error "Docker service is not enabled at boot."

        return 1
    fi


    if ! systemctl is-active --quiet docker.service; then

        log_error "Docker service is not currently running."

        return 1
    fi


    # --------------------------------------------------------------------------
    # `docker info` verifies communication with the daemon, not merely that the
    # Docker client executable exists.
    #
    # setup_docker runs as root, so socket permission is not an issue here.
    # --------------------------------------------------------------------------
    if ! docker info >/dev/null; then

        log_error "Docker daemon communication failed."

        return 1
    fi


    log_success "Docker installation verified."
}


# ==============================================================================
# setup_docker
# ==============================================================================
#
# Purpose:
#     Install and configure Docker Engine from Docker's official repository.
#
# The setup is idempotent:
#
#     - packages already installed are not reinstalled
#     - an existing repository definition is reused
#     - an enabled/running service is not restarted unnecessarily
# ==============================================================================
setup_docker() {

    require_root || return 1

    log_info "Starting Docker setup."


    detect_docker_package_conflicts || return 1

    configure_docker_repository || return 1

    verify_docker_repository_packages || return 1


    ensure_package_installed "docker-ce" || return 1
    ensure_package_installed "docker-ce-cli" || return 1
    ensure_package_installed "containerd.io" || return 1
    ensure_package_installed "docker-buildx-plugin" || return 1
    ensure_package_installed "docker-compose-plugin" || return 1


    ensure_service_enabled_and_running "docker.service" || return 1

    verify_docker_installation || return 1


    log_success "Docker setup completed successfully."
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
# setup_app_server
# ==============================================================================
#
# Purpose:
#     Configure the application-server baseline.
#
# The profile definition is intentionally declarative:
#
#     pipeline_begin
#     pipeline_step
#     pipeline_end
#
# The pipeline engine handles:
#
#     - step counting
#     - execution order
#     - progress output
#     - colored success/failure status
#     - failure summaries
# ==============================================================================
setup_app_server() {

    require_root || return 1

    pipeline_begin "Application server" || return 1

    pipeline_step "Chrony" setup_chrony || return 1
    pipeline_step "Firewall" setup_firewall || return 1
    pipeline_step "Docker" setup_docker || return 1

    pipeline_end
}


# ==============================================================================
# setup_stage_server
# ==============================================================================
#
# Purpose:
#     Configure the staging-server baseline.
#
# Staging currently uses the same baseline as the application server, but it
# remains a separate profile so staging-specific components can be added later.
# ==============================================================================
setup_stage_server() {

    require_root || return 1

    pipeline_begin "Staging server" || return 1

    pipeline_step "Chrony" setup_chrony || return 1
    pipeline_step "Firewall" setup_firewall || return 1
    pipeline_step "Docker" setup_docker || return 1

    pipeline_end
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
#!/usr/bin/env bash

set -Eeuo pipefail


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


    require_root || return $?
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


    require_root || return $?


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


    require_root || return $?

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

    require_root || return $?

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

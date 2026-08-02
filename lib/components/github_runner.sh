#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - GitHub Runner Component
# ==============================================================================
#
# This component installs and configures a GitHub Actions self-hosted runner.
#
# Responsibilities
#
#     - Validate user input
#     - Detect system architecture
#     - Download the GitHub Actions Runner
#     - Extract the runner package
#     - Configure the runner
#     - Install the systemd service
#     - Verify the installation
#
# Public entry point
#
#     github_runner_setup
#
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# github_runner_validate
# ==============================================================================
#
# Purpose:
#     Validate the GitHub Runner configuration before making any changes to the
#     server.
#
# Required variables:
#
#     GITHUB_RUNNER_URL
#         GitHub repository URL.
#
#         Example:
#
#             https://github.com/ivanstoskovic/noteverbal
#
#     GITHUB_RUNNER_SHORT_NAME
#         Short local identifier used for the installation directory.
#
#         Example:
#
#             noteverbal
#
#     GITHUB_RUNNER_LABELS
#         Comma-separated runner labels.
#
#         Example:
#
#             self-hosted,linux,x64,staging
#
#     GITHUB_RUNNER_USER
#         Linux user that will execute the runner service.
#
#         Default:
#
#             deployer
#
# Validation performed:
#
#     - command is running as root
#     - repository URL uses the expected GitHub format
#     - short name contains only safe characters
#     - labels are not empty or malformed
#     - Linux execution user exists
#     - /opt/runners exists or can be created later
#
# Return codes:
#
#     0 = configuration is valid
#     1 = configuration is invalid
# ==============================================================================
github_runner_validate() {

    local github_url_pattern
    local safe_name_pattern
    local labels_pattern


    log_info "Validating GitHub Runner configuration."


    # --------------------------------------------------------------------------
    # Runner installation and systemd service registration require root access.
    #
    # The runner service itself will later run as the non-root deployer user.
    # --------------------------------------------------------------------------
    require_root || return 1


    # --------------------------------------------------------------------------
    # Confirm that all expected variables exist.
    #
    # `${VARIABLE:-}`
    #     Produces an empty value when the variable is undefined.
    #
    # This is important because Stoleus uses:
    #
    #     set -u
    #
    # which normally treats undefined variables as fatal errors.
    # --------------------------------------------------------------------------
    if [[ -z "${GITHUB_RUNNER_URL:-}" ]]; then

        log_error "GitHub repository URL is required."
        log_error "Use: --url https://github.com/OWNER/REPOSITORY"

        return 1
    fi


    if [[ -z "${GITHUB_RUNNER_SHORT_NAME:-}" ]]; then

        log_error "GitHub Runner short name is required."
        log_error "Use: --name repository-name"

        return 1
    fi


    if [[ -z "${GITHUB_RUNNER_LABELS:-}" ]]; then

        log_error "At least one GitHub Runner label is required."
        log_error "Use: --labels self-hosted,linux,x64"

        return 1
    fi


    if [[ -z "${GITHUB_RUNNER_USER:-}" ]]; then

        log_error "GitHub Runner execution user is required."

        return 1
    fi


    # --------------------------------------------------------------------------
    # Validate the repository URL.
    #
    # Accepted:
    #
    #     https://github.com/OWNER/REPOSITORY
    #
    # Rejected:
    #
    #     http://github.com/OWNER/REPOSITORY
    #     https://gitlab.com/OWNER/REPOSITORY
    #     https://github.com/OWNER
    #     github.com/OWNER/REPOSITORY
    #
    # Owner and repository names may contain:
    #
    #     letters
    #     numbers
    #     dots
    #     underscores
    #     hyphens
    #
    # An optional trailing slash is accepted.
    # --------------------------------------------------------------------------
    github_url_pattern='^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/?$'


    if [[ ! "$GITHUB_RUNNER_URL" =~ $github_url_pattern ]]; then

        log_error "Invalid GitHub repository URL: $GITHUB_RUNNER_URL"
        log_error "Expected format: https://github.com/OWNER/REPOSITORY"

        return 1
    fi


    log_success "GitHub repository URL is valid."


    # --------------------------------------------------------------------------
    # Validate the short local runner name.
    #
    # This value will become part of a filesystem path:
    #
    #     /opt/runners/<short-name>
    #
    # Restricting characters prevents:
    #
    #     spaces
    #     path traversal
    #     shell metacharacters
    #     accidental nested directories
    #
    # Accepted examples:
    #
    #     noteverbal
    #     insurance-api
    #     tools_runner
    #     repository.v2
    # --------------------------------------------------------------------------
    safe_name_pattern='^[A-Za-z0-9][A-Za-z0-9._-]*$'


    if [[ ! "$GITHUB_RUNNER_SHORT_NAME" =~ $safe_name_pattern ]]; then

        log_error \
            "Invalid GitHub Runner short name: $GITHUB_RUNNER_SHORT_NAME"

        log_error \
            "Use only letters, numbers, dots, underscores, and hyphens."

        return 1
    fi


    # --------------------------------------------------------------------------
    # Keep the generated directory and service identifiers reasonably short.
    # --------------------------------------------------------------------------
    if (( ${#GITHUB_RUNNER_SHORT_NAME} > 64 )); then

        log_error "GitHub Runner short name must not exceed 64 characters."

        return 1
    fi


    log_success "GitHub Runner short name is valid."


    # --------------------------------------------------------------------------
    # Validate labels.
    #
    # Accepted:
    #
    #     linux
    #     linux,x64
    #     self-hosted,linux,x64,staging
    #
    # Rejected:
    #
    #     ,
    #     linux,
    #     ,linux
    #     linux,,x64
    #     linux label
    #
    # Each label follows the same safe-character convention as the short name.
    # --------------------------------------------------------------------------
    labels_pattern='^[A-Za-z0-9._-]+(,[A-Za-z0-9._-]+)*$'


    if [[ ! "$GITHUB_RUNNER_LABELS" =~ $labels_pattern ]]; then

        log_error "Invalid GitHub Runner labels: $GITHUB_RUNNER_LABELS"
        log_error \
            "Labels must be comma-separated and contain no spaces or empty values."

        return 1
    fi


    log_success "GitHub Runner labels are valid."


    # --------------------------------------------------------------------------
    # Verify that the requested Linux user exists.
    #
    # The Stoleus command runs as root, but the runner service must run as this
    # non-root account.
    # --------------------------------------------------------------------------
    if ! id -u "$GITHUB_RUNNER_USER" >/dev/null 2>&1; then

        log_error "GitHub Runner user does not exist: $GITHUB_RUNNER_USER"

        return 1
    fi


    # --------------------------------------------------------------------------
    # Running CI jobs as root would give every workflow unrestricted control of
    # the host operating system.
    # --------------------------------------------------------------------------
    if [[ "$GITHUB_RUNNER_USER" == "root" ]]; then

        log_error "GitHub Runner must not run as root."

        return 1
    fi


    log_success "GitHub Runner user exists: $GITHUB_RUNNER_USER"


    # --------------------------------------------------------------------------
    # Verify the base installation directory.
    #
    # The standard directories component should normally create:
    #
    #     /opt/runners
    #
    # We only validate it here. Creation and ownership correction will belong to
    # the installation phase.
    # --------------------------------------------------------------------------
    if [[ -e "/opt/runners" ]] && [[ ! -d "/opt/runners" ]]; then

        log_error "/opt/runners exists but is not a directory."

        return 1
    fi


    log_success "GitHub Runner configuration is valid."

    return 0
}


# ==============================================================================
# github_runner_detect_architecture
# ==============================================================================
#
# Purpose:
#     Detect the current machine architecture and map it to the architecture
#     names used by GitHub Actions Runner release packages.
#
# Supported mappings:
#
#     x86_64  -> x64
#     amd64   -> x64
#     aarch64 -> arm64
#     arm64   -> arm64
#
# Output:
#     Prints the GitHub Runner architecture name to stdout.
#
# Return codes:
#
#     0 = supported architecture detected
#     1 = architecture is unsupported or could not be detected
# ==============================================================================
github_runner_detect_architecture() {

    local machine_architecture
    local runner_architecture


    log_info "Detecting GitHub Runner architecture." >&2


    require_command "uname" || return 1


    machine_architecture="$(uname -m)"


    if [[ -z "$machine_architecture" ]]; then

        log_error "Could not determine the machine architecture."

        return 1
    fi


    case "$machine_architecture" in

        x86_64|amd64)

            runner_architecture="x64"

            ;;


        aarch64|arm64)

            runner_architecture="arm64"

            ;;


        *)

            log_error \
                "Unsupported GitHub Runner architecture: $machine_architecture"

            return 1

            ;;
    esac


    log_success \
        "GitHub Runner architecture detected: ${machine_architecture} -> ${runner_architecture}" >&2


    printf '%s\n' "$runner_architecture"

    return 0
}


# ==============================================================================
# github_runner_resolve_version
# ==============================================================================
#
# Purpose:
#     Validate and return the GitHub Actions Runner version selected for the
#     installation.
#
# Default:
#
#     2.334.0
#
# An alternative version may be supplied with:
#
#     --version 2.334.0
#
# Output:
#     Prints the validated version to stdout.
# ==============================================================================
github_runner_resolve_version() {

    local selected_version="${GITHUB_RUNNER_VERSION:-2.334.0}"
    local version_pattern='^[0-9]+\.[0-9]+\.[0-9]+$'


    log_info "Resolving GitHub Runner version." >&2


    if [[ ! "$selected_version" =~ $version_pattern ]]; then

        log_error "Invalid GitHub Runner version: $selected_version"
        log_error "Expected format: major.minor.patch"

        return 1
    fi


    log_success \
        "GitHub Runner version selected: $selected_version" >&2


    printf '%s\n' "$selected_version"

    return 0
}


# ==============================================================================
# github_runner_download
# ==============================================================================
#
# Purpose:
#     Download the GitHub Actions Runner archive selected for the current
#     operating-system architecture and configured runner version.
#
# Required variables:
#
#     GITHUB_RUNNER_ARCHITECTURE
#         GitHub package architecture.
#
#         Supported values:
#
#             x64
#             arm64
#
#     GITHUB_RUNNER_VERSION
#         Runner version without the leading "v".
#
#         Example:
#
#             2.334.0
#
# Download format:
#
#     https://github.com/actions/runner/releases/download/v<VERSION>/
#     actions-runner-linux-<ARCHITECTURE>-<VERSION>.tar.gz
#
# Output:
#     Prints the downloaded archive path to stdout.
#
# Return codes:
#
#     0 = archive downloaded successfully
#     1 = download failed
#     2 = required state is missing or invalid
# ==============================================================================
github_runner_download() {

    local runner_architecture="${GITHUB_RUNNER_ARCHITECTURE:-}"
    local runner_version="${GITHUB_RUNNER_VERSION:-}"

    local archive_name
    local archive_path
    local download_url


    log_info "Preparing GitHub Runner download." >&2


    # --------------------------------------------------------------------------
    # Validate state generated by the earlier component phases.
    # --------------------------------------------------------------------------
    if [[ -z "$runner_architecture" ]]; then

        log_error "GitHub Runner architecture has not been resolved."

        return 2
    fi


    if [[ -z "$runner_version" ]]; then

        log_error "GitHub Runner version has not been resolved."

        return 2
    fi


    case "$runner_architecture" in

        x64|arm64)

            ;;

        *)

            log_error \
                "Unsupported GitHub Runner download architecture: $runner_architecture"

            return 2

            ;;
    esac


    # --------------------------------------------------------------------------
    # Build the official GitHub Runner release asset name.
    #
    # Example:
    #
    #     actions-runner-linux-x64-2.334.0.tar.gz
    # --------------------------------------------------------------------------
    archive_name="actions-runner-linux-${runner_architecture}-${runner_version}.tar.gz"


    # --------------------------------------------------------------------------
    # Store temporary installation artifacts under /tmp.
    #
    # Including both architecture and version prevents collisions between
    # different packages.
    # --------------------------------------------------------------------------
    archive_path="/tmp/${archive_name}"


    # --------------------------------------------------------------------------
    # Build the official release download URL.
    # --------------------------------------------------------------------------
    download_url="https://github.com/actions/runner/releases/download/v${runner_version}/${archive_name}"


    log_info "GitHub Runner archive: $archive_name" >&2
    log_info "GitHub Runner download URL: $download_url" >&2


    # --------------------------------------------------------------------------
    # Use the shared download helper.
    #
    # download_file handles:
    #
    #     - HTTPS validation
    #     - temporary partial files
    #     - HTTP failures
    #     - empty downloads
    #     - final atomic move
    # --------------------------------------------------------------------------
    download_file \
        "$download_url" \
        "$archive_path" >&2 || return 1


    if [[ ! -s "$archive_path" ]]; then

        log_error \
            "GitHub Runner archive was not downloaded correctly: $archive_path"

        return 1
    fi


    log_success \
        "GitHub Runner archive downloaded: $archive_path" >&2


    # --------------------------------------------------------------------------
    # stdout is reserved for the function result so callers can capture it.
    # --------------------------------------------------------------------------
    printf '%s\n' "$archive_path"

    return 0
}


# ==============================================================================
# github_runner_extract
# ==============================================================================
#
# Purpose:
#     Create the runner installation directory and extract the downloaded
#     GitHub Actions Runner archive into it.
#
# Required variables:
#
#     GITHUB_RUNNER_SHORT_NAME
#         Short repository identifier.
#
#         Example:
#
#             noteverbal
#
#     GITHUB_RUNNER_USER
#         Linux user that will own and run the runner.
#
#     GITHUB_RUNNER_ARCHIVE_PATH
#         Path returned by github_runner_download().
#
# Installation directory:
#
#     /opt/runners/<short-name>
#
# Example:
#
#     /opt/runners/noteverbal
#
# Output:
#     Prints the installation directory to stdout.
# ==============================================================================
github_runner_extract() {

    local short_name="${GITHUB_RUNNER_SHORT_NAME:-}"
    local runner_user="${GITHUB_RUNNER_USER:-}"
    local archive_path="${GITHUB_RUNNER_ARCHIVE_PATH:-}"

    local installation_directory


    log_info "Preparing GitHub Runner extraction." >&2


    if [[ -z "$short_name" ]]; then

        log_error "GitHub Runner short name has not been provided."

        return 2
    fi


    if [[ -z "$runner_user" ]]; then

        log_error "GitHub Runner user has not been provided."

        return 2
    fi


    if [[ -z "$archive_path" ]]; then

        log_error "GitHub Runner archive path has not been provided."

        return 2
    fi


    if [[ ! -s "$archive_path" ]]; then

        log_error "GitHub Runner archive does not exist or is empty: $archive_path"

        return 1
    fi
	
	# --------------------------------------------------------------------------
	# Verify that all required system commands are available before continuing.
	# --------------------------------------------------------------------------
	require_command "find" || return 1
	require_command "chown" || return 1


    installation_directory="/opt/runners/${short_name}"


    # --------------------------------------------------------------------------
    # Refuse to overwrite an existing configured runner.
    #
    # GitHub Runner creates:
    #
    #     .runner
    #
    # after successful registration.
    # --------------------------------------------------------------------------
    if [[ -f "${installation_directory}/.runner" ]]; then

        log_info \
            "GitHub Runner is already configured: $installation_directory" >&2

        printf '%s\n' "$installation_directory"

        return 0
    fi


    # --------------------------------------------------------------------------
    # Avoid extracting into a non-empty unknown directory.
    #
    # This protects files from a failed or manually managed installation.
    # --------------------------------------------------------------------------
    if [[ -d "$installation_directory" ]] &&
       [[ -n "$(find "$installation_directory" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then

        log_error \
            "GitHub Runner directory exists and is not empty: $installation_directory"

        log_error \
            "Stoleus will not overwrite an unknown or incomplete installation."

        return 1
    fi


    create_directory \
        "$installation_directory" \
        "0755" \
        "$runner_user" \
        "$runner_user" >&2 || return 1


    extract_tar_gz \
        "$archive_path" \
        "$installation_directory" >&2 || return 1


    # --------------------------------------------------------------------------
    # Ensure extracted files belong to the service account.
    # --------------------------------------------------------------------------
    if ! chown -R \
        "${runner_user}:${runner_user}" \
        "$installation_directory"; then

        log_error \
            "Failed to set GitHub Runner ownership: $installation_directory"

        return 1
    fi


    if [[ ! -x "${installation_directory}/config.sh" ]]; then

        log_error \
            "GitHub Runner extraction verification failed: config.sh is missing."

        return 1
    fi


    log_success \
        "GitHub Runner extracted successfully: $installation_directory" >&2


    printf '%s\n' "$installation_directory"

    return 0
}


# ==============================================================================
# github_runner_configure
# ==============================================================================
#
# Purpose:
#     Register the extracted GitHub Actions Runner with a GitHub repository.
#
# Required variables:
#
#     GITHUB_RUNNER_URL
#     GITHUB_RUNNER_SHORT_NAME
#     GITHUB_RUNNER_LABELS
#     GITHUB_RUNNER_USER
#     GITHUB_RUNNER_INSTALLATION_DIRECTORY
#
# Runner identity:
#
#     Local directory:
#
#         /opt/runners/<short-name>
#
#     GitHub-visible runner name:
#
#         <hostname>-<short-name>
#
# Token handling:
#
#     The temporary registration token is requested using a hidden prompt.
#     It is held only in memory for the duration of this function.
#
# Output:
#     Prints the generated GitHub-visible runner name to stdout.
# ==============================================================================
github_runner_configure() {

    local repository_url="${GITHUB_RUNNER_URL:-}"
    local short_name="${GITHUB_RUNNER_SHORT_NAME:-}"
    local runner_labels="${GITHUB_RUNNER_LABELS:-}"
    local runner_user="${GITHUB_RUNNER_USER:-}"
    local installation_directory="${GITHUB_RUNNER_INSTALLATION_DIRECTORY:-}"

    local server_hostname
    local github_runner_name
    local registration_token=""


    log_info "Preparing GitHub Runner registration." >&2


    # --------------------------------------------------------------------------
    # Validate state produced by earlier phases.
    # --------------------------------------------------------------------------
    if [[ -z "$repository_url" ]]; then

        log_error "GitHub repository URL has not been provided."

        return 2
    fi


    if [[ -z "$short_name" ]]; then

        log_error "GitHub Runner short name has not been provided."

        return 2
    fi


    if [[ -z "$runner_labels" ]]; then

        log_error "GitHub Runner labels have not been provided."

        return 2
    fi


    if [[ -z "$runner_user" ]]; then

        log_error "GitHub Runner user has not been provided."

        return 2
    fi


    if [[ -z "$installation_directory" ]]; then

        log_error "GitHub Runner installation directory has not been resolved."

        return 2
    fi


    require_command "hostname" || return 1
    require_command "sudo" || return 1


    if [[ ! -x "${installation_directory}/config.sh" ]]; then

        log_error \
            "GitHub Runner configuration script is missing: ${installation_directory}/config.sh"

        return 1
    fi


    # --------------------------------------------------------------------------
    # Build the runner name displayed in GitHub.
    #
    # Example:
    #
    #     hostname   = stoleusstage
    #     short name = noteverbal
    #
    # Result:
    #
    #     stoleusstage-noteverbal
    # --------------------------------------------------------------------------
    server_hostname="$(hostname --short)"


    if [[ -z "$server_hostname" ]]; then

        log_error "Could not determine the server hostname."

        return 1
    fi


    github_runner_name="${server_hostname}-${short_name}"


    # --------------------------------------------------------------------------
    # A successfully configured runner contains a .runner metadata file.
    #
    # Re-running setup should not request another token or register it again.
    # --------------------------------------------------------------------------
    if [[ -f "${installation_directory}/.runner" ]]; then

        log_info \
            "GitHub Runner is already registered: $github_runner_name" >&2

        printf '%s\n' "$github_runner_name"

        return 0
    fi


    # --------------------------------------------------------------------------
    # Registration requires a temporary GitHub token.
    #
    # `read -s`
    #     Prevents the token from being displayed.
    #
    # `read -r`
    #     Prevents backslash interpretation.
    #
    # The token is not written to a file by Stoleus.
    # --------------------------------------------------------------------------
    if [[ ! -t 0 ]]; then

        log_error \
            "GitHub Runner registration requires an interactive terminal."

        return 1
    fi


    printf 'GitHub registration token: ' >&2

    if ! IFS= read -r -s registration_token; then

        printf '\n' >&2

        log_error "Failed to read the GitHub registration token."

        return 1
    fi

    printf '\n' >&2


    if [[ -z "$registration_token" ]]; then

        log_error "GitHub registration token must not be empty."

        return 1
    fi


    log_info \
        "Registering GitHub Runner: $github_runner_name" >&2


    # --------------------------------------------------------------------------
    # Run config.sh as the non-root runner account.
    #
    # Options:
    #
    #     --url
    #         Repository receiving the runner.
    #
    #     --token
    #         Temporary registration token.
    #
    #     --name
    #         Name displayed in GitHub.
    #
    #     --labels
    #         Labels used by workflow `runs-on` selection.
    #
    #     --work
    #         Runner job workspace relative to its installation directory.
    #
    #     --unattended
    #         Do not ask interactive configuration questions.
    # --------------------------------------------------------------------------
    if ! sudo \
        --user "$runner_user" \
        --set-home \
        bash -c '
            cd -- "$1"

            exec ./config.sh \
                --url "$2" \
                --token "$3" \
                --name "$4" \
                --labels "$5" \
                --work "_work" \
                --unattended
        ' bash \
        "$installation_directory" \
        "$repository_url" \
        "$registration_token" \
        "$github_runner_name" \
        "$runner_labels" >&2; then

        unset registration_token

        log_error "GitHub Runner registration failed."

        return 1
    fi


    # --------------------------------------------------------------------------
    # Remove the token from the shell variable as soon as registration finishes.
    # --------------------------------------------------------------------------
    unset registration_token


    if [[ ! -f "${installation_directory}/.runner" ]]; then

        log_error \
            "GitHub Runner registration could not be verified."

        return 1
    fi


    log_success \
        "GitHub Runner registered successfully: $github_runner_name" >&2


    printf '%s\n' "$github_runner_name"

    return 0
}


# ==============================================================================
# github_runner_install_service
# ==============================================================================
#
# Purpose:
#     Install and start the systemd service for this specific GitHub Runner.
#
# The service is installed for GITHUB_RUNNER_USER, never for root.
#
# Output:
#     Prints the exact systemd service name to stdout.
# ==============================================================================
github_runner_install_service() {

    local installation_directory="${GITHUB_RUNNER_INSTALLATION_DIRECTORY:-}"
    local runner_user="${GITHUB_RUNNER_USER:-}"
    local runner_name="${GITHUB_RUNNER_NAME:-}"

    local service_name
    local -a matching_services=()


    log_info "Installing GitHub Runner service." >&2


    if [[ -z "$installation_directory" ]]; then

        log_error "GitHub Runner installation directory has not been resolved."

        return 2
    fi


    if [[ -z "$runner_user" ]]; then

        log_error "GitHub Runner service user has not been provided."

        return 2
    fi


    if [[ -z "$runner_name" ]]; then

        log_error "GitHub Runner name has not been resolved."

        return 2
    fi


    require_root || return 1
    require_command "systemctl" || return 1


    if [[ ! -x "${installation_directory}/svc.sh" ]]; then

        log_error \
            "GitHub Runner service script is missing: ${installation_directory}/svc.sh"

        return 1
    fi


    # --------------------------------------------------------------------------
    # If the service is not installed yet, install it for the non-root account.
    #
    # GitHub's svc.sh accepts the service user as its first argument:
    #
    #     ./svc.sh install deployer
    # --------------------------------------------------------------------------
    if ! systemctl list-unit-files \
        --type=service \
        --no-legend |
        awk '{print $1}' |
        grep -Fq ".${runner_name}.service"; then

        log_info \
            "Installing GitHub Runner service for user: $runner_user" >&2


        if ! (
            cd -- "$installation_directory"

            ./svc.sh install "$runner_user"
        ) >&2; then

            log_error "Failed to install GitHub Runner service."

            return 1
        fi
    else

        log_info "GitHub Runner service is already installed." >&2
    fi


    # --------------------------------------------------------------------------
    # Find the exact service whose final component matches the generated runner
    # name.
    #
    # Example:
    #
    #     actions.runner.owner-repository.stoleusstage-noteverbal.service
    # --------------------------------------------------------------------------
    mapfile -t matching_services < <(
        systemctl list-unit-files \
            --type=service \
            --no-legend |
            awk '{print $1}' |
            grep -F ".${runner_name}.service" || true
    )


    if (( ${#matching_services[@]} == 0 )); then

        log_error \
            "GitHub Runner service could not be located for runner: $runner_name"

        return 1
    fi


    if (( ${#matching_services[@]} > 1 )); then

        log_error \
            "Multiple GitHub Runner services matched runner name: $runner_name"

        return 1
    fi


    service_name="${matching_services[0]}"


    ensure_service_enabled_and_running "$service_name" >&2 || return 1


    log_success \
        "GitHub Runner service installed and running: $service_name" >&2


    printf '%s\n' "$service_name"

    return 0
}


# ==============================================================================
# github_runner_verify
# ==============================================================================
#
# Purpose:
#     Verify the exact systemd service belonging to the configured runner.
# ==============================================================================
github_runner_verify() {

    local service_name="${GITHUB_RUNNER_SERVICE_NAME:-}"


    log_info "Verifying GitHub Runner installation."


    if [[ -z "$service_name" ]]; then

        log_error "GitHub Runner service name has not been resolved."

        return 2
    fi


    require_command "systemctl" || return 1


    if ! systemctl cat "$service_name" >/dev/null 2>&1; then

        log_error "GitHub Runner service does not exist: $service_name"

        return 1
    fi


    if ! systemctl is-enabled --quiet "$service_name"; then

        log_error "GitHub Runner service is not enabled: $service_name"

        return 1
    fi


    if ! systemctl is-active --quiet "$service_name"; then

        log_error "GitHub Runner service is not running: $service_name"

        return 1
    fi


    log_success \
        "GitHub Runner installation verified: $service_name"

    return 0
}
# ==============================================================================
# setup_github_runner
# ==============================================================================
#
# Purpose
#
#     Install and configure a GitHub Actions self-hosted runner.
#
# Execution Flow
#
#     Validate input
#             ↓
#     Detect architecture
#             ↓
#     Resolve version
#             ↓
#     Download runner
#             ↓
#     Extract runner
#             ↓
#     Configure runner
#             ↓
#     Install service
#             ↓
#     Verify installation
#
# Public Entry Point
#
#     This is the only function that should be called from outside this
#     component.
# ==============================================================================

# ==============================================================================
# github_runner_setup
# ==============================================================================
#
# Purpose:
#     Install and configure a GitHub Actions self-hosted runner.
#
# This function is the public entry point for the component.
# ==============================================================================
github_runner_setup() {

    log_info "Starting GitHub Runner setup."


    github_runner_validate || return 1


    GITHUB_RUNNER_ARCHITECTURE="$(
        github_runner_detect_architecture
    )" || return 1


    GITHUB_RUNNER_VERSION="$(
        github_runner_resolve_version
    )" || return 1


    GITHUB_RUNNER_ARCHIVE_PATH="$(
        github_runner_download
    )" || return 1


    GITHUB_RUNNER_INSTALLATION_DIRECTORY="$(
        github_runner_extract
    )" || return 1


    GITHUB_RUNNER_NAME="$(
        github_runner_configure
    )" || return 1


    GITHUB_RUNNER_SERVICE_NAME="$(
		github_runner_install_service
	)" || return 1

    github_runner_verify || return 1


    log_info \
        "Selected GitHub Runner architecture: $GITHUB_RUNNER_ARCHITECTURE"

    log_info \
        "Selected GitHub Runner version: $GITHUB_RUNNER_VERSION"

    log_info \
        "Downloaded GitHub Runner archive: $GITHUB_RUNNER_ARCHIVE_PATH"

    log_info \
        "GitHub Runner installation directory: $GITHUB_RUNNER_INSTALLATION_DIRECTORY"

    log_info \
        "Registered GitHub Runner name: $GITHUB_RUNNER_NAME"
		
	log_info \
		"GitHub Runner service: $GITHUB_RUNNER_SERVICE_NAME"


    log_success "GitHub Runner setup completed successfully."

    return 0
}




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
    require_root ||
    return "${STOLEUS_EXIT_PERMISSION:-5}"

	# --------------------------------------------------------------------------
    # GitHub Runner registration and OAuth session creation are time-sensitive.
    # Refuse registration if the machine clock differs materially from GitHub.
    # --------------------------------------------------------------------------
    verify_remote_clock_skew \
        "https://github.com" \
        "30" || return $?
		
		
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
# github_runner_get_installed_version
# ==============================================================================
#
# Purpose:
#     Read the version of an existing extracted GitHub Actions Runner.
#
# Arguments:
#
#     $1 = runner installation directory
#
# Output:
#     Prints the installed version to stdout.
#
# Return codes:
#
#     0 = installed version found
#     1 = installation or version unavailable
#     2 = invalid argument
# ==============================================================================
github_runner_get_installed_version() {

    local installation_directory="${1:-}"
    local listener_path
    local installed_version


    if [[ -z "$installation_directory" ]]; then

        log_error \
            "github_runner_get_installed_version requires an installation directory."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    listener_path="${installation_directory}/bin/Runner.Listener"


    if [[ ! -x "$listener_path" ]]; then

        return "${STOLEUS_EXIT_FAILURE:-1}"
    fi


    if ! installed_version="$(
        "$listener_path" --version 2>/dev/null
    )"; then

        return "${STOLEUS_EXIT_FAILURE:-1}"
    fi


    installed_version="${installed_version//$'\r'/}"
    installed_version="${installed_version//$'\n'/}"


    if [[ ! "$installed_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then

        return "${STOLEUS_EXIT_FAILURE:-1}"
    fi


    printf '%s\n' "$installed_version"

    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# github_runner_compare_versions
# ==============================================================================
#
# Purpose:
#     Compare two semantic-style version numbers using GNU version sorting.
#
# Usage:
#
#     comparison="$(
#         github_runner_compare_versions \
#             "2.336.0" \
#             "2.334.0"
#     )"
#
# Arguments:
#
#     $1 = left version
#     $2 = right version
#
# Output:
#
#     -1
#         Left version is older than the right version.
#
#      0
#         Both versions are equal.
#
#      1
#         Left version is newer than the right version.
#
# Example:
#
#     github_runner_compare_versions "2.336.0" "2.334.0"
#
# outputs:
#
#     1
#
# Return codes:
#
#     0 = comparison completed successfully
#     2 = invalid arguments
#     3 = required command unavailable
# ==============================================================================
github_runner_compare_versions() {

    local left_version="${1:-}"
    local right_version="${2:-}"

    local oldest_version=""


    if [[ -z "$left_version" ]]; then

        log_error \
            "github_runner_compare_versions requires a left version."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if [[ -z "$right_version" ]]; then

        log_error \
            "github_runner_compare_versions requires a right version."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    require_command "sort" ||
        return "${STOLEUS_EXIT_DEPENDENCY:-3}"


    if [[ "$left_version" == "$right_version" ]]; then

        printf '0\n'

        return "${STOLEUS_EXIT_SUCCESS:-0}"
    fi


    # --------------------------------------------------------------------------
    # Sort both versions from oldest to newest.
    #
    # sed reads the complete pipeline and prints only the first line. This avoids
    # the early-pipeline termination behavior associated with grep -q or head
    # while pipefail is enabled.
    # --------------------------------------------------------------------------
    if ! oldest_version="$(
        printf '%s\n%s\n' \
            "$left_version" \
            "$right_version" |
            sort -V |
            sed -n '1p'
    )"; then

        log_error \
            "Failed to compare GitHub Runner versions."

        return "${STOLEUS_EXIT_FAILURE:-1}"
    fi


    if [[ "$oldest_version" == "$left_version" ]]; then

        printf '%s\n' '-1'

    else

        printf '%s\n' '1'
    fi


    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# github_runner_requested_version_is_installed
# ==============================================================================
#
# Purpose:
#     Determine whether an existing GitHub Runner installation satisfies the
#     requested minimum version.
#
# Version policy:
#
#     installed version == requested version
#         The installation is reused.
#
#     installed version > requested version
#         The newer installation is reused.
#
#         GitHub Actions runners may update themselves automatically, so a newer
#         installed version is valid and must not be downgraded.
#
#     installed version < requested version
#         The installation does not satisfy the requested minimum.
#
#         Stoleus currently stops with a version conflict because an in-place
#         Runner upgrade lifecycle has not yet been implemented.
#
#     no valid installation found
#         Return 1 so github_runner_setup() downloads a new installation.
#
# Required variables:
#
#     GITHUB_RUNNER_VERSION
#     GITHUB_RUNNER_INSTALLATION_DIRECTORY
#
# Generated state:
#
#     GITHUB_RUNNER_VERSION
#
#         When a newer Runner is already installed, this variable is updated to
#         the actual installed version so all later phases and summary messages
#         use accurate state.
#
# Return codes:
#
#     0 = existing installation satisfies the requested minimum version
#     1 = no valid Runner installation was found
#     2 = required state is missing
#     8 = installed Runner is older than the requested minimum
# ==============================================================================
github_runner_requested_version_is_installed() {

    local requested_version="${GITHUB_RUNNER_VERSION:-}"
    local installation_directory="${GITHUB_RUNNER_INSTALLATION_DIRECTORY:-}"

    local installed_version=""
    local version_comparison=""


    if [[ -z "$requested_version" ]]; then

        log_error \
            "GitHub Runner version has not been resolved."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if [[ -z "$installation_directory" ]]; then

        log_error \
            "GitHub Runner installation directory has not been resolved."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    # --------------------------------------------------------------------------
    # A missing or unreadable Runner.Listener means there is no reusable Runner
    # installation at this path.
    #
    # This is not logged as an error because it is a normal first-install state.
    # --------------------------------------------------------------------------
    if ! installed_version="$(
        github_runner_get_installed_version \
            "$installation_directory"
    )"; then

        log_debug \
            "No valid GitHub Runner installation was found in: $installation_directory"

        return "${STOLEUS_EXIT_FAILURE:-1}"
    fi


    if ! version_comparison="$(
        github_runner_compare_versions \
            "$installed_version" \
            "$requested_version"
    )"; then

        return $?
    fi


    case "$version_comparison" in

        0)

            log_info \
                "GitHub Runner ${requested_version} is already installed; archive download is not required."

            return "${STOLEUS_EXIT_SUCCESS:-0}"

            ;;


        1)

            log_info \
                "Installed GitHub Runner version ${installed_version} is newer than requested version ${requested_version}."

            log_info \
                "The newer installed GitHub Runner will be reused; archive download is not required."


            # ------------------------------------------------------------------
            # Use the actual installed version throughout the remaining setup
            # lifecycle and in the final summary.
            #
            # This function is called directly, not through command substitution,
            # so this global state change remains available to the caller.
            # ------------------------------------------------------------------
            GITHUB_RUNNER_VERSION="$installed_version"

            return "${STOLEUS_EXIT_SUCCESS:-0}"

            ;;


        -1)

            log_error \
                "Installed GitHub Runner version ${installed_version} is older than requested minimum version ${requested_version}."

            log_error \
                "Automatic GitHub Runner upgrades are not implemented yet."

            log_error \
                "Stoleus will not overwrite or partially upgrade the existing Runner installation."

            return "${STOLEUS_EXIT_CONFLICT:-8}"

            ;;


        *)

            log_error \
                "Unexpected GitHub Runner version-comparison result: $version_comparison"

            return "${STOLEUS_EXIT_FAILURE:-1}"

            ;;
    esac
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
#     Reuse an existing valid GitHub Runner installation or extract a newly
#     downloaded Runner archive.
#
# Existing-installation policy:
#
#     installed version == requested version
#         Reuse the existing installation.
#
#     installed version > requested version
#         Reuse the newer existing installation.
#
#     installed version < requested version
#         Stop with a conflict because automatic in-place upgrades are not yet
#         implemented.
#
# Valid reusable states:
#
#     - Runner files exist and `.runner` exists:
#           Runner is extracted and locally configured.
#
#     - Runner files exist and `.runner` does not exist:
#           Runner is extracted but requires registration.
#
# Unknown non-empty directories are never overwritten.
#
# Required variables:
#
#     GITHUB_RUNNER_SHORT_NAME
#     GITHUB_RUNNER_USER
#     GITHUB_RUNNER_VERSION
#
# Optional variable:
#
#     GITHUB_RUNNER_ARCHIVE_PATH
#
#         Required only when no valid existing installation is available.
#
# Output:
#     Prints the verified installation directory to stdout.
#
# Return codes:
#
#     0 = installation reused or extracted successfully
#     2 = required state is missing
#     3 = required command unavailable
#     5 = permission or ownership failure
#     6 = invalid installation or archive configuration
#     7 = extraction verification failed
#     8 = existing installation conflicts with the requested version
# ==============================================================================
github_runner_extract() {

    local short_name="${GITHUB_RUNNER_SHORT_NAME:-}"
    local runner_user="${GITHUB_RUNNER_USER:-}"
    local requested_version="${GITHUB_RUNNER_VERSION:-}"
    local archive_path="${GITHUB_RUNNER_ARCHIVE_PATH:-}"

    local installation_directory=""
    local installed_version=""
    local version_comparison=""


    log_info "Preparing GitHub Runner extraction." >&2


    if [[ -z "$short_name" ]]; then

        log_error \
            "GitHub Runner short name has not been provided."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if [[ -z "$runner_user" ]]; then

        log_error \
            "GitHub Runner user has not been provided."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if [[ -z "$requested_version" ]]; then

        log_error \
            "GitHub Runner version has not been resolved."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    installation_directory="/opt/runners/${short_name}"


    require_command "find" ||
        return "${STOLEUS_EXIT_DEPENDENCY:-3}"

    require_command "chown" ||
        return "${STOLEUS_EXIT_DEPENDENCY:-3}"


    # --------------------------------------------------------------------------
    # Detect and validate a reusable existing Runner installation.
    #
    # Runner.Listener --version distinguishes a genuine extracted Runner package
    # from an arbitrary non-empty directory.
    # --------------------------------------------------------------------------
    if installed_version="$(
        github_runner_get_installed_version \
            "$installation_directory"
    )"; then

        if ! version_comparison="$(
            github_runner_compare_versions \
                "$installed_version" \
                "$requested_version"
        )"; then

            return $?
        fi


        case "$version_comparison" in

            0)

                log_debug \
                    "Existing GitHub Runner version matches the requested version: $installed_version"

                ;;


            1)

                log_info \
                    "Using newer installed GitHub Runner version ${installed_version} instead of requested version ${requested_version}." >&2

                ;;


            -1)

                log_error \
                    "Existing GitHub Runner is older than the requested minimum version."

                log_error \
                    "Installation directory: $installation_directory"

                log_error \
                    "Installed version: $installed_version"

                log_error \
                    "Requested minimum version: $requested_version"

                log_error \
                    "Automatic in-place Runner upgrades are not implemented yet."

                return "${STOLEUS_EXIT_CONFLICT:-8}"

                ;;


            *)

                log_error \
                    "Unexpected GitHub Runner version-comparison result: $version_comparison"

                return "${STOLEUS_EXIT_FAILURE:-1}"

                ;;
        esac


        # ----------------------------------------------------------------------
        # Verify the required official Runner scripts before reusing the
        # installation.
        # ----------------------------------------------------------------------
        if [[ ! -x "${installation_directory}/config.sh" ]] ||
           [[ ! -x "${installation_directory}/run.sh" ]] ||
           [[ ! -x "${installation_directory}/svc.sh" ]] ||
           [[ ! -x "${installation_directory}/bin/Runner.Listener" ]]; then

            log_error \
                "Existing GitHub Runner installation is incomplete: $installation_directory"

            return "${STOLEUS_EXIT_CONFIGURATION:-6}"
        fi


        if [[ -f "${installation_directory}/.runner" ]]; then

            log_info \
                "GitHub Runner is already configured: $installation_directory" >&2

        else

            log_info \
                "GitHub Runner files are already extracted and ready for registration: $installation_directory" >&2
        fi


        printf '%s\n' "$installation_directory"

        return "${STOLEUS_EXIT_SUCCESS:-0}"
    fi


    # --------------------------------------------------------------------------
    # The directory exists but does not contain a readable official Runner.
    #
    # Never overwrite unknown or incomplete content automatically.
    # --------------------------------------------------------------------------
    if [[ -d "$installation_directory" ]] &&
       [[ -n "$(
           find \
               "$installation_directory" \
               -mindepth 1 \
               -maxdepth 1 \
               -print \
               -quit
       )" ]]; then

        log_error \
            "GitHub Runner directory exists but is not a valid Runner installation: $installation_directory"

        log_error \
            "Stoleus will not overwrite an unknown or incomplete directory."

        return "${STOLEUS_EXIT_CONFLICT:-8}"
    fi


    # --------------------------------------------------------------------------
    # A new installation requires a downloaded archive.
    # --------------------------------------------------------------------------
    if [[ -z "$archive_path" ]]; then

        log_error \
            "GitHub Runner archive path has not been provided for a new installation."

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    if [[ ! -s "$archive_path" ]]; then

        log_error \
            "GitHub Runner archive does not exist or is empty: $archive_path"

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    create_directory \
        "$installation_directory" \
        "0755" \
        "$runner_user" \
        "$runner_user" >&2 ||
        return "${STOLEUS_EXIT_FAILURE:-1}"


    extract_tar_gz \
        "$archive_path" \
        "$installation_directory" >&2 ||
        return "${STOLEUS_EXIT_FAILURE:-1}"


    # --------------------------------------------------------------------------
    # Ensure that the configured non-root Runner account owns all extracted
    # files.
    # --------------------------------------------------------------------------
    if ! chown -R \
        "${runner_user}:${runner_user}" \
        "$installation_directory"; then

        log_error \
            "Failed to set GitHub Runner ownership: $installation_directory"

        return "${STOLEUS_EXIT_PERMISSION:-5}"
    fi


    # --------------------------------------------------------------------------
    # Verify critical extracted files.
    # --------------------------------------------------------------------------
    if [[ ! -x "${installation_directory}/config.sh" ]] ||
       [[ ! -x "${installation_directory}/run.sh" ]] ||
       [[ ! -x "${installation_directory}/svc.sh" ]] ||
       [[ ! -x "${installation_directory}/bin/Runner.Listener" ]]; then

        log_error \
            "GitHub Runner extraction verification failed."

        return "${STOLEUS_EXIT_VERIFICATION:-7}"
    fi


    if ! installed_version="$(
        github_runner_get_installed_version \
            "$installation_directory"
    )"; then

        log_error \
            "Could not determine the extracted GitHub Runner version."

        return "${STOLEUS_EXIT_VERIFICATION:-7}"
    fi


    # --------------------------------------------------------------------------
    # A newly downloaded archive must exactly match the resolved requested
    # version.
    # --------------------------------------------------------------------------
    if [[ "$installed_version" != "$requested_version" ]]; then

        log_error \
            "Extracted GitHub Runner version does not match the requested version."

        log_error \
            "Extracted version: $installed_version"

        log_error \
            "Requested version: $requested_version"

        return "${STOLEUS_EXIT_VERIFICATION:-7}"
    fi


    log_success \
        "GitHub Runner extracted successfully: $installation_directory" >&2


    printf '%s\n' "$installation_directory"

    return "${STOLEUS_EXIT_SUCCESS:-0}"
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

	register_secret "$registration_token" || {

		unset registration_token

		return 1
	}


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

		unregister_secret "$registration_token"
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
#     Locate or install the systemd service belonging to this GitHub Runner,
#     then ensure that the exact service is enabled and running.
#
# Output:
#     Prints the exact systemd service name to stdout.
# ==============================================================================
github_runner_install_service() {

    local installation_directory="${GITHUB_RUNNER_INSTALLATION_DIRECTORY:-}"
    local runner_user="${GITHUB_RUNNER_USER:-}"
    local runner_name="${GITHUB_RUNNER_NAME:-}"

    local service_name=""
    local -a matching_services=()


    log_info "Installing GitHub Runner service." >&2


    if [[ -z "$installation_directory" ]]; then

        log_error \
            "GitHub Runner installation directory has not been resolved."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if [[ -z "$runner_user" ]]; then

        log_error "GitHub Runner service user has not been provided."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if [[ -z "$runner_name" ]]; then

        log_error "GitHub Runner name has not been resolved."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    require_root ||
        return "${STOLEUS_EXIT_PERMISSION:-5}"

    require_command "systemctl" ||
        return "${STOLEUS_EXIT_DEPENDENCY:-3}"

    require_command "awk" ||
        return "${STOLEUS_EXIT_DEPENDENCY:-3}"

    require_command "grep" ||
        return "${STOLEUS_EXIT_DEPENDENCY:-3}"


    if [[ ! -x "${installation_directory}/svc.sh" ]]; then

        log_error \
            "GitHub Runner service script is missing: ${installation_directory}/svc.sh"

        return "${STOLEUS_EXIT_CONFIGURATION:-6}"
    fi


    # --------------------------------------------------------------------------
    # Discover the existing service before attempting installation.
    #
    # Do not use grep -q in a pipe while pipefail is enabled. grep -q may stop
    # reading after the first match, causing an upstream command to receive
    # SIGPIPE and making the pipeline appear to have failed.
    # --------------------------------------------------------------------------
    mapfile -t matching_services < <(
        systemctl list-unit-files \
            --type=service \
            --no-legend |
            awk '{print $1}' |
            grep -F ".${runner_name}.service" || true
    )


    if (( ${#matching_services[@]} > 1 )); then

        log_error \
            "Multiple GitHub Runner services matched runner name: $runner_name"

        printf 'Matched service: %s\n' \
            "${matching_services[@]}" >&2

        return "${STOLEUS_EXIT_CONFLICT:-8}"
    fi


    if (( ${#matching_services[@]} == 1 )); then

        service_name="${matching_services[0]}"

        log_info \
            "GitHub Runner service is already installed: $service_name" >&2

    else

        log_info \
            "Installing GitHub Runner service for user: $runner_user" >&2


        if ! (
            cd -- "$installation_directory"

            ./svc.sh install "$runner_user"
        ) >&2; then

            log_error "Failed to install GitHub Runner service."

            return "${STOLEUS_EXIT_FAILURE:-1}"
        fi


        # ----------------------------------------------------------------------
        # Discover the exact service created by svc.sh.
        # ----------------------------------------------------------------------
        mapfile -t matching_services < <(
            systemctl list-unit-files \
                --type=service \
                --no-legend |
                awk '{print $1}' |
                grep -F ".${runner_name}.service" || true
        )


        if (( ${#matching_services[@]} == 0 )); then

            log_error \
                "GitHub Runner service was installed but could not be located."

            return "${STOLEUS_EXIT_VERIFICATION:-7}"
        fi


        if (( ${#matching_services[@]} > 1 )); then

            log_error \
                "Multiple GitHub Runner services matched runner name after installation: $runner_name"

            return "${STOLEUS_EXIT_CONFLICT:-8}"
        fi


        service_name="${matching_services[0]}"
    fi


    ensure_service_enabled_and_running "$service_name" >&2 ||
        return "${STOLEUS_EXIT_VERIFICATION:-7}"


    log_success \
        "GitHub Runner service is installed and running: $service_name" >&2


    printf '%s\n' "$service_name"

    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# github_runner_report_inactive_service
# ==============================================================================
#
# Purpose:
#     Inspect the latest Runner diagnostic log after the service exits.
#
# Detects known stale-registration and authentication failures and reports a
# clear error instead of only saying that the systemd service is inactive.
# ==============================================================================
github_runner_report_inactive_service() {

    local service_name="${1:-}"
    local installation_directory="${2:-}"

    local diagnostic_directory
    local latest_log=""
    local matching_error=""


    if [[ -z "$service_name" ]] ||
       [[ -z "$installation_directory" ]]; then

        log_error \
            "Runner failure diagnosis requires a service name and installation directory."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    diagnostic_directory="${installation_directory}/_diag"


    log_error \
        "GitHub Runner service stopped unexpectedly: $service_name"


    if [[ ! -d "$diagnostic_directory" ]]; then

        log_error \
            "GitHub Runner diagnostic directory does not exist: $diagnostic_directory"

        return "${STOLEUS_EXIT_VERIFICATION:-7}"
    fi


    # --------------------------------------------------------------------------
    # Select the newest Runner diagnostic file.
    #
    # sed reads the complete sorted output, avoiding grep/head SIGPIPE behavior
    # while pipefail is enabled.
    # --------------------------------------------------------------------------
    latest_log="$(
        find \
            "$diagnostic_directory" \
            -maxdepth 1 \
            -type f \
            -name 'Runner_*.log' \
            -printf '%T@ %p\n' 2>/dev/null |
            sort -nr |
            sed -n '1s/^[^ ]* //p'
    )"


    if [[ -z "$latest_log" ]] ||
       [[ ! -r "$latest_log" ]]; then

        log_error "No readable GitHub Runner diagnostic log was found."

        return "${STOLEUS_EXIT_VERIFICATION:-7}"
    fi


    if grep -Fq \
        "runner registration has been deleted from the server" \
        "$latest_log"; then

        matching_error="stale-registration"

    elif grep -Fq \
        "The token expired on" \
        "$latest_log"; then

        matching_error="expired-token"

    elif grep -Fq \
        "VssOAuthTokenRequestException" \
        "$latest_log"; then

        matching_error="oauth-authentication"

    else

        matching_error="unknown"
    fi


    case "$matching_error" in

        stale-registration)

            log_error \
                "GitHub no longer accepts the local Runner registration."

            log_error \
                "The local .runner and credential files are stale and the Runner must be registered again."

            ;;

        expired-token)

            log_error \
                "GitHub Runner session creation failed because an authentication token was considered expired."

            log_error \
                "Verify system time and re-register the Runner with a fresh registration token."

            ;;

        oauth-authentication)

            log_error \
                "GitHub Runner OAuth authentication failed."

            log_error \
                "The local Runner registration may be stale or invalid."

            ;;

        *)

            log_error \
                "The Runner stopped for an unrecognized reason."

            ;;
    esac


    log_error "Diagnostic log: $latest_log"

    return "${STOLEUS_EXIT_VERIFICATION:-7}"
}


# ==============================================================================
# github_runner_verify
# ==============================================================================
#
# Purpose:
#     Verify that the exact GitHub Runner service:
#
#         - exists;
#         - is enabled;
#         - is active;
#         - remains active for the verification period.
#
# A Runner can appear active briefly and then exit after GitHub rejects its
# registration. Therefore one immediate systemctl check is insufficient.
# ==============================================================================
github_runner_verify() {

    local service_name="${GITHUB_RUNNER_SERVICE_NAME:-}"
    local installation_directory="${GITHUB_RUNNER_INSTALLATION_DIRECTORY:-}"

    local verification_seconds=10
    local poll_interval_seconds=2
    local elapsed_seconds=0


    log_info "Verifying GitHub Runner installation."


    if [[ -z "$service_name" ]]; then

        log_error "GitHub Runner service name has not been resolved."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    if [[ -z "$installation_directory" ]]; then

        log_error \
            "GitHub Runner installation directory has not been resolved."

        return "${STOLEUS_EXIT_USAGE:-2}"
    fi


    require_command "systemctl" ||
        return "${STOLEUS_EXIT_DEPENDENCY:-3}"

    require_command "sleep" ||
        return "${STOLEUS_EXIT_DEPENDENCY:-3}"


    if ! systemctl cat "$service_name" >/dev/null 2>&1; then

        log_error "GitHub Runner service does not exist: $service_name"

        return "${STOLEUS_EXIT_VERIFICATION:-7}"
    fi


    if ! systemctl is-enabled --quiet "$service_name"; then

        log_error "GitHub Runner service is not enabled: $service_name"

        return "${STOLEUS_EXIT_VERIFICATION:-7}"
    fi


    log_info \
        "Confirming that the GitHub Runner remains active for ${verification_seconds}s."


    while (( elapsed_seconds < verification_seconds )); do

        if ! systemctl is-active --quiet "$service_name"; then

            github_runner_report_inactive_service \
                "$service_name" \
                "$installation_directory"

            return "${STOLEUS_EXIT_VERIFICATION:-7}"
        fi


        sleep "$poll_interval_seconds"

        elapsed_seconds=$(
            (elapsed_seconds + poll_interval_seconds)
        )
    done


    if ! systemctl is-active --quiet "$service_name"; then

        github_runner_report_inactive_service \
            "$service_name" \
            "$installation_directory"

        return "${STOLEUS_EXIT_VERIFICATION:-7}"
    fi


    log_success \
        "GitHub Runner installation verified; service remained active for ${verification_seconds}s: $service_name"

    return "${STOLEUS_EXIT_SUCCESS:-0}"
}


# ==============================================================================
# github_runner_setup
# ==============================================================================
#
# Purpose:
#     Execute the complete GitHub Actions Runner setup lifecycle.
#
# Version policy:
#
#     GITHUB_RUNNER_VERSION represents the minimum acceptable Runner version.
#
#     - Equal installed version:
#           Reuse it.
#
#     - Newer installed version:
#           Reuse it and update the active version state.
#
#     - Older installed version:
#           Stop with a clear version conflict.
#
#     - No installation:
#           Download and extract the requested version.
#
# Lifecycle:
#
#     1. Validate configuration and system time.
#     2. Detect architecture.
#     3. Resolve requested minimum Runner version.
#     4. Inspect any existing installation.
#     5. Download only when no acceptable installation exists.
#     6. Reuse or extract Runner files.
#     7. Reuse or create GitHub registration.
#     8. Reuse or install the systemd service.
#     9. Verify that the Runner remains active.
#    10. Print a final summary.
#
# Generated state:
#
#     GITHUB_RUNNER_ARCHITECTURE
#     GITHUB_RUNNER_VERSION
#     GITHUB_RUNNER_ARCHIVE_PATH
#     GITHUB_RUNNER_INSTALLATION_DIRECTORY
#     GITHUB_RUNNER_NAME
#     GITHUB_RUNNER_SERVICE_NAME
#
# Return codes:
#
#     0 = setup completed successfully
#     non-zero = one setup lifecycle phase failed
# ==============================================================================
github_runner_setup() {

    local installed_version_check_exit_code=0
    local conflict_exit_code="${STOLEUS_EXIT_CONFLICT:-8}"


    log_info "Starting GitHub Runner setup."


    # --------------------------------------------------------------------------
    # Validate:
    #
    #     - root permissions;
    #     - external system time;
    #     - repository URL;
    #     - Runner short name;
    #     - labels;
    #     - Linux Runner user.
    # --------------------------------------------------------------------------
    github_runner_validate || return $?


    # --------------------------------------------------------------------------
    # Resolve GitHub package architecture.
    #
    # Examples:
    #
    #     x86_64  -> x64
    #     aarch64 -> arm64
    # --------------------------------------------------------------------------
    GITHUB_RUNNER_ARCHITECTURE="$(
        github_runner_detect_architecture
    )" || return $?


    # --------------------------------------------------------------------------
    # Resolve the configured minimum Runner version.
    # --------------------------------------------------------------------------
    GITHUB_RUNNER_VERSION="$(
        github_runner_resolve_version
    )" || return $?


    # --------------------------------------------------------------------------
    # Resolve the deterministic installation directory before download so an
    # existing Runner installation can be inspected first.
    # --------------------------------------------------------------------------
    GITHUB_RUNNER_INSTALLATION_DIRECTORY="/opt/runners/${GITHUB_RUNNER_SHORT_NAME}"


    # --------------------------------------------------------------------------
    # Decide whether an archive download is required.
    #
    # Return values from github_runner_requested_version_is_installed():
    #
    #     0
    #         Equal or newer Runner version already installed.
    #
    #     1
    #         No valid existing Runner installation; download is required.
    #
    #     8
    #         Existing Runner is older than the requested minimum. Stop because
    #         automatic upgrades are not implemented.
    # --------------------------------------------------------------------------
    if github_runner_requested_version_is_installed; then

        GITHUB_RUNNER_ARCHIVE_PATH=""

    else

        installed_version_check_exit_code=$?


        if (( installed_version_check_exit_code == conflict_exit_code )); then

            return "$installed_version_check_exit_code"
        fi


        if (( installed_version_check_exit_code != ${STOLEUS_EXIT_FAILURE:-1} )); then

            return "$installed_version_check_exit_code"
        fi


        GITHUB_RUNNER_ARCHIVE_PATH="$(
            github_runner_download
        )" || return $?
    fi


    # --------------------------------------------------------------------------
    # Reuse the valid existing installation or extract the newly downloaded
    # archive.
    # --------------------------------------------------------------------------
    GITHUB_RUNNER_INSTALLATION_DIRECTORY="$(
        github_runner_extract
    )" || return $?


    # --------------------------------------------------------------------------
    # Reuse the existing local registration or register the Runner using a fresh
    # temporary token.
    # --------------------------------------------------------------------------
    GITHUB_RUNNER_NAME="$(
        github_runner_configure
    )" || return $?


    # --------------------------------------------------------------------------
    # Reuse or install the exact systemd service for this Runner.
    # --------------------------------------------------------------------------
    GITHUB_RUNNER_SERVICE_NAME="$(
        github_runner_install_service
    )" || return $?


    # --------------------------------------------------------------------------
    # Confirm that the exact service exists, is enabled, is active, and remains
    # active throughout the verification period.
    # --------------------------------------------------------------------------
    github_runner_verify || return $?


    # --------------------------------------------------------------------------
    # Final setup summary.
    # --------------------------------------------------------------------------
    log_info \
        "Selected GitHub Runner architecture: $GITHUB_RUNNER_ARCHITECTURE"

    log_info \
        "Active GitHub Runner version: $GITHUB_RUNNER_VERSION"


    if [[ -n "$GITHUB_RUNNER_ARCHIVE_PATH" ]]; then

        log_info \
            "Downloaded GitHub Runner archive: $GITHUB_RUNNER_ARCHIVE_PATH"

    else

        log_info \
            "GitHub Runner archive download skipped because version ${GITHUB_RUNNER_VERSION} is already installed."
    fi


    log_info \
        "GitHub Runner installation directory: $GITHUB_RUNNER_INSTALLATION_DIRECTORY"

    log_info \
        "Registered GitHub Runner name: $GITHUB_RUNNER_NAME"

    log_info \
        "GitHub Runner service: $GITHUB_RUNNER_SERVICE_NAME"


    log_success \
        "GitHub Runner setup completed successfully."

    return "${STOLEUS_EXIT_SUCCESS:-0}"
}



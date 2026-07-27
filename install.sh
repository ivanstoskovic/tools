#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Installer
# ==============================================================================
#
# Purpose:
#     Install the Stoleus Tools project into a standard Linux system location.
#
# After installation:
#
#     Project files:
#
#         /opt/stoleus-tools
#
#     Global command:
#
#         /usr/local/bin/stoleus
#
# This allows the user to run:
#
#     stoleus health
#
# instead of:
#
#     ./bin/stoleus health
#
# ==============================================================================


# ------------------------------------------------------------------------------
# Enable strict Bash behavior.
#
# -E
#     Preserve ERR traps inside functions and subshells.
#
# -e
#     Stop when an unexpected command fails.
#
# -u
#     Treat undefined variables as errors.
#
# -o pipefail
#     Make pipelines fail if an important command inside them fails.
# ------------------------------------------------------------------------------
set -Eeuo pipefail


# ==============================================================================
# Installation paths
# ==============================================================================

# ------------------------------------------------------------------------------
# Determine where THIS install.sh file lives.
#
# Example:
#
#     /home/deployer/tools/install.sh
#
# becomes:
#
#     /home/deployer/tools
#
# This is the source repository we are installing from.
# ------------------------------------------------------------------------------
readonly SOURCE_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
    pwd
)"


# ------------------------------------------------------------------------------
# Main installation directory.
#
# `/opt`
#     Is commonly used for optional/add-on application software installed by
#     the administrator.
#
# Our toolkit will live here:
#
#     /opt/stoleus-tools
# ------------------------------------------------------------------------------
readonly INSTALL_DIR="/opt/stoleus-tools"


# ------------------------------------------------------------------------------
# Global command location.
#
# `/usr/local/bin`
#     Is conventionally used for administrator-installed executable commands.
#
# It is normally already included in the shell PATH.
#
# We will create:
#
#     /usr/local/bin/stoleus
#
# as a symbolic link to:
#
#     /opt/stoleus-tools/bin/stoleus
# ------------------------------------------------------------------------------
readonly COMMAND_LINK="/usr/local/bin/stoleus"


# ==============================================================================
# Root privilege check
# ==============================================================================
#
# Installing under:
#
#     /opt
#
# and:
#
#     /usr/local/bin
#
# requires root privileges.
#
# `$EUID`
#     Contains the effective user ID.
#
# Root always has UID:
#
#     0
#
# Therefore:
#
#     EUID != 0
#
# means the installer was not started as root.
# ==============================================================================
if [[ "$EUID" -ne 0 ]]; then

    echo "ERROR: This installer must be run as root." >&2
    echo
    echo "Run:" >&2
    echo "    sudo ./install.sh" >&2

    exit 1
fi


# ==============================================================================
# Validate source project
# ==============================================================================

# ------------------------------------------------------------------------------
# Before modifying the machine, verify that the expected Stoleus entry point
# exists in the repository.
# ------------------------------------------------------------------------------
if [[ ! -f "${SOURCE_DIR}/bin/stoleus" ]]; then

    echo "ERROR: bin/stoleus was not found." >&2
    echo "Run install.sh from the root of the tools repository." >&2

    exit 1
fi


# ==============================================================================
# Install project files
# ==============================================================================

echo "Installing Stoleus Tools..."
echo


# ------------------------------------------------------------------------------
# Remove an existing installation.
#
# `rm -rf`
#
#     -r
#         Remove directories recursively.
#
#     -f
#         Do not prompt for confirmation.
#
# This makes installation repeatable:
#
#     sudo ./install.sh
#
# can be executed again when upgrading the toolkit.
#
# IMPORTANT:
# INSTALL_DIR is a readonly constant defined above, which reduces the risk of
# accidentally deleting an unexpected path.
# ------------------------------------------------------------------------------
if [[ -d "$INSTALL_DIR" ]]; then

    echo "Removing previous installation: $INSTALL_DIR"

    rm -rf "$INSTALL_DIR"
fi


# ------------------------------------------------------------------------------
# Create the installation directory.
#
# `mkdir -p`
#
#     Creates the directory and any missing parent directories.
#
#     It is safe even if the parent already exists.
# ------------------------------------------------------------------------------
mkdir -p "$INSTALL_DIR"


# ------------------------------------------------------------------------------
# Copy the repository into the installation directory.
#
# `cp -a`
#
#     -a = archive mode
#
# It preserves:
#
#     - directory structure
#     - timestamps
#     - permissions where supported
#     - symbolic links
#
# `${SOURCE_DIR}/.`
#
# The trailing `/.` means:
#
#     copy the CONTENTS of SOURCE_DIR
#
# rather than creating:
#
#     /opt/stoleus-tools/tools
# ------------------------------------------------------------------------------
cp -a "${SOURCE_DIR}/." "$INSTALL_DIR/"


# ==============================================================================
# Set executable permissions
# ==============================================================================

# ------------------------------------------------------------------------------
# The public CLI entry point must be executable.
#
# chmod 0755 means:
#
#     owner  = read + write + execute
#     group  = read + execute
#     others = read + execute
#
# Numeric permissions:
#
#     7 = 4(read) + 2(write) + 1(execute)
#     5 = 4(read) + 1(execute)
# ------------------------------------------------------------------------------
chmod 0755 "${INSTALL_DIR}/bin/stoleus"


# ------------------------------------------------------------------------------
# The installer and uninstaller should also be executable.
#
# We check whether uninstall.sh exists before changing its permissions.
# ------------------------------------------------------------------------------
chmod 0755 "${INSTALL_DIR}/install.sh"

if [[ -f "${INSTALL_DIR}/uninstall.sh" ]]; then
    chmod 0755 "${INSTALL_DIR}/uninstall.sh"
fi


# ------------------------------------------------------------------------------
# Command and library .sh files are sourced rather than directly executed,
# so they technically do not require executable permission.
#
# We deliberately leave their normal file permissions unchanged.
# ------------------------------------------------------------------------------


# ==============================================================================
# Create global `stoleus` command
# ==============================================================================

# ------------------------------------------------------------------------------
# `ln`
#     Creates links between files.
#
# `-s`
#     Creates a symbolic link rather than a hard link.
#
# `-f`
#     Replaces an existing destination.
#
# `-n`
#     Treats an existing symbolic-link destination as a link rather than
#     following it.
#
# We create:
#
#     /usr/local/bin/stoleus
#
# pointing to:
#
#     /opt/stoleus-tools/bin/stoleus
#
# Mental model:
#
#     /usr/local/bin/stoleus
#              |
#              v
#     /opt/stoleus-tools/bin/stoleus
#
# Since `/usr/local/bin` is normally in PATH, Bash can find the command from
# anywhere.
# ------------------------------------------------------------------------------
ln -sfn \
    "${INSTALL_DIR}/bin/stoleus" \
    "$COMMAND_LINK"


# ==============================================================================
# Verification
# ==============================================================================

# ------------------------------------------------------------------------------
# Verify that the symbolic link exists.
#
# `-L`
#     Tests whether the specified path is a symbolic link.
# ------------------------------------------------------------------------------
if [[ ! -L "$COMMAND_LINK" ]]; then

    echo "ERROR: Failed to create $COMMAND_LINK" >&2

    exit 1
fi


# ------------------------------------------------------------------------------
# Run a simple command from the installed copy.
#
# We call the installed binary directly here instead of relying on PATH.
# ------------------------------------------------------------------------------
if ! "${INSTALL_DIR}/bin/stoleus" version >/dev/null 2>&1; then

    echo "ERROR: Installed Stoleus command failed verification." >&2

    exit 1
fi


# ==============================================================================
# Installation complete
# ==============================================================================

echo
echo "Stoleus Tools installed successfully."
echo
echo "Installation directory:"
echo "    $INSTALL_DIR"
echo
echo "Global command:"
echo "    $COMMAND_LINK"
echo
echo "Try:"
echo "    stoleus version"
echo "    sudo stoleus health"
#!/usr/bin/env bash

# ------------------------------------------------------------------------------
# Enable strict Bash behavior.
# ------------------------------------------------------------------------------
set -Eeuo pipefail

# ==============================================================================
# Stoleus Tools - Setup Module Loader
# ==============================================================================
#
# This file loads all setup modules in dependency order.
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
source "${PROJECT_ROOT}/lib/setup/common.sh"
source "${PROJECT_ROOT}/lib/setup/chrony.sh"
source "${PROJECT_ROOT}/lib/setup/firewall.sh"
source "${PROJECT_ROOT}/lib/setup/docker.sh"
source "${PROJECT_ROOT}/lib/setup/directories.sh"
source "${PROJECT_ROOT}/lib/setup/profiles.sh"







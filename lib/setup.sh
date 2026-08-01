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
# ==============================================================================
# Stoleus Tools - Component Loader
# ==============================================================================
#
# This compatibility loader loads all infrastructure components in dependency
# order.
#
# commands/setup.sh still loads:
#
#     lib/setup.sh
#
# This allows us to rename the implementation directory without changing the
# command layer immediately.
# ==============================================================================
source "${PROJECT_ROOT}/lib/components/common.sh"
source "${PROJECT_ROOT}/lib/components/chrony.sh"
source "${PROJECT_ROOT}/lib/components/firewall.sh"
source "${PROJECT_ROOT}/lib/components/docker.sh"
source "${PROJECT_ROOT}/lib/components/directories.sh"
source "${PROJECT_ROOT}/lib/components/profiles.sh"







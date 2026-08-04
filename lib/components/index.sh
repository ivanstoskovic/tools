#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Component Module
# ==============================================================================
#
# Purpose:
#     Load component infrastructure, component implementations, component
#     manifests, and verify the complete registry.
#
# Loading order:
#
#     shared component helpers
#         ↓
#     registry implementation
#         ↓
#     component implementations
#         ↓
#     manifests
#         ↓
#     registry verification
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Shared Component Infrastructure
# ==============================================================================

source "${PROJECT_ROOT}/lib/components/common.sh"
source "${PROJECT_ROOT}/lib/components/registry.sh"


# ==============================================================================
# Component Implementations
# ==============================================================================

source "${PROJECT_ROOT}/lib/components/chrony.sh"
source "${PROJECT_ROOT}/lib/components/firewall.sh"
source "${PROJECT_ROOT}/lib/components/docker.sh"
source "${PROJECT_ROOT}/lib/components/directories.sh"
source "${PROJECT_ROOT}/lib/components/github_runner.sh"
source "${PROJECT_ROOT}/lib/components/profiles.sh"


# ==============================================================================
# Component Manifests
# ==============================================================================

source "${PROJECT_ROOT}/lib/components/manifests/chrony.sh"
source "${PROJECT_ROOT}/lib/components/manifests/firewall.sh"
source "${PROJECT_ROOT}/lib/components/manifests/docker.sh"
source "${PROJECT_ROOT}/lib/components/manifests/directories.sh"
source "${PROJECT_ROOT}/lib/components/manifests/github_runner.sh"
source "${PROJECT_ROOT}/lib/components/manifests/server.sh"


# ==============================================================================
# Registry Verification
# ==============================================================================

component_verify_registry
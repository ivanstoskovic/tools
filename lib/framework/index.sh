#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Framework Public API
# ==============================================================================
#
# Purpose:
#     Load every framework public-API declaration and verify that all declared
#     functions exist.
#
# Loading order:
#
#     1. API registry implementation
#     2. Module API declarations
#     3. API contract verification
#
# Requirement:
#     Text, filesystem, OS, and process implementation modules must already be
#     loaded before this file is sourced.
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# API Registry
# ==============================================================================

source "${PROJECT_ROOT}/lib/framework/api.sh"


# ==============================================================================
# Public Module Contracts
# ==============================================================================

source "${PROJECT_ROOT}/lib/framework/text.sh"
source "${PROJECT_ROOT}/lib/framework/filesystem.sh"
source "${PROJECT_ROOT}/lib/framework/os.sh"
source "${PROJECT_ROOT}/lib/framework/process.sh"


# ==============================================================================
# Contract Verification
# ==============================================================================

framework_verify_api
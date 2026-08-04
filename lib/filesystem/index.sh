#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Filesystem Module
# ==============================================================================
#
# Purpose:
#     Load filesystem-related framework capabilities.
#
# Dependency order:
#
#     checksums
#     directories
#     backups
#     files
#     binary
# ==============================================================================

set -Eeuo pipefail


source "${PROJECT_ROOT}/lib/filesystem/checksums.sh"
source "${PROJECT_ROOT}/lib/filesystem/directories.sh"
source "${PROJECT_ROOT}/lib/filesystem/backups.sh"
source "${PROJECT_ROOT}/lib/filesystem/files.sh"
source "${PROJECT_ROOT}/lib/filesystem/binary.sh"
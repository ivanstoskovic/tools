#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Operating-System Module
# ==============================================================================
#
# Purpose:
#     Load operating-system integration helpers.
# ==============================================================================

set -Eeuo pipefail


source "${PROJECT_ROOT}/lib/os/downloads.sh"
source "${PROJECT_ROOT}/lib/os/archives.sh"
source "${PROJECT_ROOT}/lib/os/time.sh"
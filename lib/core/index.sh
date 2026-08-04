#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Core Module
# ==============================================================================
#
# Purpose:
#     Load core application services.
#
# Core services currently include:
#
#     - version access;
#     - command dispatching.
# ==============================================================================

set -Eeuo pipefail


source "${PROJECT_ROOT}/lib/core/version.sh"
source "${PROJECT_ROOT}/lib/core/dispatcher.sh"
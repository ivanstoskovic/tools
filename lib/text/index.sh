#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Text Module
# ==============================================================================
#
# Purpose:
#     Load all text-related framework capabilities in dependency order.
#
# Dependency order:
#
#     secrets
#         ↓
#     logging
#         ↓
#     normalization
#         ↓
#     encoding
#         ↓
#     output
# ==============================================================================

set -Eeuo pipefail


source "${PROJECT_ROOT}/lib/text/secrets.sh"
source "${PROJECT_ROOT}/lib/text/logging.sh"
source "${PROJECT_ROOT}/lib/text/normalization.sh"
source "${PROJECT_ROOT}/lib/text/encoding.sh"
source "${PROJECT_ROOT}/lib/text/output.sh"
#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Public Operating-System API
# ==============================================================================
#
# Purpose:
#     Declare the supported public API of the Operating-System module.
# ==============================================================================
set -Eeuo pipefail


framework_register_api \
    "os" \
    download_file \
    extract_tar_gz \
    verify_remote_clock_skew
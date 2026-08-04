#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Public Process API
# ==============================================================================
#
# Purpose:
#     Declare the supported public API of the Process module.
# ==============================================================================
set -Eeuo pipefail


framework_register_api \
    "process" \
    print_step_failure \
    print_step_success \
    run_with_log_context
#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Public Text API
# ==============================================================================
#
# Purpose:
#     Declare the supported public API of the Text module.
#
# Functions not listed here should be treated as implementation details, even
# though Bash technically places all loaded functions in the global namespace.
# ==============================================================================
set -Eeuo pipefail


framework_register_api \
    "text" \
    log_debug \
    log_info \
    log_success \
    log_warning \
    log_error \
    set_log_context \
    clear_log_context \
    register_secret \
    unregister_secret \
    clear_registered_secrets \
    redact_secret \
    redact_text \
    normalize_line_endings \
    strip_trailing_whitespace \
    validate_utf8 \
    write_text
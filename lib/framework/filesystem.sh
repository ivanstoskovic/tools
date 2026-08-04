#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Public Filesystem API
# ==============================================================================
#
# Purpose:
#     Declare the supported public API of the Filesystem module.
# ==============================================================================
set -Eeuo pipefail


framework_register_api \
    "filesystem" \
    append_file \
    backup_file \
    create_directory \
    remove_directory \
    replace_line \
    restore_file \
    verify_sha256 \
    write_binary_file \
    write_binary_stream \
    write_file
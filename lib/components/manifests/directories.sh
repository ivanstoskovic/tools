#!/usr/bin/env bash

set -Eeuo pipefail


component_register \
    "directories" \
    "setup_application_directories" \
    "Create the standard application directories" \
    "lib/components/directories.sh" \
    "text,filesystem,process" \
    ""
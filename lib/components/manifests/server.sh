#!/usr/bin/env bash

set -Eeuo pipefail


component_register \
    "server" \
    "setup_server_profile" \
    "Configure a complete server profile" \
    "lib/components/profiles.sh" \
    "text,process" \
    "chrony,firewall,docker,directories" \
    "validate_server_profile"
#!/usr/bin/env bash

set -Eeuo pipefail


component_register \
    "firewall" \
    "setup_firewall" \
    "Install and configure the UFW firewall" \
    "lib/components/firewall.sh" \
    "text,process" \
    ""
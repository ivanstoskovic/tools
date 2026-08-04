#!/usr/bin/env bash

set -Eeuo pipefail


component_register \
    "chrony" \
    "setup_chrony" \
    "Install, enable, and verify Chrony" \
    "lib/components/chrony.sh" \
    "text,os,process" \
    ""
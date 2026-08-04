#!/usr/bin/env bash

set -Eeuo pipefail


component_register \
    "docker" \
    "setup_docker" \
    "Install Docker Engine, Buildx, and Docker Compose" \
    "lib/components/docker.sh" \
    "text,filesystem,os,process" \
    ""
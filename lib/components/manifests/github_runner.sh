#!/usr/bin/env bash

set -Eeuo pipefail


component_register \
    "github-runner" \
    "github_runner_setup" \
    "Install and configure a GitHub Actions runner" \
    "lib/components/github_runner.sh" \
    "text,filesystem,os,process" \
    ""
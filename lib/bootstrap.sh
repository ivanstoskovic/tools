#!/usr/bin/env bash

# ==============================================================================
# Stoleus Tools - Framework Bootstrap
# ==============================================================================
#
# Purpose:
#     Initialize the Stoleus framework and load all required modules.
#
# Responsibilities:
#
#     - enable strict Bash behavior;
#     - verify that PROJECT_ROOT exists;
#     - load standardized exit codes;
#     - load text modules;
#     - load operating-system modules;
#     - load filesystem modules;
#     - load process modules;
#     - load the current core compatibility layer.
#
# This file must not contain component setup logic.
#
# It prepares the framework so command dispatching and components can execute.
# ==============================================================================

set -Eeuo pipefail


# ==============================================================================
# Bootstrap Guard
# ==============================================================================
#
# Prevent the framework from being loaded more than once in the same Bash
# process.
#
# `${STOLEUS_BOOTSTRAPPED:-false}`
#     Uses the current value if it exists.
#     Otherwise uses "false".
# ==============================================================================
if [[ "${STOLEUS_BOOTSTRAPPED:-false}" == "true" ]]; then

    return 0
fi


readonly STOLEUS_BOOTSTRAPPED="true"


# ==============================================================================
# Bootstrap Validation
# ==============================================================================

if [[ -z "${PROJECT_ROOT:-}" ]]; then

    printf '%s\n' \
        "ERROR: PROJECT_ROOT must be defined before loading Stoleus." >&2

    return 1
fi


if [[ ! -d "$PROJECT_ROOT" ]]; then

    printf '%s\n' \
        "ERROR: PROJECT_ROOT does not exist: $PROJECT_ROOT" >&2

    return 1
fi


# ==============================================================================
# Framework Constants
# ==============================================================================

readonly STOLEUS_COMMANDS_DIR="${PROJECT_ROOT}/commands"
readonly STOLEUS_VERSION_FILE="${PROJECT_ROOT}/VERSION"


# ==============================================================================
# Exit Codes
# ==============================================================================

source "${PROJECT_ROOT}/lib/exit_codes.sh"


# ==============================================================================
# Framework Modules
# ==============================================================================

source "${PROJECT_ROOT}/lib/text/index.sh"
source "${PROJECT_ROOT}/lib/os/index.sh"
source "${PROJECT_ROOT}/lib/filesystem/index.sh"
source "${PROJECT_ROOT}/lib/process/index.sh"

# ------------------------------------------------------------------------------
# Load the generic pipeline execution engine.
#
# The pipeline library is used by workflows that execute named steps in order,
# including:
#
#     - server setup
#     - deployments
#     - backups
#     - restores
#     - repair operations
#
# Loading it here makes pipeline functions available to every Stoleus command.
# ------------------------------------------------------------------------------
source "${PROJECT_ROOT}/lib/pipeline.sh"


# ==============================================================================
# Framework Public API
# ==============================================================================
#
# Implementation modules have already been loaded.
#
# The framework module now registers and verifies the supported public API.
# ==============================================================================
source "${PROJECT_ROOT}/lib/framework/index.sh"

# ==============================================================================
# Core Compatibility Layer
# ==============================================================================
#
# common.sh currently still contains:
#
#     run_command()
#     read_version()
#
# During the next Architecture 2.0 phase, these functions will move to:
#
#     lib/core/dispatcher.sh
#     lib/core/version.sh
#
# common.sh must not load bootstrap.sh yet, otherwise a circular dependency
# would be created.
# ==============================================================================

# ==============================================================================
# Core
# ==============================================================================

source "${PROJECT_ROOT}/lib/core/index.sh"
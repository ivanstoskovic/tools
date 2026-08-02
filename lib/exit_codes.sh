#!/usr/bin/env bash

set -Eeuo pipefail

# ==============================================================================
# Stoleus Exit Codes
# ==============================================================================
#
# Purpose:
#     Define standardized process and function exit codes used across Stoleus.
#
# Convention:
#
#     0 = success
#     non-zero = failure
#
# These constants make return values easier to understand than unnamed numbers
# such as:
#
#     return 4
#
# Prefer:
#
#     return "$STOLEUS_EXIT_NETWORK"
# ==============================================================================


# ------------------------------------------------------------------------------
# Operation completed successfully.
# ------------------------------------------------------------------------------
readonly STOLEUS_EXIT_SUCCESS=0


# ------------------------------------------------------------------------------
# General failure that does not fit a more specific category.
# ------------------------------------------------------------------------------
readonly STOLEUS_EXIT_FAILURE=1


# ------------------------------------------------------------------------------
# Invalid command usage, missing arguments, or invalid options.
# ------------------------------------------------------------------------------
readonly STOLEUS_EXIT_USAGE=2


# ------------------------------------------------------------------------------
# Required command, package, service, or dependency is unavailable.
# ------------------------------------------------------------------------------
readonly STOLEUS_EXIT_DEPENDENCY=3


# ------------------------------------------------------------------------------
# Network request, repository access, or download failed.
# ------------------------------------------------------------------------------
readonly STOLEUS_EXIT_NETWORK=4


# ------------------------------------------------------------------------------
# Required permissions are missing.
# ------------------------------------------------------------------------------
readonly STOLEUS_EXIT_PERMISSION=5


# ------------------------------------------------------------------------------
# Invalid or unsupported configuration.
# ------------------------------------------------------------------------------
readonly STOLEUS_EXIT_CONFIGURATION=6


# ------------------------------------------------------------------------------
# Installation or configuration completed, but verification failed.
# ------------------------------------------------------------------------------
readonly STOLEUS_EXIT_VERIFICATION=7


# ------------------------------------------------------------------------------
# Existing state conflicts with the requested operation.
# ------------------------------------------------------------------------------
readonly STOLEUS_EXIT_CONFLICT=8
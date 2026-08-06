#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Capability Definition Tests
# ==============================================================================

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

source "${PROJECT_ROOT}/kernel/kernel.sh"


fail() {

    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}


assert_equals() {

    local expected="${1:-}"
    local actual="${2:-}"
    local message="${3:-Values are not equal.}"


    if [[ "$expected" != "$actual" ]]; then

        printf 'FAIL: %s\n' "$message" >&2
        printf 'Expected: %s\n' "$expected" >&2
        printf 'Actual:   %s\n' "$actual" >&2

        exit 1
    fi
}


stoleus_kernel_initialize
stoleus_definition_reset
stoleus_manifest_bash_reset


# ==============================================================================
# Explicit capability DSL.
# ==============================================================================

stoleus_plugin_begin \
    "chrony"

stoleus_plugin_description \
    "Chrony time synchronization provider."

stoleus_plugin_implementation \
    "implementation.sh"

stoleus_plugin_requires_capabilities \
    "package-management" \
    "service-management"

stoleus_plugin_provides_capabilities \
    "time-sync"

stoleus_plugin_lifecycle \
    "verify" \
    "chrony_verify"

stoleus_plugin_end


assert_equals \
    "package-management,service-management" \
    "$STOLEUS_MANIFEST_CAPABILITIES" \
    "Required capability normalization is incorrect."


assert_equals \
    "time-sync" \
    "$STOLEUS_MANIFEST_PROVIDED_CAPABILITIES" \
    "Provided capability normalization is incorrect."


# ==============================================================================
# Legacy DSL remains a required-capability alias.
# ==============================================================================

stoleus_manifest_bash_reset

stoleus_plugin_begin \
    "legacy-consumer"

stoleus_plugin_capabilities \
    "remote-shell" \
    "firewall"

stoleus_plugin_lifecycle \
    "verify" \
    "legacy_verify"

stoleus_plugin_end


assert_equals \
    "remote-shell,firewall" \
    "$STOLEUS_MANIFEST_CAPABILITIES" \
    "Legacy capability DSL should declare required capabilities."


# ==============================================================================
# Duplicate required capability declarations are rejected.
# ==============================================================================

stoleus_manifest_bash_reset
stoleus_plugin_begin "duplicate-required"


set +e

stoleus_plugin_requires_capabilities \
    "time-sync" \
    "time-sync" \
    >/dev/null 2>&1

duplicate_required_exit_code=$?

set -e


assert_equals \
    "8" \
    "$duplicate_required_exit_code" \
    "Duplicate required capability should return conflict code 8."


# ==============================================================================
# Duplicate provided capability declarations are rejected.
# ==============================================================================

stoleus_manifest_bash_reset
stoleus_plugin_begin "duplicate-provider"


set +e

stoleus_plugin_provides_capabilities \
    "time-sync" \
    "time-sync" \
    >/dev/null 2>&1

duplicate_provided_exit_code=$?

set -e


assert_equals \
    "8" \
    "$duplicate_provided_exit_code" \
    "Duplicate provided capability should return conflict code 8."


# ==============================================================================
# Invalid capability identifiers are rejected.
# ==============================================================================

stoleus_manifest_bash_reset
stoleus_plugin_begin "invalid-capability"


set +e

stoleus_plugin_provides_capabilities \
    "Time Sync" \
    >/dev/null 2>&1

invalid_capability_exit_code=$?

set -e


assert_equals \
    "6" \
    "$invalid_capability_exit_code" \
    "Invalid capability ID should return configuration code 6."


printf '%s\n' \
    "PASS: Capability Definition tests completed successfully."

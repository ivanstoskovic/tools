#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Capability Provider Override Tests
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


capability_id="package-management"


# ==============================================================================
# No override initially.
# ==============================================================================

assert_equals \
    "" \
    "$(stoleus_context_get_capability_provider_override "$capability_id")" \
    "Capability provider override should initially be empty."


# ==============================================================================
# Set and get.
# ==============================================================================

generation_before="$(
    stoleus_context_get_generation
)"


stoleus_context_set_capability_provider_override \
    "$capability_id" \
    "apt-provider"


assert_equals \
    "apt-provider" \
    "$(stoleus_context_get_capability_provider_override "$capability_id")" \
    "Capability provider override lookup is incorrect."


generation_after="$(
    stoleus_context_get_generation
)"


if (( generation_after <= generation_before )); then
    fail "Setting a capability provider override should increment Context generation."
fi


# ==============================================================================
# Idempotent set does not change generation.
# ==============================================================================

generation_before="$generation_after"


stoleus_context_set_capability_provider_override \
    "$capability_id" \
    "apt-provider"


generation_after="$(
    stoleus_context_get_generation
)"


assert_equals \
    "$generation_before" \
    "$generation_after" \
    "Idempotent capability override should not change Context generation."


# ==============================================================================
# Listing.
# ==============================================================================

assert_equals \
    $'package-management\tapt-provider' \
    "$(stoleus_context_list_capability_provider_overrides)" \
    "Capability provider override listing is incorrect."


# ==============================================================================
# Clear.
# ==============================================================================

stoleus_context_clear_capability_provider_override \
    "$capability_id"


assert_equals \
    "" \
    "$(stoleus_context_get_capability_provider_override "$capability_id")" \
    "Capability provider override was not cleared."


# ==============================================================================
# Invalid identifiers.
# ==============================================================================

set +e

stoleus_context_set_capability_provider_override \
    "INVALID CAPABILITY" \
    "apt-provider" \
    >/dev/null 2>&1

invalid_capability_exit_code=$?

set -e


assert_equals \
    "6" \
    "$invalid_capability_exit_code" \
    "Invalid capability override identifier should return code 6."


set +e

stoleus_context_set_capability_provider_override \
    "$capability_id" \
    "INVALID PROVIDER" \
    >/dev/null 2>&1

invalid_provider_exit_code=$?

set -e


assert_equals \
    "6" \
    "$invalid_provider_exit_code" \
    "Invalid provider override identifier should return code 6."


printf '%s\n' \
    "PASS: Capability Provider Override tests completed successfully."

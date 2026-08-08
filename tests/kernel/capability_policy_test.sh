#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Capability Provider Policy Tests
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


assert_equals \
    "true" \
    "${STOLEUS_CAPABILITY_POLICY_INITIALIZED:-false}" \
    "Capability Policy should be initialized."


# ==============================================================================
# One candidate is selected.
# ==============================================================================

assert_equals \
    "apt-provider" \
    "$(
        stoleus_capability_policy_select \
            "package-management" \
            "" \
            "apt-provider"
    )" \
    "Single capability provider was not selected."


# ==============================================================================
# No candidates fail with not-found code.
# ==============================================================================

set +e

stoleus_capability_policy_select \
    "package-management" \
    "" \
    >/dev/null 2>&1

no_candidate_exit_code=$?

set -e


assert_equals \
    "6" \
    "$no_candidate_exit_code" \
    "Missing capability providers should return code 6."


# ==============================================================================
# Multiple providers remain a conflict without another policy.
# ==============================================================================

set +e

stoleus_capability_policy_select \
    "package-management" \
    "" \
    "apt-provider" \
    "dnf-provider" \
    >/dev/null 2>&1

multiple_provider_exit_code=$?

set -e


assert_equals \
    "8" \
    "$multiple_provider_exit_code" \
    "Unresolved multiple capability providers should return code 8."


# ==============================================================================
# Explicit override resolves a multi-provider conflict.
# ==============================================================================

assert_equals \
    "dnf-provider" \
    "$(
        stoleus_capability_policy_select \
            "package-management" \
            "dnf-provider" \
            "apt-provider" \
            "dnf-provider"
    )" \
    "Explicit capability provider override was not selected."


# ==============================================================================
# Override must reference one of the supplied candidates.
# ==============================================================================

set +e

stoleus_capability_policy_select \
    "package-management" \
    "apk-provider" \
    "apt-provider" \
    "dnf-provider" \
    >/dev/null 2>&1

unknown_override_exit_code=$?

set -e


assert_equals \
    "6" \
    "$unknown_override_exit_code" \
    "Unknown capability provider override should return code 6."


# ==============================================================================
# Duplicate candidates are rejected.
# ==============================================================================

set +e

stoleus_capability_policy_select \
    "package-management" \
    "" \
    "apt-provider" \
    "apt-provider" \
    >/dev/null 2>&1

duplicate_candidate_exit_code=$?

set -e


assert_equals \
    "8" \
    "$duplicate_candidate_exit_code" \
    "Duplicate capability provider candidates should return code 8."


# ==============================================================================
# Invalid identifiers are rejected.
# ==============================================================================

set +e

stoleus_capability_policy_select \
    "INVALID CAPABILITY" \
    "" \
    "apt-provider" \
    >/dev/null 2>&1

invalid_capability_exit_code=$?

set -e


assert_equals \
    "2" \
    "$invalid_capability_exit_code" \
    "Invalid capability identifier should return code 2."


set +e

stoleus_capability_policy_select \
    "package-management" \
    "INVALID PROVIDER" \
    "apt-provider" \
    >/dev/null 2>&1

invalid_override_exit_code=$?

set -e


assert_equals \
    "2" \
    "$invalid_override_exit_code" \
    "Invalid provider override identifier should return code 2."



# ==============================================================================
# Capability Policy delegates generic priority selection.
# ==============================================================================

stoleus_provider_policy_registry_register \
    "capability" \
    "archive-management" \
    "tar-provider" \
    "50" \
    "true"


stoleus_provider_policy_registry_register \
    "capability" \
    "archive-management" \
    "zip-provider" \
    "100" \
    "true"


assert_equals \
    "zip-provider" \
    "$(
        stoleus_capability_policy_select \
            "archive-management" \
            "" \
            "tar-provider" \
            "zip-provider"
    )" \
    "Capability Policy did not delegate priority selection correctly."


# ==============================================================================
# Disabled capability provider is excluded.
# ==============================================================================

stoleus_provider_policy_registry_register \
    "capability" \
    "process-management" \
    "disabled-provider" \
    "1000" \
    "false"


stoleus_provider_policy_registry_register \
    "capability" \
    "process-management" \
    "enabled-provider" \
    "10" \
    "true"


assert_equals \
    "enabled-provider" \
    "$(
        stoleus_capability_policy_select \
            "process-management" \
            "" \
            "disabled-provider" \
            "enabled-provider"
    )" \
    "Capability Policy selected a disabled provider."


# ==============================================================================
# Equal highest policy priority remains a conflict.
# ==============================================================================

stoleus_provider_policy_registry_register \
    "capability" \
    "network-management" \
    "network-provider-a" \
    "100" \
    "true"


stoleus_provider_policy_registry_register \
    "capability" \
    "network-management" \
    "network-provider-b" \
    "100" \
    "true"


set +e

stoleus_capability_policy_select \
    "network-management" \
    "" \
    "network-provider-a" \
    "network-provider-b" \
    >/dev/null 2>&1

priority_tie_exit_code=$?

set -e


assert_equals \
    "8" \
    "$priority_tie_exit_code" \
    "Capability Policy priority tie should return code 8."



# ==============================================================================
# Capability Policy delegates Context condition filtering.
# ==============================================================================

stoleus_context_set \
    "os-family" \
    "debian"


stoleus_provider_policy_registry_register \
    "capability" \
    "conditional-capability" \
    "debian-provider" \
    "10" \
    "true" \
    "os-family=debian"


stoleus_provider_policy_registry_register \
    "capability" \
    "conditional-capability" \
    "redhat-provider" \
    "1000" \
    "true" \
    "os-family=redhat"


assert_equals \
    "debian-provider" \
    "$(
        stoleus_capability_policy_select \
            "conditional-capability" \
            "" \
            "debian-provider" \
            "redhat-provider"
    )" \
    "Capability Policy did not delegate Context condition filtering."


printf '%s\n' \
    "PASS: Capability Provider Policy tests completed successfully."

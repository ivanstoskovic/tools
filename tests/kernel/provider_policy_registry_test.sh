#!/usr/bin/env bash

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
    "${STOLEUS_PROVIDER_POLICY_REGISTRY_INITIALIZED:-false}" \
    "Provider Policy Registry should be initialized."


assert_equals \
    "0" \
    "$(stoleus_provider_policy_registry_get_count)" \
    "Provider Policy Registry should initially be empty."


stoleus_provider_policy_registry_register \
    "capability" \
    "package-management" \
    "apt-provider" \
    "100" \
    "true" \
    "os-family=debian" \
    "package,linux"


assert_equals \
    "1" \
    "$(stoleus_provider_policy_registry_get_count)" \
    "Provider Policy Registry count is incorrect."


policy_key="capability:package-management@apt-provider"


assert_equals \
    "100" \
    "$(stoleus_provider_policy_registry_get_field \
        "$policy_key" \
        "priority")" \
    "Provider Policy priority is incorrect."


assert_equals \
    "true" \
    "$(stoleus_provider_policy_registry_get_field \
        "$policy_key" \
        "enabled")" \
    "Provider Policy enabled state is incorrect."


assert_equals \
    "os-family=debian" \
    "$(stoleus_provider_policy_registry_get_field \
        "$policy_key" \
        "conditions")" \
    "Provider Policy conditions are incorrect."


assert_equals \
    "package,linux" \
    "$(stoleus_provider_policy_registry_get_field \
        "$policy_key" \
        "tags")" \
    "Provider Policy tags are incorrect."


set +e

stoleus_provider_policy_registry_register \
    "capability" \
    "package-management" \
    "apt-provider" \
    >/dev/null 2>&1

duplicate_exit_code=$?

set -e


assert_equals \
    "8" \
    "$duplicate_exit_code" \
    "Duplicate Provider Policy should return code 8."


set +e

stoleus_provider_policy_registry_register \
    "invalid-type" \
    "package-management" \
    "apt-provider" \
    >/dev/null 2>&1

invalid_subject_type_exit_code=$?

set -e


assert_equals \
    "6" \
    "$invalid_subject_type_exit_code" \
    "Invalid Provider Policy subject type should return code 6."


set +e

stoleus_provider_policy_registry_register \
    "capability" \
    "package-management" \
    "dnf-provider" \
    "invalid" \
    >/dev/null 2>&1

invalid_priority_exit_code=$?

set -e


assert_equals \
    "6" \
    "$invalid_priority_exit_code" \
    "Invalid Provider Policy priority should return code 6."


set +e

stoleus_provider_policy_registry_register \
    "capability" \
    "package-management" \
    "dnf-provider" \
    "50" \
    "maybe" \
    >/dev/null 2>&1

invalid_enabled_exit_code=$?

set -e


assert_equals \
    "6" \
    "$invalid_enabled_exit_code" \
    "Invalid Provider Policy enabled state should return code 6."


printf '%s\n' \
    "PASS: Provider Policy Registry tests completed successfully."

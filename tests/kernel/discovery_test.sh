#!/usr/bin/env bash

# ==============================================================================
# Stoleus Framework - Discovery Subsystem Tests
# ==============================================================================

set -Eeuo pipefail


TEST_ROOT="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." &&
    pwd
)"

PROJECT_ROOT="$TEST_ROOT"

source "${PROJECT_ROOT}/kernel/kernel.sh"


TEST_TEMP_ROOT=""


cleanup() {

    if [[ -n "$TEST_TEMP_ROOT" && -d "$TEST_TEMP_ROOT" ]]; then
        rm -rf "$TEST_TEMP_ROOT"
    fi
}


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


trap cleanup EXIT


stoleus_kernel_initialize


TEST_TEMP_ROOT="$(
    mktemp -d
)"


mkdir -p \
    "${TEST_TEMP_ROOT}/modules/chrony" \
    "${TEST_TEMP_ROOT}/modules/docker" \
    "${TEST_TEMP_ROOT}/modules/.hidden" \
    "${TEST_TEMP_ROOT}/providers/apt"


printf '%s\n' '# test manifest' \
    > "${TEST_TEMP_ROOT}/modules/chrony/manifest.sh"

printf '%s\n' 'component: docker' \
    > "${TEST_TEMP_ROOT}/modules/docker/manifest.yaml"

printf '%s\n' '{"provider":"apt"}' \
    > "${TEST_TEMP_ROOT}/providers/apt/manifest.json"


# ==============================================================================
# Replace default roots with isolated test roots.
# ==============================================================================

STOLEUS_DISCOVERY_ROOT_CATEGORIES=()
STOLEUS_DISCOVERY_ROOT_PATHS=()

stoleus_discovery_reset

stoleus_discovery_add_root \
    "modules" \
    "${TEST_TEMP_ROOT}/modules"

stoleus_discovery_add_root \
    "providers" \
    "${TEST_TEMP_ROOT}/providers"


# ==============================================================================
# Execute discovery.
# ==============================================================================

stoleus_discovery_scan


record_count="${#STOLEUS_DISCOVERY_RECORD_PATHS[@]}"

assert_equals \
    "3" \
    "$record_count" \
    "Discovery should create exactly three records."


assert_equals \
    "modules" \
    "${STOLEUS_DISCOVERY_RECORD_CATEGORIES[0]}" \
    "First record category is incorrect."

assert_equals \
    "chrony" \
    "${STOLEUS_DISCOVERY_RECORD_NAMES[0]}" \
    "Plugin order should be lexical."

assert_equals \
    "docker" \
    "${STOLEUS_DISCOVERY_RECORD_NAMES[1]}" \
    "Second plugin should be docker."

assert_equals \
    "providers" \
    "${STOLEUS_DISCOVERY_RECORD_CATEGORIES[2]}" \
    "Third record should be a provider."

assert_equals \
    "apt" \
    "${STOLEUS_DISCOVERY_RECORD_NAMES[2]}" \
    "Provider name should be apt."


if [[ "${STOLEUS_DISCOVERY_RECORD_MANIFESTS[0]}" != *"/manifest.sh" ]]; then
    fail "Chrony Bash manifest was not discovered."
fi


if [[ "${STOLEUS_DISCOVERY_RECORD_MANIFESTS[1]}" != *"/manifest.yaml" ]]; then
    fail "Docker YAML manifest was not discovered."
fi


if [[ "${STOLEUS_DISCOVERY_RECORD_MANIFESTS[2]}" != *"/manifest.json" ]]; then
    fail "APT JSON manifest was not discovered."
fi


# ==============================================================================
# Verify scan idempotency.
# ==============================================================================

stoleus_discovery_scan

assert_equals \
    "3" \
    "${#STOLEUS_DISCOVERY_RECORD_PATHS[@]}" \
    "Repeated scanning must not duplicate records."


# ==============================================================================
# Verify roots cannot change after scanning.
# ==============================================================================

set +e

stoleus_discovery_add_root \
    "commands" \
    "${TEST_TEMP_ROOT}/commands" \
    >/dev/null 2>&1

add_root_exit_code=$?

set -e


assert_equals \
    "8" \
    "$add_root_exit_code" \
    "Adding a root after scanning should return conflict code 8."


printf '%s\n' \
    "PASS: Discovery subsystem tests completed successfully."
